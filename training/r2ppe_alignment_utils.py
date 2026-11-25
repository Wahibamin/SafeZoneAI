"""Portable R2PPE frame-index and COCO-to-YOLO geometry helpers."""
from __future__ import annotations


def annotation_index_to_video_frame(index: int, measured_fps: float) -> int:
    """Convert a 1-FPS annotation index to the nearest source-video frame."""
    if index < 0 or measured_fps <= 0:
        raise ValueError("index must be non-negative and FPS must be positive")
    return round(index * measured_fps)


def coco_xywh_to_yolo(box: tuple[float, float, float, float], width: int, height: int):
    """Convert pixel-space COCO (x,y,w,h) to normalized YOLO (cx,cy,w,h)."""
    x, y, box_w, box_h = box
    if width <= 0 or height <= 0 or box_w <= 0 or box_h <= 0:
        raise ValueError("image and box dimensions must be positive")
    return ((x + box_w / 2) / width, (y + box_h / 2) / height,
            box_w / width, box_h / height)


def yolo_to_coco_xywh(box: tuple[float, float, float, float], width: int, height: int):
    """Convert normalized YOLO (cx,cy,w,h) to pixel-space COCO (x,y,w,h)."""
    cx, cy, box_w, box_h = box
    if width <= 0 or height <= 0:
        raise ValueError("image dimensions must be positive")
    pixel_w, pixel_h = box_w * width, box_h * height
    return (cx * width - pixel_w / 2, cy * height - pixel_h / 2,
            pixel_w, pixel_h)
