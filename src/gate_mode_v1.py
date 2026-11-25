"""SafeZone AI Gate Mode (pilot): one face at a time, sequential passes.

Classifies short *face visibility episodes* using video timestamps (not CPU
processing time) and writes at most one event per episode to the existing
SafeZone SQLite schema. This is NOT verified physical door-crossing detection,
identity tracking, or an access-control system. If an episode cannot be
classified safely, it is listed as REVIEW but NOT written as a violation.

Requires the existing best_mask_v4.pt and storage.py in this project.
"""
import argparse
import csv
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from uuid import uuid4

ALIASES = {
    'with_mask': 'with_mask', 'mask_proper': 'with_mask',
    'without_mask': 'without_mask', 'no_mask': 'without_mask',
    'mask_weared_incorrect': 'incorrect_mask',
    'mask_worn_incorrect': 'incorrect_mask',
    'incorrect_mask': 'incorrect_mask',
}
COLORS = {
    'compliant': (55, 205, 65), 'violation': (45, 65, 240),
    'review': (0, 190, 255),
}


def normalize(name):
    return ALIASES.get(str(name).strip().lower().replace(' ', '_').replace('-', '_'))


def overlap_min(a, b):
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[2], b[2]), min(a[3], b[3])
    area = max(0, x2-x1) * max(0, y2-y1)
    area_a = max(1, (a[2]-a[0])*(a[3]-a[1]))
    area_b = max(1, (b[2]-b[0])*(b[3]-b[1]))
    return area / min(area_a, area_b)


def group_face_predictions(preds):
    """One group per face, even when YOLO emits competing classes/boxes."""
    groups = []
    for item in sorted(preds, key=lambda d: -d[2]):
        for group in groups:
            if any(overlap_min(item[0], d[0]) >= 0.58 for d in group):
                group.append(item)
                break
        else:
            groups.append([item])
    return groups


def frame_evidence(predictions, threshold=0.48, conflict_margin=0.12):
    """Return face_present, categorical observation, confidence, box, reason.

    Ambiguous detection isn't automatically non-compliant. We accept one
    physical face; simultaneous multiple face groups are marked ambiguous.
    """
    groups = group_face_predictions(predictions)
    if not groups:
        return False, None, 0.0, None, 'NO FACE'
    if len(groups) != 1:
        return True, None, 0.0, None, 'MULTIPLE FACES - REVIEW'
    group = groups[0]
    best = max(group, key=lambda d: d[2])
    compliant = max((d for d in group if d[1] == 'with_mask'),
                    key=lambda d: d[2], default=None)
    bad = max((d for d in group if d[1] != 'with_mask'),
              key=lambda d: d[2], default=None)
    if compliant and bad and abs(compliant[2]-bad[2]) < conflict_margin:
        return True, None, best[2], best[0], 'CONFLICTING - REVIEW'
    winner = max((d for d in (compliant, bad) if d is not None),
                 key=lambda d: d[2])
    if winner[2] < threshold:
        return True, None, winner[2], winner[0], 'LOW CONFIDENCE - REVIEW'
    result = 'compliant' if winner[1] == 'with_mask' else 'violation'
    return True, result, winner[2], winner[0], winner[1]


@dataclass
class Passage:
    number: int
    start: float
    last_seen: float
    frames_visible: int = 0
    frames_decided: int = 0
    scores: dict = field(default_factory=lambda: {'compliant': 0., 'violation': 0.})
    counts: dict = field(default_factory=lambda: {'compliant': 0, 'violation': 0})
    ambiguous_frames: int = 0


@dataclass
class Decision:
    passage: int
    start: float
    end: float
    outcome: str
    confidence_fraction: float
    frames: int
    reason: str


