# Model inventory — 2026-11-20

Baseline selection is fixed to best_mask_v4.pt. No newer checkpoint was substituted.

| File | Bytes | Actual architecture | Task | Classes in actual order | Training input |
|---|---:|---|---|---|---|
| best_mask.pt | 6190122 | YOLOv8n | detect | 0: mask_weared_incorrect; 1: with_mask; 2: without_mask | 64 |

Full paths, SHA-256, architecture YAML, checkpoint versions, training arguments and recorded validation metrics: [model_inventory.json](evidence/model_inventory.json).

Checkpoint metrics are historical training validation records, not a new independent mobile accuracy evaluation. v4: precision .83434, recall .78887, mAP50 .85737, mAP50-95 .58876. best_mask: .62181/.23939/.2774/.17376. yolo11n is general COCO, not a mask model.

No .tflite/.onnx/args.yaml/data.yaml or evaluation CSV files were found outside the training venv in the source project. Dataset paths in checkpoints are Colab paths and were not assumed present locally. Training reference video v1.mp4 was used locally without uploading it.
| best_mask_v4.pt | 5494042 | YOLO11n | detect | 0: with_mask; 1: without_mask; 2: mask_weared_incorrect | 640 |

Full paths, SHA-256, architecture YAML, checkpoint versions, training arguments and recorded validation metrics: [model_inventory.json](evidence/model_inventory.json).

Checkpoint metrics are historical training validation records, not a new independent mobile accuracy evaluation. v4: precision .83434, recall .78887, mAP50 .85737, mAP50-95 .58876. best_mask: .62181/.23939/.2774/.17376. yolo11n is general COCO, not a mask model.

No .tflite/.onnx/args.yaml/data.yaml or evaluation CSV files were found outside the training venv in the source project. Dataset paths in checkpoints are Colab paths and were not assumed present locally. Training reference video v1.mp4 was used locally without uploading it.
| yolo11n.pt | 5613764 | YOLO11n | detect | 80 COCO classes (see evidence JSON) | 640 |

Full paths, SHA-256, architecture YAML, checkpoint versions, training arguments and recorded validation metrics: [model_inventory.json](evidence/model_inventory.json).

Checkpoint metrics are historical training validation records, not a new independent mobile accuracy evaluation. v4: precision .83434, recall .78887, mAP50 .85737, mAP50-95 .58876. best_mask: .62181/.23939/.2774/.17376. yolo11n is general COCO, not a mask model.

No .tflite/.onnx/args.yaml/data.yaml or evaluation CSV files were found outside the training venv in the source project. Dataset paths in checkpoints are Colab paths and were not assumed present locally. Training reference video v1.mp4 was used locally without uploading it.
