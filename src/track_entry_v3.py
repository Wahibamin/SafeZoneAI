"""SafeZone AI - cautious crossing prototype v3 (Windows / YOLO11n / ByteTrack).

This prototype prioritizes avoiding false counts from cropped bodies, changes in
pose and bounding-box jumps. It intentionally DOES NOT count if it cannot see
an entire person; move the camera to a side view of a real doorway / use a phone
recording if your laptop's field of view is too narrow.

Commands:
    .\\.venv\\Scripts\\python.exe track_entry_v3.py --source 0 --mirror
    .\\.venv\\Scripts\\python.exe track_entry_v3.py --source 0 --position 0.5
    .\\.venv\\Scripts\\python.exe track_entry_v3.py --source "v1.mp4"

This counts CROSSES only, not PPE violations or unique employees. Q=quit R=reset.
"""
from __future__ import annotations

import argparse
import csv
import statistics
import sys
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


@dataclass
class TrackState:
    last_frame: int = 0
    points: deque = field(default_factory=lambda: deque(maxlen=3))
    last_raw: float | None = None
    stable_side: int = 0
    origin_anchor: float | None = None
    candidate_side: int = 0
    candidate_frames: int = 0
    reference_height: float | None = None
    last_event_at: float = -1e9


class CautiousCounter:
    """Conservative, fail-closed line counting with stable per-track positions.

    Coordinates are frame pixel units; no cv2 / YOLO import required for tests.
    """

    def __init__(self, orientation="vertical", position=.50, margin=.10,
                 stable_frames=4, min_span=.28, cooldown=3.0,
                 expiry_frames=40, max_size_change=.33, max_step=.19):
        self.orientation = orientation
        self.position = position
        self.margin = margin
        self.stable_frames = stable_frames
        self.min_span = min_span
        self.cooldown = cooldown
        self.expiry_frames = expiry_frames
        self.max_size_change = max_size_change
        self.max_step = max_step
        self.states: dict[int, TrackState] = {}
        self.entered = 0
        self.exited = 0

    @staticmethod
    def inspect_box(box, width, height):
        """Quality gate: a detector box near an image border is not full-body evidence."""
        x1, y1, x2, y2 = box
        bw, bh = x2 - x1, y2 - y1
        if bw <= 0 or bh <= 0:
            return False, "INVALID_BOX"
        if y1 <= height * .035 or y2 >= height * .965:
            return False, "PARTIAL_BODY"
        if x1 <= width * .012 or x2 >= width * .988:
            return False, "EDGE_CROP"
        if bh < height * .24 or bw < width * .05:
            return False, "TOO_SMALL"
        if bh > height * .90:
            return False, "TOO_CLOSE"
        return True, "OK"

    def update(self, track_id, box, width, height, frame_index, timestamp):
        """Return (event_or_None, status, anchor_xy) for one detection."""
        x1, y1, x2, y2 = box
        anchor_xy = ((x1 + x2) / 2.0, y2)
        if track_id is None:
            return None, "NO_TRACK_ID", anchor_xy

        good, reason = self.inspect_box(box, width, height)
        if not good:
            # Discard pre-crop history; re-observe a stable starting side.
            self.states.pop(track_id, None)
            return None, reason, anchor_xy

        dimension = width if self.orientation == "vertical" else height
        anchor = anchor_xy[0] if self.orientation == "vertical" else anchor_xy[1]
        bh = y2 - y1
        state = self.states.setdefault(track_id, TrackState())

        # Treat large instantaneous jumps / severe scale changes as unreliable
        # and re-arm on a known side rather than potentially count a false trip.
        if state.last_raw is not None:
            step = abs(anchor - state.last_raw) / dimension
            scale_change = abs(bh - state.reference_height) / max(1.0, state.reference_height)
            if step > self.max_step or scale_change > self.max_size_change:
                state = TrackState()
                self.states[track_id] = state
                reset_reason = "RESET_JUMP" if step > self.max_step else "RESET_SCALE"
            else:
                reset_reason = None
        else:
            reset_reason = None

        state.last_frame = frame_index
        state.last_raw = anchor
        state.reference_height = bh if state.reference_height is None else (state.reference_height * .9 + bh * .1)
        state.points.append(anchor)
        smooth = float(statistics.median(state.points))

        line = dimension * self.position
        guard = max(5.0, dimension * self.margin)
        if smooth < line - guard:
            side = -1
        elif smooth > line + guard:
            side = 1
        else:
            state.candidate_side = 0
            state.candidate_frames = 0
            return None, reset_reason or "GUARD_BAND", anchor_xy

        if side != state.candidate_side:
            state.candidate_side = side
            state.candidate_frames = 1
        else:
            state.candidate_frames += 1
        if state.candidate_frames < self.stable_frames:
            return None, reset_reason or "STABILIZING", anchor_xy

        if state.stable_side == 0:
            state.stable_side = side
            state.origin_anchor = smooth
            return None, "ARMED", anchor_xy

        if side == state.stable_side:
            # Preserve the furthest good starting coordinate, not last frame
            # coordinate, to prevent stationary jitter building fake travel.
            if side == -1:
                state.origin_anchor = min(state.origin_anchor, smooth)
            else:
                state.origin_anchor = max(state.origin_anchor, smooth)
            return None, "READY", anchor_xy

        span = abs(smooth - state.origin_anchor) / dimension
        if span < self.min_span:
            return None, "INSUFFICIENT_TRAVEL", anchor_xy
        if timestamp - state.last_event_at < self.cooldown:
            return None, "COOLDOWN", anchor_xy

        event = "IN" if state.stable_side == -1 and side == 1 else "OUT"
        if event == "IN":
            self.entered += 1
        else:
            self.exited += 1
        state.last_event_at = timestamp
        state.stable_side = side
        state.origin_anchor = smooth
        return event, "COUNTED", anchor_xy

    def expire(self, current_frame):
        for tid in list(self.states):
            if current_frame - self.states[tid].last_frame > self.expiry_frames:
                del self.states[tid]

    def reset(self):
        self.states.clear()
        self.entered = 0
        self.exited = 0


