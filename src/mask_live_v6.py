"""SafeZone AI Lite v6: time-stable mask episode counting.

This is a CPU-oriented demo. One visible face at a time.
Unknown/conflicted results never become violations automatically.
Consecutive evidence is required; unknown observations with a visible face
do not rearm the counter or create duplicate events.
Counts are observation episodes, not distinct employees or gate entries.
"""
import argparse
import sys
import time
from pathlib import Path
from uuid import uuid4

from dataclasses import dataclass

ALIASES = {
    'with_mask': 'with_mask', 'mask_proper': 'with_mask',
    'without_mask': 'without_mask', 'no_mask': 'without_mask', 'mask_none': 'without_mask',
    'mask_weared_incorrect': 'incorrect_mask', 'mask_worn_incorrect': 'incorrect_mask',
    'incorrect_mask': 'incorrect_mask', 'mask_improper': 'incorrect_mask',
}
COLORS = {
    'with_mask': (60, 210, 65), 'without_mask': (50, 50, 235),
    'incorrect_mask': (0, 165, 250), 'unknown': (155, 155, 155),
}


def overlap(a, b):
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[2], b[2]), min(a[3], b[3])
    i = max(0, x2 - x1) * max(0, y2 - y1)
    aa = max(1, (a[2] - a[0]) * (a[3] - a[1]))
    bb = max(1, (b[2] - b[0]) * (b[3] - b[1]))
    return i / min(aa, bb)


def group_faces(detections):
    """Group cross-class overlapping face predictions using overlap/min-area.

    Each detection is (box_xyxy, normalized_status, confidence).
    Group boxes only when strong overlap; retain competing class evidence.
    """
    groups = []
    for det in sorted(detections, key=lambda d: -d[2]):
        for g in groups:
            if any(overlap(det[0], member[0]) >= 0.60 for member in g):
                g.append(det)
                break
        else:
            groups.append([det])
    return groups


def decide(detections, min_conf=0.56, conflict_margin=0.16):
    """Return (status, confidence, box, reason) for a *single* face.

    Duplicate predictions within the two violation subclasses are NOT
    contradictory for the safety decision. A with_mask vs. violation
    disagreement remains unknown unless the leading score is convincingly
    ahead. YOLO scores are not calibrated correctness probabilities.
    """
    groups = group_faces(detections)
    if not groups:
        return 'unknown', 0.0, None, 'NO FACE - NO LOG'
    if len(groups) > 1:
        return 'unknown', 0.0, None, 'MULTIPLE FACES - NO LOG'
    group = groups[0]
    best = max(group, key=lambda d: d[2])
    if best[2] < min_conf:
        return 'unknown', best[2], best[0], 'LOW CONFIDENCE - NO LOG'

    compliant = max((d for d in group if d[1] == 'with_mask'),
                    key=lambda d: d[2], default=None)
    violation = max((d for d in group if d[1] != 'with_mask'),
                    key=lambda d: d[2], default=None)
    if compliant and violation:
        if abs(compliant[2] - violation[2]) < conflict_margin:
            return 'unknown', best[2], best[0], 'CHECK MASK - NO LOG'
        winner = compliant if compliant[2] > violation[2] else violation
    else:
        winner = best
    if winner[2] < min_conf:
        return 'unknown', winner[2], winner[0], 'LOW CONFIDENCE - NO LOG'
    return winner[1], winner[2], winner[0], 'READY'


@dataclass
class StableEvent:
    episode: int
    status: str
    outcome: str


