import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../../../core/errors/app_exceptions.dart';
import '../domain/camera_source.dart';
import '../platform/camera_preview_provider.dart';

/// Concrete implementation of CameraSource designed for Samsung Galaxy Z Flip3.
/// Enforces single-owner session guard (ADR-001), manages lifecycle pause/resume,
/// supports real hardware preview and lens switching between rear and front cameras,
/// adapts to foldable postures (Flex Mode), and strictly enforces zero photo/video
/// retention to disk (ADR-003 & ADR-006).
class MobileCameraService implements CameraSource, CameraPreviewProvider {
  bool _isRunning = false;
  bool _hasPermission = true;
  bool _isPermanentlyDenied = false;
  bool _wasRunningBeforeBackground = false;
  bool _isTransitioning = false;
  bool _testMode = false;
  CameraLensDirectionType _currentLens = CameraLensDirectionType.rear;
  FoldablePosture _currentPosture = FoldablePosture.flatOpen;
  int _sensorRotationDegrees = 90;
  String? _activeOwnerTag;
  String? _errorMessage;
  int _frameCounter = 0;
  Timer? _frameTicker;

  CameraController? _controller;
  List<CameraDescription>? _availableCameras;

  final StreamController<CameraFrameMeta> _frameController =
      StreamController<CameraFrameMeta>.broadcast();
  final _imageController =
      StreamController<CameraImageFrame>.broadcast(sync: true);

  @override
  bool get isRunning => _isRunning;

  @override
  bool get hasPermission => _hasPermission;

  @override
  bool get isPermanentlyDenied => _isPermanentlyDenied;

  @override
  CameraLensDirectionType get currentLens => _currentLens;

  @override
  FoldablePosture get currentPosture => _currentPosture;

  @override
  int get sensorRotationDegrees => _sensorRotationDegrees;

  @override
  String? get activeOwnerTag => _activeOwnerTag;

  @override
  String? get errorMessage => _errorMessage;

  @override
  CameraController? get controller => _controller;

  void setPermissionStateForTest(
    bool granted, {
    bool permanentlyDenied = false,
  }) {
    _testMode = true;
    _hasPermission = granted;
    _isPermanentlyDenied = permanentlyDenied;
    if (!granted) {
      _errorMessage = permanentlyDenied
          ? 'تم رفض إذن الكاميرا بشكل دائم. يرجى تفعيله من إعدادات النظام.'
          : 'يرجى منح إذن الكاميرا لتشغيل المعاينة المباشرة.';
    } else {
      _errorMessage = null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final status = await ph.Permission.camera.status;
      if (status.isGranted) {
        _hasPermission = true;
        _isPermanentlyDenied = false;
        _errorMessage = null;
        return true;
      }
      final result = await ph.Permission.camera.request();
      _hasPermission = result.isGranted;
      _isPermanentlyDenied = result.isPermanentlyDenied;
      if (result.isPermanentlyDenied) {
        _errorMessage =
            'تم رفض إذن الكاميرا بشكل دائم. يرجى تفعيله من إعدادات النظام.';
      } else if (!result.isGranted) {
        _errorMessage = 'يرجى منح إذن الكاميرا لتشغيل المعاينة المباشرة.';
      } else {
        _errorMessage = null;
      }
      return _hasPermission;
    } catch (_) {
      if (_testMode) return _hasPermission;
      rethrow;
    }
  }

