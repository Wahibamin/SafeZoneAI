# Colab TFLite import guide

Release Candidate baseline: Profile APK archive `backups/release_candidate_20261120_0425/SafeZoneAI-Mobile-Profile-RC.apk`, SHA-256 `8e5e3f23a8286bd1d6ee897a5ec7b5ff45b8ebd674e7e9ede57e8ee76be4694b`. Keep `SafeZone v4 float32` as the active reference; retain `SafeZone v4 float16` only as a comparison candidate.

## Required Colab handoff

Provide a `.tflite` file and its matching `model.json`/`safezone.json` sidecar. The JSON must match the exact file SHA-256 and declare schema version 1, `format: tflite`, detection labels/mapping, input shape/layout/dtype/color/normalization, and output shape/layout/dtype/coordinate units. State the YOLO adapter explicitly (`yolo_raw` or the supported `yolo26_end2end`) and declare `output.nms: false`.

For the current reference contract, the expected input is `[1,640,640,3]`, `NHWC`, `float32`, RGB `/255`; output is raw `[1,7,8400]`, `BCN`, float32, xywh pixel coordinates, three classes, and no embedded NMS. A different contract is acceptable only if the existing contract validator and supported adapter accept it; do not bypass validation or silently reinterpret tensors.

## Import and safe evaluation

1. Copy the `.tflite` and JSON sidecar to the phone.
2. Open **استيراد**, choose the JSON sidecar, then choose the `.tflite` through Android SAF.
3. Confirm the displayed tensor inspection and SHA-256. A duplicate SHA-256 is rejected safely.
4. In **النماذج**, use **فحص** first. This smoke test does not change the active model.
5. Review Metadata/contract, labels, input/output dimensions, coordinate units, adapter, and NMS status.
6. Only then choose **تفعيل**. It performs a real inference; failure rolls back to FP32 automatically.
7. Run a short, thermally safe camera smoke check. Do not start endurance while Thermal Status is elevated.

The import operation registers a pending model and does not activate it automatically. Never delete FP32 or FP16 reference entries during candidate evaluation.