def parse_args():
    p = argparse.ArgumentParser(description="SafeZone AI v3 - cautious entry counting")
    p.add_argument("--source", default="0", help="Camera number or path to a video")
    p.add_argument("--model", default="yolo11n.pt")
    p.add_argument("--orientation", choices=("vertical", "horizontal"), default="vertical")
    p.add_argument("--position", type=float, default=.50, help="Gate 0..1 along image width/height")
    p.add_argument("--mirror", action="store_true", help="Horizontally flip image")
    p.add_argument("--reverse-direction", action="store_true", help="Swap IN/OUT")
    p.add_argument("--conf", type=float, default=.35)
    p.add_argument("--imgsz", type=int, default=512)
    p.add_argument("--margin", type=float, default=.10)
    p.add_argument("--stable-frames", type=int, default=4)
    p.add_argument("--min-span", type=float, default=.28)
    p.add_argument("--cooldown", type=float, default=3.0)
    p.add_argument("--log", default="entry_events_v3.csv")
    args = p.parse_args()
    if not (.15 < args.position < .85):
        p.error("--position must be between 0.15 and 0.85")
    if not (.02 <= args.margin <= .25):
        p.error("--margin must be between 0.02 and 0.25")
    if args.position <= args.margin or 1 - args.position <= args.margin:
        p.error("Gate margins must leave space on both sides")
    if not (.15 <= args.min_span <= .7):
        p.error("--min-span must be between 0.15 and 0.7")
    if args.stable_frames < 2 or args.cooldown < 0:
        p.error("--stable-frames >=2 and --cooldown >=0 required")
    return args


def open_capture(cv2, source):
    src = int(source) if source.isdigit() else source
    if isinstance(src, int) and sys.platform == "win32":
        cap = cv2.VideoCapture(src, cv2.CAP_DSHOW)
        if not cap.isOpened():
            cap.release()
            cap = cv2.VideoCapture(src)
    else:
        cap = cv2.VideoCapture(src)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    return cap


