class PerformanceSample {
  final String id;
  final String? sessionId;
  final String sampledAt;
  final double fps;
  final double inferenceMs;
  final int droppedFrames;
  final String accelerator; // 'cpu' | 'gpu' | 'other' | 'unknown'

  const PerformanceSample({
    required this.id,
    this.sessionId,
    required this.sampledAt,
    required this.fps,
    required this.inferenceMs,
    required this.droppedFrames,
    required this.accelerator,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'sampled_at': sampledAt,
      'fps': fps,
      'inference_ms': inferenceMs,
      'dropped_frames': droppedFrames,
      'accelerator': accelerator,
    };
  }

  factory PerformanceSample.fromMap(Map<String, dynamic> map) {
    return PerformanceSample(
      id: map['id'] as String,
      sessionId: map['session_id'] as String?,
      sampledAt: map['sampled_at'] as String,
      fps: (map['fps'] as num).toDouble(),
      inferenceMs: (map['inference_ms'] as num).toDouble(),
      droppedFrames: map['dropped_frames'] as int,
      accelerator: map['accelerator'] as String,
    );
  }
}

class BenchmarkSummary {
  final int totalFramesEvaluated;
  final int droppedFrames;
  final double averageInferenceFps;
  final double medianLatencyMs; // p50
  final double p95LatencyMs; // p95
  final double minLatencyMs;
  final double maxLatencyMs;
  final String accelerator;

  const BenchmarkSummary({
    required this.totalFramesEvaluated,
    required this.droppedFrames,
    required this.averageInferenceFps,
    required this.medianLatencyMs,
    required this.p95LatencyMs,
    required this.minLatencyMs,
    required this.maxLatencyMs,
    required this.accelerator,
  });
}
