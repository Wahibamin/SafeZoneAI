"""Small, dependency-free geometry and mask-decision helpers for SafeZone Lite.

This module never predicts person identity. Only crop-detection hypotheses are
considered; ambiguous results yield 'unknown' rather than a false event.
"""
from dataclasses import dataclass
from typing import Sequence


def overlap_ratio(a, b):
    ix1, iy1 = max(a[0], b[0]), max(a[1], b[1])
    ix2, iy2 = min(a[2], b[2]), min(a[3], b[3])
    intersection = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    area1 = max(1, (a[2] - a[0]) * (a[3] - a[1]))
    area2 = max(1, (b[2] - b[0]) * (b[3] - b[1]))
    return intersection / min(area1, area2)


def unique_faces(faces):
    """Merge multiple overlapping Haar rectangles for the same face."""
    normalized = []
    for x, y, w, h in faces:
        normalized.append((int(x), int(y), int(x + w), int(y + h)))
    normalized.sort(key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), reverse=True)
    unique = []
    for box in normalized:
        if not any(overlap_ratio(box, other) >= 0.45 for other in unique):
            unique.append(box)
    return unique


def expand_face(face, frame_width, frame_height):
    """Generous face crop incl. chin and mask, bounded by the input frame."""
    x1, y1, x2, y2 = face
    w, h = x2 - x1, y2 - y1
    return (max(0, int(x1 - .18*w)), max(0, int(y1 - .12*h)),
            min(frame_width, int(x2 + .18*w)),
            min(frame_height, int(y2 + .25*h)))


@dataclass(frozen=True)
class MaskHypothesis:
    status: str
    score: float
    box: tuple


def decide_mask(hypotheses: Sequence[MaskHypothesis], width, height,
                minimum_score=0.50, conflicting_score=0.55):
    """Return (status, score) for a single face crop.

    Deduplicates all same-category boxes by max score, not IoU. A clearly
    confident disagreement between compliant and non-compliant gives UNKNOWN.
    A single winner does not prove the model is calibrated.
    """
    if width <= 0 or height <= 0:
        return 'unknown', 0.0
    accepted = []
    for d in hypotheses:
        if d.status not in {'with_mask', 'without_mask', 'incorrect_mask'}:
            continue
        if d.score < minimum_score:
            continue
        x1, y1, x2, y2 = d.box
        if x2 <= x1 or y2 <= y1:
            continue
        cx = (x1+x2)/2 / width
        cy = (y1+y2)/2 / height
        area = (x2-x1) * (y2-y1) / (width*height)
        # Exclude tiny predictions likely to be eyes or background noise.
        if not (0.06 <= cx <= .94 and .06 <= cy <= .94 and area >= .025):
            continue
        accepted.append(d)
    if not accepted:
        return 'unknown', 0.0
    best_mask = max((d.score for d in accepted if d.status == 'with_mask'), default=0.0)
    best_violation = max((d.score for d in accepted if d.status in ('without_mask', 'incorrect_mask')), default=0.0)
    # Conservative: if the model has strong evidence for both categories, no logging.
    if best_mask >= conflicting_score and best_violation >= conflicting_score:
        return 'unknown', max(best_mask, best_violation)
    best = max(accepted, key=lambda d:d.score)
    return best.status, best.score