class StableSession:
    """Count confirmed state transitions only, not frames or unique people.

    Key fix: a detected but ambiguous face does not reset an existing episode.
    Reset occurs only after no face at all for absent_reset_seconds.
    """
    def __init__(self, stable_frames=18, stable_seconds=2.5, cooldown_seconds=5.0, absent_reset_seconds=12.0):
        self.stable_frames = stable_frames
        self.stable_seconds = stable_seconds
        self.cooldown_seconds = cooldown_seconds
        self.absent_reset_seconds = absent_reset_seconds
        self.candidate_category = None
        self.candidate_since = None
        self.candidate_streak = 0
        self.confirmed_category = None
        self.last_face_at = None
        self.last_event_at = None
        self.episode = 0

    def observe(self, status, now, face_present):
        if status not in ('with_mask','without_mask','incorrect_mask','unknown'):
            raise ValueError('Invalid status')
        if not face_present:
            self.candidate_category = None
            self.candidate_since = None
            self.candidate_streak = 0
            if self.last_face_at is not None and now - self.last_face_at >= self.absent_reset_seconds:
                self.confirmed_category = None
            return None
        self.last_face_at = now
        if status == 'unknown':
            self.candidate_category = None
            self.candidate_since = None
            self.candidate_streak = 0
            return None
        category = 'compliant' if status == 'with_mask' else 'violation'
        if self.candidate_category == category:
            self.candidate_streak += 1
        else:
            self.candidate_category = category
            self.candidate_since = now
            self.candidate_streak = 1
        if self.candidate_streak < self.stable_frames or (now - self.candidate_since) < self.stable_seconds:
            return None
        if category == self.confirmed_category:
            return None
        if self.last_event_at is not None and now - self.last_event_at < self.cooldown_seconds:
            return None
        self.confirmed_category = category
        self.last_event_at = now
        self.episode += 1
        return StableEvent(self.episode, status, category)


def camera_source(value):
    return int(value) if value.isdecimal() else value