  @override
  Future<bool> openDeviceSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start({required String ownerTag}) async {
    if (_isRunning && _activeOwnerTag != null && _activeOwnerTag != ownerTag) {
      throw CameraOwnershipException(
        'Active owner is $_activeOwnerTag, rejected competing session from $ownerTag',
      );
    }

    if (_isTransitioning) return;
    _isTransitioning = true;

    try {
      final permitted = await requestPermission();
      if (!permitted) {
        throw const SafeZoneException(
          code: 'CAMERA_PERMISSION_DENIED',
          messageAr: 'يرجى منح إذن الكاميرا لتشغيل المعاينة المباشرة.',
        );
      }

      if (_isRunning &&
          _controller != null &&
          _controller!.value.isInitialized) {
        return;
      }

      _activeOwnerTag = ownerTag;

      // Attempt real hardware camera initialization
      await _initializeHardwareCamera();

      _isRunning = true;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e is SafeZoneException ? e.messageAr : e.toString();
      rethrow;
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _initializeHardwareCamera() async {
    try {
      _availableCameras ??= await availableCameras();
    } on MissingPluginException {
      if (!_testMode) rethrow;
      _startFallbackFrameTicker();
      return;
    } catch (e) {
      if (!_testMode) rethrow;
      _startFallbackFrameTicker();
      return;
    }

    if (_availableCameras == null || _availableCameras!.isEmpty) {
      if (!_testMode) {
        throw const ModelValidationException('لا توجد كاميرا متاحة.');
      }
      _startFallbackFrameTicker();
      return;
    }

    final targetDirection = _currentLens == CameraLensDirectionType.front
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    final cameraDesc = _availableCameras!.firstWhere(
      (c) => c.lensDirection == targetDirection,
      orElse: () => _availableCameras!.first,
    );

    _sensorRotationDegrees = cameraDesc.sensorOrientation;

    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
    }

    final newController = CameraController(
      cameraDesc,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await newController.initialize();
      _controller = newController;
    } catch (e) {
      await newController.dispose();
      rethrow;
    }

    await _startFrameStream(newController);
  }

  Future<void> _startFrameStream(CameraController ctrl) async {
    _frameTicker?.cancel();
    _frameTicker = null;

    try {
      await ctrl.startImageStream((CameraImage image) {
        if (!_isRunning || _frameController.isClosed) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        _frameCounter++;
        final meta = CameraFrameMeta(
          frameNumber: _frameCounter,
          timestampMs: now,
          width: image.width,
          height: image.height,
          sensorRotationDegrees: _imageRotation(ctrl),
          lens: _currentLens,
          posture: _currentPosture,
        );
        _frameController.add(meta);
        if (_imageController.hasListener && !_imageController.isClosed) {
          _imageController.add(CameraImageFrame(
              meta: meta,
              format: image.format.group.name,
              planes: List.unmodifiable(image.planes.map((p) =>
                  CameraFramePlane(
                      bytes: Uint8List.fromList(p.bytes),
                      bytesPerRow: p.bytesPerRow,
                      bytesPerPixel: p.bytesPerPixel)))));
        }
      });
    } catch (_) {
      rethrow;
    }
  }

  int _imageRotation(CameraController ctrl) {
    final device = switch (ctrl.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return _currentLens == CameraLensDirectionType.front
        ? (_sensorRotationDegrees + device) % 360
        : (_sensorRotationDegrees - device + 360) % 360;
  }

  void _startFallbackFrameTicker() {
    _frameTicker?.cancel();
    _frameTicker = Timer.periodic(const Duration(milliseconds: 66), (_) {
      if (!_isRunning || _frameController.isClosed) return;
      _frameCounter++;
      _frameController.add(
        CameraFrameMeta(
          frameNumber: _frameCounter,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          width: 1280,
          height: 720,
          sensorRotationDegrees: _sensorRotationDegrees,
          lens: _currentLens,
          posture: _currentPosture,
        ),
      );
    });
  }

  @override
  Future<void> stop({required String ownerTag}) async {
    if (_isRunning && _activeOwnerTag != null && _activeOwnerTag != ownerTag) {
      throw CameraOwnershipException(
        'Active owner is $_activeOwnerTag, cannot be stopped by $ownerTag',
      );
    }

    if (_isTransitioning) return;
    _isTransitioning = true;

    try {
      _frameTicker?.cancel();
      _frameTicker = null;

      if (_controller != null) {
        try {
          if (_controller!.value.isStreamingImages) {
            await _controller!.stopImageStream();
          }
        } catch (_) {}
        try {
          await _controller!.dispose();
        } catch (_) {}
        _controller = null;
      }

      _isRunning = false;
      _activeOwnerTag = null;
    } finally {
      _isTransitioning = false;
    }
  }

  @override
  Future<void> switchLens() async {
    if (_isTransitioning) return;

    _currentLens = _currentLens == CameraLensDirectionType.rear
        ? CameraLensDirectionType.front
        : CameraLensDirectionType.rear;

    _sensorRotationDegrees =
        _currentLens == CameraLensDirectionType.front ? 270 : 90;

    if (_isRunning && _activeOwnerTag != null) {
      final owner = _activeOwnerTag!;
      await stop(ownerTag: owner);
      await start(ownerTag: owner);
    }
  }

  @override
  void setFoldablePosture(FoldablePosture posture) {
    _currentPosture = posture;
  }

  @override
  void setSensorRotationDegrees(int degrees) {
    if (![0, 90, 180, 270].contains(degrees)) {
      throw ArgumentError('Rotation degrees must be 0, 90, 180, or 270');
    }
    _sensorRotationDegrees = degrees;
  }

  @override
  Stream<CameraFrameMeta> observeFrames() => _frameController.stream;
  @override
  Stream<CameraImageFrame> observeImageFrames() => _imageController.stream;

  @override
  Future<void> onAppBackgrounded() async {
    _wasRunningBeforeBackground = _wasRunningBeforeBackground || _isRunning;
    if (_isRunning && _activeOwnerTag != null) {
      await stop(ownerTag: _activeOwnerTag!);
    }
  }

  @override
  Future<void> onAppResumed({required String ownerTag}) async {
    if (_wasRunningBeforeBackground && _hasPermission) {
      _wasRunningBeforeBackground = false;
      await start(ownerTag: ownerTag);
    }
  }

  Future<void> dispose() async {
    _frameTicker?.cancel();
    _frameTicker = null;
    if (_controller != null) {
      try {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
      } catch (_) {}
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
    }
    await _frameController.close();
    await _imageController.close();
  }
}
