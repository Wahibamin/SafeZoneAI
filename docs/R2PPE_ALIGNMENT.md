# R2PPE frame alignment and data review

The local frame extraction initially treated the COCO image filename suffix as an AVI frame number. The R2PPE parser enumerates annotation frame URLs sampled at 1 frame per second. For a source video measured at approximately 30 FPS, annotation index `n` therefore maps to approximately `round(n * measured_fps)` in the video, rather than raw frame `n`.

The alignment diagnosis used the official parser and converter, compared random seeking, sequential decoding, and timestamp seeking, and checked COCO-to-YOLO coordinate round trips. The resulting V7.1 preparation had 7,449 image/label pairs across train, validation, and reserved test, with no video overlap. These structural checks do not certify semantic correctness.

Manual review found boxes placed on walls, clothing, or other non-face regions. One frame was excluded, but remaining labels still require review. A baseline evaluated on the V7.1 validation split produced near-zero mAP50. The derived set is **not approved for training**, and the reserved test split was not used.

Primary references:

- [R2PPE data parser](https://github.com/yangwanzhao/R2PPE-DATASET/blob/main/script_data_parse_v7.py)
- [R2PPE V7 to COCO converter](https://github.com/yangwanzhao/R2PPE-DATASET/blob/main/script_data_v72coco.py)
- [R2PPE COCO to YOLO converter](https://github.com/yangwanzhao/R2PPE-DATASET/blob/main/script_data_coco2yolo.py)
- [R2PPE paper](https://www.nature.com/articles/s41597-024-04355-0)

The primary source code is GPL-3.0. The paper states CC BY 4.0 subject to third-party exceptions. Confirm exact asset rights before redistribution.
