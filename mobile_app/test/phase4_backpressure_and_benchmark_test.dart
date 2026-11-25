import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/errors/app_exceptions.dart';
import 'package:safezone_mobile/features/detection/data/litert_yolo_inference_engine.dart';
import 'package:safezone_mobile/features/models/data/native_model_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native runtime absence cannot be reported as successful inference',
      () async {
    final engine = LiteRtYoloInferenceEngine();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeModelRuntime.channel,
            (_) async => throw PlatformException(code: 'NO_RUNTIME'));
    await expectLater(
        engine.switchModel(
            modelId: 'invalid',
            absoluteFilePath: '/invalid.tflite',
            inputWidth: 640,
            inputHeight: 640,
            labels: const {'0': 'unverified'}),
        throwsA(isA<PlatformException>()));
    expect(engine.isReady, isFalse);
    expect(engine.activeModelId, isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeModelRuntime.channel, null);
  });
  test('missing model/image and fabricated detections are rejected', () async {
    final engine = LiteRtYoloInferenceEngine();
    await expectLater(engine.inferFrame(frameNumber: 1, timestampMs: 1),
        throwsA(isA<ModelValidationException>()));
    expect(() => engine.setDiagnosticScenario([]),
        throwsA(isA<ModelValidationException>()));
    await expectLater(
        engine.setAccelerator('gpu'), throwsA(isA<ModelValidationException>()));
    expect(engine.activeAccelerator, 'cpu');
  });
}
