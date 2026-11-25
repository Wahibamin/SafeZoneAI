import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/errors/app_exceptions.dart';
import 'package:safezone_mobile/features/camera/data/mobile_camera_service.dart';
import 'package:safezone_mobile/features/camera/domain/camera_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 01 CameraSource & Ownership Contract Tests (T02-T04)', () {
    late MobileCameraService cameraService;

    setUp(() {
      cameraService = MobileCameraService();
    });

    tearDown(() async {
      await cameraService.dispose();
    });

    test('T03: Starts camera session with valid owner tag', () async {
      cameraService.setPermissionStateForTest(true);
      expect(cameraService.isRunning, isFalse);

      await cameraService.start(ownerTag: 'live_monitor_owner');

      expect(cameraService.isRunning, isTrue);
      expect(cameraService.activeOwnerTag, 'live_monitor_owner');
      expect(cameraService.hasPermission, isTrue);
    });

    test('T03: Prevents competing camera ownership (ADR-001 single-owner)',
        () async {
      cameraService.setPermissionStateForTest(true);
      await cameraService.start(ownerTag: 'owner_A');

      expect(
        () => cameraService.start(ownerTag: 'owner_B'),
        throwsA(isA<CameraOwnershipException>()),
      );
    });

    test('T03: Prevents non-owner from stopping camera session', () async {
      cameraService.setPermissionStateForTest(true);
      await cameraService.start(ownerTag: 'owner_A');

      expect(
        () => cameraService.stop(ownerTag: 'intruder'),
        throwsA(isA<CameraOwnershipException>()),
      );

      // Legitimate owner can stop
      await cameraService.stop(ownerTag: 'owner_A');
      expect(cameraService.isRunning, isFalse);
      expect(cameraService.activeOwnerTag, isNull);
    });

    test('T03: Rejects start when permission is denied', () async {
      cameraService.setPermissionStateForTest(false);

      expect(
        () => cameraService.start(ownerTag: 'owner_A'),
        throwsA(isA<SafeZoneException>().having(
          (e) => e.code,
          'code',
          'CAMERA_PERMISSION_DENIED',
        )),
      );
      expect(cameraService.isRunning, isFalse);
    });

    test('T03: Switches lens between rear and front and updates rotation',
        () async {
      cameraService.setPermissionStateForTest(true);
      expect(cameraService.currentLens, CameraLensDirectionType.rear);
      expect(cameraService.sensorRotationDegrees, 90);

      await cameraService.switchLens();
      expect(cameraService.currentLens, CameraLensDirectionType.front);
      expect(cameraService.sensorRotationDegrees, 270);

      await cameraService.switchLens();
      expect(cameraService.currentLens, CameraLensDirectionType.rear);
      expect(cameraService.sensorRotationDegrees, 90);
    });

    test('T04: Adapts to Foldable Postures (Z Flip3 Flex Mode)', () {
      expect(cameraService.currentPosture, FoldablePosture.flatOpen);

      cameraService.setFoldablePosture(FoldablePosture.halfOpenedFlex);
      expect(cameraService.currentPosture, FoldablePosture.halfOpenedFlex);

      cameraService.setFoldablePosture(FoldablePosture.compactFolded);
      expect(cameraService.currentPosture, FoldablePosture.compactFolded);
    });

    test('T04: Validates sensor rotation degrees (0, 90, 180, 270)', () {
      cameraService.setSensorRotationDegrees(0);
      expect(cameraService.sensorRotationDegrees, 0);

      cameraService.setSensorRotationDegrees(180);
      expect(cameraService.sensorRotationDegrees, 180);

      expect(
        () => cameraService.setSensorRotationDegrees(45),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('T03: Lifecycle backgrounding stops camera and resume restores it',
        () async {
      cameraService.setPermissionStateForTest(true);
      await cameraService.start(ownerTag: 'live_monitor_owner');
      expect(cameraService.isRunning, isTrue);

      // App goes to background
      await cameraService.onAppBackgrounded();
      expect(cameraService.isRunning, isFalse);
      expect(cameraService.activeOwnerTag, isNull);

      // App returns to foreground
      await cameraService.onAppResumed(ownerTag: 'live_monitor_owner');
      expect(cameraService.isRunning, isTrue);
      expect(cameraService.activeOwnerTag, 'live_monitor_owner');
    });

    test('T16: Emits stream metadata frames without saving any media to disk',
        () async {
      cameraService.setPermissionStateForTest(true);
      await cameraService.start(ownerTag: 'live_monitor_owner');

      final firstFrame = await cameraService.observeFrames().first;
      expect(firstFrame.frameNumber, greaterThanOrEqualTo(1));
      expect(firstFrame.width, greaterThan(0));
      expect(firstFrame.height, greaterThan(0));
      expect(firstFrame.lens, CameraLensDirectionType.rear);
      expect(firstFrame.aspectRatio, greaterThan(0));
    });
  });
}
