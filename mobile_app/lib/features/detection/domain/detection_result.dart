class NormalizedBox {
  final double left; // 0.0 .. 1.0
  final double top; // 0.0 .. 1.0
  final double right; // 0.0 .. 1.0
  final double bottom; // 0.0 .. 1.0

  const NormalizedBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => (right - left).clamp(0.0, 1.0);
  double get height => (bottom - top).clamp(0.0, 1.0);
  double get centerX => left + width / 2.0;
  double get centerY => top + height / 2.0;
  double get area => width * height;
}

/// Unified DetectionResult contract from MODEL_CONTRACT.md:
/// {timestampMs, classId, label, confidence, bbox, modelId}
class DetectionResult {
  final int timestampMs;
  final int classId;
  final String label;
  final double confidence;
  final NormalizedBox bbox;
  final String modelId;

  const DetectionResult({
    required this.timestampMs,
    required this.classId,
    required this.label,
    required this.confidence,
    required this.bbox,
    required this.modelId,
  });
}

class FrameInferenceOutput {
  final int frameNumber;
  final int timestampMs;
  final double inferenceMs;
  final bool droppedByBackpressure;
  final String acceleratorUsed; // 'cpu' | 'gpu'
  final List<DetectionResult> detections;

  const FrameInferenceOutput({
    required this.frameNumber,
    required this.timestampMs,
    required this.inferenceMs,
    required this.droppedByBackpressure,
    required this.acceleratorUsed,
    required this.detections,
  });
}