def main():
    p = argparse.ArgumentParser(description='SafeZone AI v6 time-stable one-model mask detection')
    p.add_argument('--source', default='0', help='camera index or video file path')
    p.add_argument('--model', default='best_mask_v4.pt')
    p.add_argument('--database', default='safezone_mask.db')
    p.add_argument('--zone', default='Food Area - Mask Zone')
    p.add_argument('--camera', default='Laptop Webcam')
    p.add_argument('--mirror', action='store_true')
    p.add_argument('--imgsz', type=int, default=512)
    p.add_argument('--conf', type=float, default=0.28, help='YOLO proposal threshold')
    p.add_argument('--min-log-conf', type=float, default=0.56, help='require confidence for event')
    p.add_argument('--stable-frames', type=int, default=18)
    p.add_argument('--stable-seconds', type=float, default=2.5, help='minimum real seconds of same category')
    p.add_argument('--cooldown-seconds', type=float, default=5.0, help='minimum seconds between logged changes')
    p.add_argument('--absent-reset', type=float, default=12.0, help='reset only after this many seconds with no face')
    p.add_argument('--skip', type=int, default=1, help='infer every Nth frame; 1=every frame')
    p.add_argument('--threads', type=int, default=4)
    p.add_argument('--beep', action='store_true')
    a = p.parse_args()
    if a.skip < 1 or a.stable_frames < 1 or a.stable_seconds < 0 or a.cooldown_seconds < 0 or a.absent_reset <= 0 or a.imgsz < 256 or a.imgsz > 1280:
        p.error('Check --skip, --stable-frames and --imgsz')
    if not Path(a.model).is_file():
        p.error(f'Missing model: {a.model} | Download best_mask_v4.pt from Colab first.')

    import cv2
    import torch
    from ultralytics import YOLO
    from storage import EventStore

    torch.set_num_threads(max(1, a.threads))
    mask_model = YOLO(a.model)
    names = mask_model.names
    mapped = {(int(i), ALIASES.get(str(name).lower().strip().replace('-', '_').replace(' ', '_')))
              for i, name in (names.items() if isinstance(names, dict) else enumerate(names))}
    valid = {k: v for k, v in mapped if v is not None}
    if set(valid.values()) != {'with_mask', 'without_mask', 'incorrect_mask'}:
        p.error(f'Model does not contain the three correct mask classes: {names}')
    src = camera_source(a.source)
    cap = cv2.VideoCapture(src, cv2.CAP_DSHOW) if isinstance(src, int) and sys.platform == 'win32' else cv2.VideoCapture(src)
    if not cap.isOpened():
        raise SystemExit(f'Camera / video unavailable: {a.source}')
    if isinstance(src, int):
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    store = EventStore(a.database)
    logger = StableSession(stable_frames=a.stable_frames, stable_seconds=a.stable_seconds,
                           cooldown_seconds=a.cooldown_seconds, absent_reset_seconds=a.absent_reset)
    run_id = uuid4().hex
    last_status, last_score, last_box, last_reason = 'unknown', 0.0, None, 'STARTING'
    fps = 0.0
    tick = time.monotonic()
    frame_no = 0
    print('SafeZone v5 | Q exit | one face at a time | events != persons')
    print('Model:', a.model, '| database:', a.database)
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if a.mirror:
                frame = cv2.flip(frame, 1)
            frame_no += 1
            if frame_no % a.skip == 0:
                pred = mask_model.predict(frame, device='cpu', imgsz=a.imgsz,
                                          conf=a.conf, iou=0.45, verbose=False)[0]
                height, width = frame.shape[:2]
                candidates = []
                for b in pred.boxes:
                    klass = valid.get(int(b.cls[0].item()))
                    if klass is None:
                        continue
                    x1, y1, x2, y2 = [int(v) for v in b.xyxy[0].tolist()]
                    bw, bh = x2 - x1, y2 - y1
                    if bw < 25 or bh < 25 or not (0.38 <= bw / max(1, bh) <= 2.5):
                        continue
                    if bw * bh < 0.001 * (width * height):
                        continue
                    candidates.append(((x1, y1, x2, y2), klass, float(b.conf[0].item())))
                last_status, last_score, last_box, last_reason = decide(
                    candidates, min_conf=a.min_log_conf)
                event = logger.observe(last_status, time.monotonic(), face_present=bool(candidates))
                if event:
                    store.add(run_id, a.camera, {
                        'zone': a.zone, 'track_id': 1, 'episode': event.episode,
                        'outcome': event.outcome,
                        'statuses': {'mask': 'yes' if event.outcome == 'compliant' else 'no'},
                        'missing': ['mask'] if event.outcome == 'violation' else [],
                    })
                    print(f'Logged event {event.episode}: {event.status} -> {event.outcome}')
                    if a.beep and event.outcome == 'violation' and sys.platform == 'win32':
                        import winsound
                        winsound.MessageBeep(winsound.MB_ICONEXCLAMATION)
            color = COLORS[last_status]
            if last_box:
                x1, y1, x2, y2 = last_box
                cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
                label = ('REVIEW - NO LOG' if last_status == 'unknown'
                         else f'{last_status} {last_score:.0%}')
                cv2.putText(frame, label,
                            (max(2, x1), max(106, y1 - 10)), cv2.FONT_HERSHEY_SIMPLEX,
                            0.55, color, 2, cv2.LINE_AA)
            h, w = frame.shape[:2]
            cv2.rectangle(frame, (0, 0), (w, 94), (22, 26, 37), -1)
            if last_status == 'with_mask':
                headline = 'MASK OK'
            elif last_status in ('without_mask', 'incorrect_mask'):
                headline = 'MASK VIOLATION - ALERT'
            else:
                headline = last_reason
            cv2.putText(frame, 'SafeZone AI Lite v6', (10, 28),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.70, (255,255,255), 2, cv2.LINE_AA)
            cv2.putText(frame, headline, (10, 66), cv2.FONT_HERSHEY_SIMPLEX,
                        0.56, color, 2, cv2.LINE_AA)
            cv2.putText(frame, f'FPS: {fps:.1f} | Logged events: {logger.episode} | Q: EXIT',
                        (8, h - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.50, (255,255,255), 2, cv2.LINE_AA)
            cv2.imshow('SafeZone AI Lite v6 - Mask Monitor', frame)
            now = time.monotonic()
            inst = (1.0 / (now - tick)) if now > tick else 0.0
            fps = inst if fps == 0 else 0.7 * fps + 0.3 * inst
            tick = now
            if cv2.waitKey(1) & 0xFF in (ord('q'), 27):
                break
    finally:
        cap.release()
        cv2.destroyAllWindows()
        store.close()
        print('Database saved:', a.database)


if __name__ == '__main__':
    main()
