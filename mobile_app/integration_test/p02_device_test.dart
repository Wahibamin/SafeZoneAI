import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:safezone_mobile/core/storage/app_private_storage.dart';
import 'package:safezone_mobile/core/utils/sha256_utils.dart';
import 'package:safezone_mobile/features/models/data/native_model_runtime.dart';
import 'package:safezone_mobile/features/camera/data/mobile_camera_service.dart';
import 'package:safezone_mobile/features/camera/domain/camera_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('P02 real camera supplies YUV planes in memory for both lenses', (tester) async {
    final camera = MobileCameraService();
    final storage = AppPrivateStorage();
    final before = await storage.countForbiddenMediaFiles();
    try {
      final rearFrame = camera.observeImageFrames().first.timeout(const Duration(seconds: 20));
      await camera.start(ownerTag: 'p02-device-test');
      final rear = await rearFrame;
      expect(rear.meta.lens, CameraLensDirectionType.rear);
      expect(rear.format, 'yuv420');
      expect(rear.planes.length, 3);
      expect(rear.planes.every((p) => p.bytes.isNotEmpty && p.bytesPerRow > 0), isTrue);
      await camera.switchLens();
      final front = await camera.observeImageFrames().first.timeout(const Duration(seconds: 20));
      expect(front.meta.lens, CameraLensDirectionType.front);
      expect(front.planes.length, 3);
      expect(front.planes.every((p) => p.bytes.isNotEmpty), isTrue);
      await camera.onAppBackgrounded();
      expect(camera.isRunning, isFalse);
      // Repeated lifecycle notifications must not lose the resume intent.
      await camera.onAppBackgrounded();
      await camera.onAppResumed(ownerTag: 'p02-device-test');
      expect(camera.isRunning, isTrue);
      final resumed = await camera.observeImageFrames().first.timeout(const Duration(seconds: 20));
      expect(resumed.planes.first.bytes.isNotEmpty, isTrue);
      await camera.stop(ownerTag: 'p02-device-test');
      expect(await storage.countForbiddenMediaFiles(), before);
      // ignore: avoid_print
      print('P02_CAMERA_EVIDENCE: rear ${rear.meta.width}x${rear.meta.height}, front ${front.meta.width}x${front.meta.height}; YUV420 3 planes; lifecycle resumed; no media written.');
    } finally { await camera.dispose(); }
  });
  testWidgets(
      'P02 real Android runtime rejects TFL3-only fixture during inspection and inference',
      (tester) async {
    final device = await NativeModelRuntime.channel
        .invokeMapMethod<String, dynamic>('getDeviceInfo');
    expect(device?['isFoldableTarget'], isTrue);
    final storage = AppPrivateStorage();
    const id = 'p02-negative-device-fixture';
    try {
      final relative = await storage.saveModelWeights(
          modelId: id, bytes: Sha256Utils.buildInvalidTfliteFixture());
      final file = await storage.resolveRelativeModelPath(relative);
      final runtime = NativeModelRuntime();
      await expectLater(
          runtime.inspect(file.path), throwsA(isA<PlatformException>()));
      await expectLater(
          runtime.smoke(file.path), throwsA(isA<PlatformException>()));
      // ignore: avoid_print
      print(
          'P02_DEVICE_NEGATIVE_EVIDENCE: $device; native inspect + smoke rejected invalid FlatBuffer. No positive smoke inference claimed.');
    } finally {
      await storage.deleteModelDirectory(id);
    }
  });
}