def main():
    import cv2
    from ultralytics import YOLO

    args = parse_args()
    cap = open_capture(cv2, str(args.source))
    if not cap.isOpened():
        raise SystemExit(f"Cannot open source: {args.source}")
    model = YOLO(args.model)
    counter = CautiousCounter(orientation=args.orientation, position=args.position,
                             margin=args.margin, stable_frames=args.stable_frames,
                             min_span=args.min_span, cooldown=args.cooldown)
    out = Path(args.log)
    out.parent.mkdir(parents=True, exist_ok=True)
    new = not out.exists() or out.stat().st_size == 0
    f = out.open("a", newline="", encoding="utf-8-sig" if new else "utf-8")
    writer = csv.writer(f)
    if new:
        writer.writerow(["time_local", "source", "track_id", "direction", "confidence"])
        f.flush()

    print("SafeZone AI v3 | Conservative counts: PARTIAL BODY = NO COUNT")
    print("Keep camera fixed and show head + feet. Q: quit | R: reset on-screen counters")
    count_frame = 0
    previous = time.perf_counter()
    fps = 0.0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                print("Stream ended or camera error.")
                break
            if args.mirror:
                frame = cv2.flip(frame, 1)
            count_frame += 1
            h, w = frame.shape[:2]
            results = model.track(frame, persist=True, tracker="bytetrack.yaml",
                                  classes=[0], conf=args.conf, imgsz=args.imgsz,
                                  verbose=False)[0]
            invalid_count = 0
            visible = 0
            timestamp = time.monotonic()
            if results.boxes is not None:
                visible = len(results.boxes)
                ids = (results.boxes.id.int().cpu().tolist()
                       if results.boxes.id is not None else [None] * visible)
                for box, tid in zip(results.boxes, ids):
                    coords = tuple(int(v) for v in box.xyxy[0].cpu().tolist())
                    confidence = float(box.conf.item())
                    event, status, (ax, ay) = counter.update(tid, coords, w, h, count_frame, timestamp)
                    if status in {"PARTIAL_BODY", "EDGE_CROP", "TOO_CLOSE", "TOO_SMALL", "INVALID_BOX", "NO_TRACK_ID"}:
                        invalid_count += 1
                    shown = ("OUT" if event == "IN" else "IN") if args.reverse_direction and event else event
                    if shown:
                        writer.writerow([datetime.now().astimezone().isoformat(timespec="seconds"),
                                         args.source, tid, shown, round(confidence, 3)])
                        f.flush()
                        print(f"{shown}: ID {tid} | IN {counter.entered} OUT {counter.exited}")
                    x1, y1, x2, y2 = coords
                    good = status not in {"PARTIAL_BODY", "EDGE_CROP", "TOO_CLOSE", "TOO_SMALL", "INVALID_BOX", "NO_TRACK_ID"}
                    color = (35, 210, 55) if good else (0, 170, 255)
                    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
                    cv2.putText(frame, f"ID {tid} {confidence:.0%} {status}",
                                (max(4, x1), max(79, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX,
                                .47, color, 2, cv2.LINE_AA)
                    cv2.circle(frame, (int(ax), int(ay)), 4, color, -1)
            counter.expire(count_frame)

            dimension = w if args.orientation == "vertical" else h
            gate = int(dimension * args.position)
            band = int(dimension * args.margin)
            if args.orientation == "vertical":
                for a, color in ((gate-band, (0, 155, 255)),
                                 (gate, (0, 255, 255)), (gate+band, (0, 155, 255))):
                    cv2.line(frame, (a, 64), (a, h), color, 2)
            else:
                for a, color in ((gate-band, (0, 155, 255)),
                                 (gate, (0, 255, 255)), (gate+band, (0, 155, 255))):
                    cv2.line(frame, (0, a), (w, a), color, 2)
            # Light guide to indicate the full-body visibility requirement.
            cv2.rectangle(frame, (int(.012*w), int(.035*h)),
                          (int(.988*w), int(.965*h)), (150, 140, 80), 1)
            now = time.perf_counter()
            instantaneous = 1 / max(1e-6, now - previous)
            fps = instantaneous if fps == 0 else .8 * fps + .2 * instantaneous
            previous = now
            cv2.rectangle(frame, (0, 0), (w, 64), (25, 25, 25), -1)
            displayed_in, displayed_out = ((counter.exited, counter.entered)
                                           if args.reverse_direction
                                           else (counter.entered, counter.exited))
            cv2.putText(frame, f"IN: {displayed_in}  OUT: {displayed_out}  Visible: {visible}",
                        (11, 26), cv2.FONT_HERSHEY_SIMPLEX, .63, (255, 255, 255), 2)
            cv2.putText(frame, f"FPS: {fps:.1f} | NOT COUNTED: {invalid_count} | Q quit / R reset",
                        (11, 52), cv2.FONT_HERSHEY_SIMPLEX, .43, (235, 235, 235), 1)
            cv2.imshow("SafeZone AI - Reliable Framing v3", frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), ord("Q"), 27):
                break
            if key in (ord("r"), ord("R")):
                counter.reset()
                print("On-screen counters reset; CSV history retained.")
    finally:
        cap.release()
        f.close()
        cv2.destroyAllWindows()
    print("Events file:", out.resolve())


if __name__ == "__main__":
    main()
