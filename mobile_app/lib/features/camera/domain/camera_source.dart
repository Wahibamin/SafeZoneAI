import 'dart:typed_data';

enum CameraLensDirectionType {
  rear,
  front,
}

enum FoldablePosture {
  flatOpen, // الشاشة مفتوحة بالكامل (180 درجة)
  halfOpenedFlex, // وضع الطي الجزئي Flex Mode (90-135 درجة على Z Flip3)
  compactFolded, // مطوية
}

class CameraFrameMeta {
  final int frameNumber;
  final int timestampMs;
  final int width;
  final int height;
  final int sensorRotationDegrees; // 0, 90, 180, 270
  final CameraLensDirectionType lens;
  final FoldablePosture posture;

  const CameraFrameMeta({
    required this.frameNumber,
    required this.timestampMs,
    required this.width,
    required this.height,
    required this.sensorRotationDegrees,
    required this.lens,
    required this.posture,
  });

  double get aspectRatio => height == 0 ? 1.0 : width / height;
}

/// Abstract contract for camera session ownership (ARCHITECTURE.md).
/// Ensures only ONE owner holds the live camera session at any time.
abstract class CameraSource {
  bool get isRunning;
  bool get hasPermission;
  bool get isPermanentlyDenied;
  CameraLensDirectionType get currentLens;
  FoldablePosture get currentPosture;
  int get sensorRotationDegrees;
  String? get activeOwnerTag;
  String? get errorMessage;

  Future<bool> requestPermission();
  Future<bool> openDeviceSettings();
  Future<void> start({required String ownerTag});
  Future<void> stop({required String ownerTag});
  Future<void> switchLens();
  void setFoldablePosture(FoldablePosture posture);
  void setSensorRotationDegrees(int degrees);
  Stream<CameraFrameMeta> observeFrames();
  Stream<CameraImageFrame> observeImageFrames();
  Future<void> onAppBackgrounded();
  Future<void> onAppResumed({required String ownerTag});
}

/// Owned in-memory planes. Never file paths; row/pixel strides preserve YUV420 layout.
class CameraFramePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  const CameraFramePlane(
      {required this.bytes, required this.bytesPerRow, this.bytesPerPixel});
}

class CameraImageFrame {
  final CameraFrameMeta meta;
  final String format;
  final List<CameraFramePlane> planes;
  const CameraImageFrame(
      {required this.meta, required this.format, required this.planes});
}
