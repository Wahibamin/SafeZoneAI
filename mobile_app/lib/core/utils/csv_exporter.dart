import '../../features/statistics/domain/session_models.dart';
import '../../features/benchmark/domain/benchmark_metrics.dart';

/// Generates anonymized CSV text for detection_events and performance_samples.
/// Strictly excludes any personal identifiers, photos, or frame paths (ADR-006).
class CsvExporter {
  CsvExporter._();

  static String exportDetectionEvents(List<DetectionEventRecord> events) {
    final buffer = StringBuffer();
    buffer.writeln(
      'event_id,session_id,model_id,occurred_at_utc,safety_status,model_label,confidence,evidence_frames,duration_ms,mode',
    );
    for (final e in events) {
      final conf = e.confidence != null ? e.confidence!.toStringAsFixed(4) : '';
      final dur = e.durationMs?.toString() ?? '';
      buffer.writeln(
        '${_esc(e.id)},${_esc(e.sessionId)},${_esc(e.modelId ?? "")},${_esc(e.occurredAt)},${_esc(e.safetyStatus)},${_esc(e.modelLabel ?? "")},$conf,${e.evidenceFrames},$dur,${_esc(e.mode)}',
      );
    }
    return buffer.toString();
  }

  static String exportPerformanceSamples(List<PerformanceSample> samples) {
    final buffer = StringBuffer();
    buffer.writeln(
      'sample_id,session_id,sampled_at_utc,fps,inference_ms,dropped_frames,accelerator',
    );
    for (final s in samples) {
      buffer.writeln(
        '${_esc(s.id)},${_esc(s.sessionId ?? "")},${_esc(s.sampledAt)},${s.fps.toStringAsFixed(2)},${s.inferenceMs.toStringAsFixed(2)},${s.droppedFrames},${_esc(s.accelerator)}',
      );
    }
    return buffer.toString();
  }

  static String _esc(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
