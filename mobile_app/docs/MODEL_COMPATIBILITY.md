# Model compatibility

APK compatibility is determined by actual tensors + metadata + native smoke inference, never file extension alone.

| Adapter | Required output | Interpretation | NMS |
|---|---|---|---|
| yolo_raw | [1,4+classes,N] BCN or [1,N,4+classes] BNC | xywh + class probabilities | class-aware runtime NMS |
| yolo26_end2end | YOLO26 family, [1,N,6] BNC | x1,y1,x2,y2,score,class_id | none |

Input: static batch 1 NHWC RGB. Float32, uint8 or int8 tensors with valid quantization parameters. Normalization mean=0 and positive std per channel. Labels must be contiguous from 0. Coordinates must explicitly be pixels or normalized in output.coordinates, supplied via model.json or embedded safezone.json. Shape alone cannot establish this.

Rejected with a reason: classification/segmentation/pose, multiple outputs, NCHW, dynamic dimensions, missing class map/coordinate units, inconsistent hash/tensors/metadata, fused NMS exports without an implemented adapter. Activating an incompatible candidate preserves a working previous interpreter when possible.

Only v4 YOLO11n FP32/FP16 has host numerical parity evidence in this session. YOLO26 adapter has contract tests, but no actual YOLO26 checkpoint was supplied for device validation. Do not label an arbitrary YOLO26 export as phone-tested.

A compatible new model needs no APK rebuild: package, transfer, import, inspect, smoke, activate. Different task heads/operators/layouts may require an app adapter update. No model is downloaded or automatically selected by the APK. The original baseline remains available for comparison.

Packaging tool: tools/package_compatible_model.py. It compares actual TFLite tensors to the explicit source checkpoint on the same reference image, determines units by parity, and creates a separate file plus manifest. It never sets compatibility.validated=true or claims a phone test.
