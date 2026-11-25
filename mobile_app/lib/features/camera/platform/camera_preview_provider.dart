import 'package:camera/camera.dart';

/// Plugin-specific preview bridge, deliberately outside the camera domain contract.
abstract class CameraPreviewProvider {
  CameraController? get controller;
}