class GateCounter:
    """Sequence-based passage episodes, no person identity or physical gate line.

    Inference may be slow: timestamps come from the video timeline, not from
    time.monotonic for prerecorded files. Real cameras use monotonic time.
    """
    def __init__(self, gap_seconds=0.80, min_votes=3, agreement=0.70,
                 min_visible=3, max_ambiguous_fraction=0.50):
        if gap_seconds <= 0 or min_votes < 1 or min_visible < 1 or not (0.5 < agreement <= 1):
            raise ValueError('Invalid gate counting parameters')
        self.gap_seconds = gap_seconds
        self.min_votes = min_votes
        self.agreement = agreement
        self.min_visible = min_visible
        self.max_ambiguous_fraction = max_ambiguous_fraction
        self.current = None
        self.next_number = 1
        self.decisions = []

    def _close(self):
        p = self.current
        if p is None:
            return None
        self.current = None
        votes = sum(p.counts.values())
        total = sum(p.scores.values())
        winner = max(p.scores, key=p.scores.get)
        fraction = p.scores[winner] / total if total else 0.0
        ambiguous_fraction = p.ambiguous_frames / max(1, p.frames_visible)
        if p.frames_visible < self.min_visible or votes < self.min_votes:
            outcome, reason = 'review', 'INSUFFICIENT FACE EVIDENCE'
        elif ambiguous_fraction > self.max_ambiguous_fraction:
            outcome, reason = 'review', 'TOO MANY UNCERTAIN FRAMES'
        elif fraction < self.agreement:
            outcome, reason = 'review', 'CONFLICTING MASK EVIDENCE'
        else:
            outcome, reason = winner, 'CONFIRMED BY MULTIPLE FRAMES'
        decision = Decision(p.number, p.start, p.last_seen, outcome,
                            fraction, p.frames_decided, reason)
        self.decisions.append(decision)
        return decision

    def observe(self, t, face_present, category=None, confidence=0.0):
        """Advance by frame timestamp. Returns closed Decision or None."""
        if category not in (None, 'compliant', 'violation'):
            raise ValueError('Unknown category')
        if not face_present and category is not None:
            raise ValueError('Cannot classify absent face')
        decision = None
        if self.current is not None and t-self.current.last_seen >= self.gap_seconds:
            decision = self._close()
        if face_present:
            if self.current is None:
                self.current = Passage(self.next_number, t, t)
                self.next_number += 1
            p = self.current
            p.last_seen = t
            p.frames_visible += 1
            if category is None:
                p.ambiguous_frames += 1
            else:
                p.frames_decided += 1
                p.counts[category] += 1
                p.scores[category] += max(0., min(1., confidence))
        return decision

    def finish(self):
        return self._close()


def source_value(value):
    return int(value) if value.isdecimal() else value


