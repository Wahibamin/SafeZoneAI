# Benchmark guide

1. Transfer the packaged TFLite and JSON to the phone. In استيراد choose the JSON first if the file has no embedded safezone.json, then the TFLite. Activate in مكتبة النماذج; actual tensors and smoke inference must pass.
2. Open مختبر النماذج. Select a first model and optionally a second. To compare camera performance, activate one model, test CPU/GPU, start camera and read measured throughput, p50/p95, drops and process PSS. GPU failure is displayed; there is no fabricated success or silent CPU label change.
3. Camera inference FPS means completed frames over elapsed processing time, not preview FPS and not 1000/p50. Latency percentiles cover the native inference call (latest 500 samples). PSS is whole-process memory, sampled about once a second. Drops count incoming application image frames rejected while busy; upstream camera/driver losses are not measurable by this counter.
4. For comparable content choose the same local video with one or two compatible models. Sampling: at most 120 frames, 1-second timestamp spacing. Decode each timestamp once and feed the same bitmap to both models. First frame warmup is excluded, model order alternates. Work runs on the native worker; cancel preserves partial results. No camera images or decoded frames are written. The picker temporary video copy is removed after this explicit run; the original is untouched.
5. Export CSV through the Android save dialog. Rows carry model SHA-256, video SHA-256, sample timestamp, accelerator, native inference ms, pipeline ms, process memory and detection count. Video pipeline_fps is processing throughput for sampled frames, not real-time camera throughput or original video FPS. CPU/GPU runs should use matching sampled timestamps and hashes. No precision/recall/mAP is calculated without labeled ground truth.
6. Keep v4 FP32 as the first baseline. FP16 is a precision variant of the same checkpoint, not a substitute model. New Colab checkpoints require explicit selection and their own contracts/device acceptance.

Export in an isolated Colab/local environment with tools/colab_export_yolo11n_to_tflite.py; see its --help. All paths, family and adapter are explicit. Keep the selected checkpoint outside the fresh output directory. Do not install packages into an active training environment.

Device acceptance:
```powershell
python tools/device_acceptance.py stage
flutter drive --no-pub --driver test_driver/integration.dart --target integration_test/model_acceptance_test.dart -d R5CR90Z90AZ --keep-app-running --dart-define=ENDURANCE_SECONDS=600
python tools/device_acceptance.py collect
```
Use drive with keep-app-running: the installed Flutter SDK's `flutter test` integration runner uninstalls its app at teardown. A pre-test app backup was retained and restored after discovering that behavior. Never use uninstall/pm clear as routine testing of an existing user installation.

Timing boundary: video pipeline_ms/pipeline_fps cover per-model letterbox, input packing, inference and postprocessing. They exclude the shared video decoder, file hashing, PSS sampling and UI/transport; compare them as per-model processing measurements. Camera throughput includes the completed application loop and must be used for live FPS.
