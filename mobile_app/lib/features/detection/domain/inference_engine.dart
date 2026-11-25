import 'detection_result.dart';
import '../../camera/domain/camera_source.dart';

/// Replaceable InferenceEngine adapter (ADR-002).
abstract class InferenceEngine {
  String get runtimeName;
  String? get activeModelId;
  String get activeAccelerator; // 'cpu' | 'gpu'
  int get droppedFramesCount;
  bool get isReady;
  Map<String, dynamic>? get lastSmokeEvidence;

  Future<void> setAccelerator(String accelerator);

  /// Loads model weights from app-private storage, runs a warmup smoke inference,
  /// and returns the warmup latency in milliseconds.
  Future<double> switchModel({
    required String modelId,
    required String absoluteFilePath,
    required int inputWidth,
    required int inputHeight,
    required Map<String, String> labels,
  });

  /// Runs inference on the latest camera frame with backpressure protection.
  /// If an inference is already in flight, drops the incoming frame rather than queuing unboundedly.
  Future<FrameInferenceOutput> inferFrame({
    required int frameNumber,
    required int timestampMs,
    int sensorRotationDegrees = 90,
    bool isFrontMirrored = false,
    CameraImageFrame? image,
    Map<String, dynamic>? contract,
    double confidenceThreshold = 0.45,
    double iouThreshold = 0.45,
  });

  /// Allows injecting controlled test detections for parity tests, edge cases, and Gate Mode validation.
  void setDiagnosticScenario(List<DetectionResult>? scenarioDetections);

  Future<void> dispose();
}