def main():
    p = argparse.ArgumentParser(description='SafeZone Gate Mode pilot: short face visibility episodes')
    p.add_argument('--source', default='v1.mp4', help='video path or camera index')
    p.add_argument('--model', default='best_mask_v4.pt')
    p.add_argument('--database', default='safezone_mask_gate_test.db')
    p.add_argument('--camera', default='Phone Gate Video')
    p.add_argument('--zone', default='Food Area - Mask Zone')
    p.add_argument('--audit', default='gate_review_audit.csv', help='all outcomes including review')
    p.add_argument('--mirror', action='store_true')
    p.add_argument('--rotate', choices=['0','90','180','270'], default='0')
    p.add_argument('--imgsz', type=int, default=640)
    p.add_argument('--conf', type=float, default=0.25, help='YOLO proposal threshold')
    p.add_argument('--min-vote-conf', type=float, default=0.48)
    p.add_argument('--gap', type=float, default=0.80, help='seconds of absent face separating passage episodes')
    p.add_argument('--min-votes', type=int, default=3)
    p.add_argument('--agreement', type=float, default=0.70)
    p.add_argument('--skip', type=int, default=1)
    p.add_argument('--threads', type=int, default=4)
    p.add_argument('--no-preview', action='store_true')
    a = p.parse_args()
    if not (0 < a.conf < 1 and 0 < a.min_vote_conf < 1 and 0.5 < a.agreement <= 1
            and a.skip >= 1 and a.imgsz >= 256 and a.gap > 0):
        p.error('Invalid inference or counting settings')
    if not Path(a.model).is_file():
        p.error('Missing model: '+a.model)
    import cv2
    import torch
    from ultralytics import YOLO
    from storage import EventStore

    torch.set_num_threads(max(1, a.threads))
    mask_model = YOLO(a.model)
    names = mask_model.names
    valid = {int(i): normalize(name) for i, name in
             (names.items() if isinstance(names, dict) else enumerate(names))}
    if set(valid.values()) != {'with_mask', 'without_mask', 'incorrect_mask'}:
        p.error(f'Model must have the 3 mask classes: {names}')
    src = source_value(a.source)
    cap = cv2.VideoCapture(src, cv2.CAP_DSHOW) if isinstance(src, int) and sys.platform == 'win32' else cv2.VideoCapture(src)
    if not cap.isOpened():
        raise SystemExit('Cannot open video / camera: '+a.source)
    video_mode = not isinstance(src, int)
    file_fps = cap.get(cv2.CAP_PROP_FPS) if video_mode else 0
    if file_fps <= 0:
        file_fps = 30.0
    counter = GateCounter(a.gap, a.min_votes, a.agreement)
    store = EventStore(a.database)
    run_id = uuid4().hex
    events_saved = 0
    frame_index = 0
    prev_clock = time.monotonic()
    fps_est = 0.0
    recent = 'READY'

    def record(decision):
        nonlocal events_saved, recent
        recent = (f'PASS {decision.passage}: {decision.outcome.upper()} | '
                  f'{decision.frames} votes')
        print(f'{recent} | video {decision.start:.1f}-{decision.end:.1f}s | '
              f'certainty share {decision.confidence_fraction:.1%} | {decision.reason}')
        if decision.outcome in ('compliant', 'violation'):
            store.add(run_id, a.camera, {
                'zone': a.zone, 'track_id': decision.passage, 'episode': 1,
                'outcome': decision.outcome,
                'statuses': {'mask': 'yes' if decision.outcome == 'compliant' else 'no'},
                'missing': ['mask'] if decision.outcome == 'violation' else [],
            })
            events_saved += 1

    print('SafeZone Gate Mode | sequential face passages ONLY (not verified gate crossings)')
    print('Uses video timestamps for prerecorded video. Q / ESC exits and saves summary.')
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            frame_index += 1
            if frame_index % a.skip:
                continue
            if a.rotate == '90':
                frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
            elif a.rotate == '180':
                frame = cv2.rotate(frame, cv2.ROTATE_180)
            elif a.rotate == '270':
                frame = cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
            if a.mirror:
                frame = cv2.flip(frame, 1)
            stamp = (frame_index-1) / file_fps if video_mode else time.monotonic()
            pred = mask_model.predict(frame, device='cpu', imgsz=a.imgsz,
                                      conf=a.conf, iou=0.45, verbose=False)[0]
            height, width = frame.shape[:2]
            candidates = []
            for b in pred.boxes:
                category = valid.get(int(b.cls[0].item()))
                if category is None:
                    continue
                x1, y1, x2, y2 = (int(v) for v in b.xyxy[0].tolist())
                bw, bh = x2-x1, y2-y1
                if bw < 22 or bh < 22 or not (0.38 <= bw/max(1, bh) <= 2.5):
                    continue
                if bw*bh < 0.00075*width*height:
                    continue
                candidates.append(((x1, y1, x2, y2), category, float(b.conf[0].item())))
            present, category, confidence, box, reason = frame_evidence(candidates, a.min_vote_conf)
            closed = counter.observe(stamp, present, category, confidence)
            if closed:
                record(closed)
            if not a.no_preview:
                color = COLORS.get(category, COLORS['review'])
                if box is not None:
                    x1, y1, x2, y2 = box
                    cv2.rectangle(frame, (x1,y1), (x2,y2), color, 2)
                    cv2.putText(frame, f'{reason} {confidence:.0%}',
                                (max(2,x1), max(30,y1-6)), cv2.FONT_HERSHEY_SIMPLEX,
                                0.58, color, 2, cv2.LINE_AA)
                cv2.rectangle(frame, (0,0), (width,85), (24,27,37), -1)
                cv2.putText(frame, 'SafeZone Gate Mode - PILOT', (8,29),
                            cv2.FONT_HERSHEY_SIMPLEX,0.72,(255,255,255),2,cv2.LINE_AA)
                cv2.putText(frame, f'Observed: {len(counter.decisions)} | Logged: {events_saved}',
                            (8,58),cv2.FONT_HERSHEY_SIMPLEX,0.58,(255,255,255),2,cv2.LINE_AA)
                cv2.putText(frame, recent, (8,height-12),
                            cv2.FONT_HERSHEY_SIMPLEX,0.50,(255,255,255),2,cv2.LINE_AA)
                # Preserve image proportions for tall phone footage.
                ratio = min(1.0, 850/max(1,height), 1100/max(1,width))
                if ratio < 1:
                    frame = cv2.resize(frame, (int(width*ratio), int(height*ratio)))
                cv2.imshow('SafeZone Gate Mode v1 - Q to exit', frame)
                if cv2.waitKey(1) & 0xFF in (ord('q'), 27):
                    break
            now = time.monotonic()
            dt = now-prev_clock
            fps_est = (1/dt if dt > 0 else fps_est) if fps_est == 0 else (0.8*fps_est+0.2/dt if dt > 0 else fps_est)
            prev_clock = now
    finally:
        last = counter.finish()
        if last:
            record(last)
        cap.release()
        cv2.destroyAllWindows()
        store.close()
        with open(a.audit,'w',newline='',encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(['passage','start_video_seconds','end_video_seconds','outcome','evidence_share',
                             'decided_frames','reason'])
            for d in counter.decisions:
                writer.writerow([d.passage, f'{d.start:.2f}', f'{d.end:.2f}',
                                 d.outcome, f'{d.confidence_fraction:.3f}', d.frames, d.reason])
        print('\n--- VIDEO / SESSION SUMMARY ---')
        for outcome in ('compliant','violation','review'):
            print(outcome.upper()+':',sum(1 for d in counter.decisions if d.outcome==outcome))
        print('Recorded to dashboard:', events_saved)
        print('Detailed report:',a.audit)
        print('Database:',a.database)
        print('NOTE: episodes of visible faces; no verified person identity or door crossing.')


if __name__ == '__main__':
    main()
