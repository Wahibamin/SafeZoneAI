import 'package:uuid/uuid.dart';
import '../../../core/database/database_helper.dart';
import '../domain/benchmark_metrics.dart';

class BenchmarkService {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();
  final List<double> _latenciesMs = [];
  int _droppedFrames = 0;
  String _accelerator = 'cpu';
  int _evaluated = 0;
  double? _startedMs;
  double? _lastMs;
  final Stopwatch _clock = Stopwatch()..start();

  BenchmarkService({required DatabaseHelper dbHelper}) : _dbHelper = dbHelper;

  void recordFrameTelemetry({
    required double inferenceMs,
    required bool dropped,
    required String accelerator,
  }) {
    _accelerator = accelerator;
    if (dropped) {
      _droppedFrames++;
      return;
    }
    if (inferenceMs > 0) {
      final now = _clock.elapsedMicroseconds / 1000.0;
      _startedMs ??= now - inferenceMs;
      _lastMs = now;
      _evaluated++;
      _latenciesMs.add(inferenceMs);
      if (_latenciesMs.length > 500) {
        _latenciesMs.removeAt(0);
      }
    }
  }

  BenchmarkSummary computeSummary() {
    if (_latenciesMs.isEmpty) {
      return BenchmarkSummary(
        totalFramesEvaluated: 0,
        droppedFrames: _droppedFrames,
        averageInferenceFps: 0.0,
        medianLatencyMs: 0.0,
        p95LatencyMs: 0.0,
        minLatencyMs: 0.0,
        maxLatencyMs: 0.0,
        accelerator: _accelerator,
      );
    }

    final sorted = List<double>.from(_latenciesMs)..sort();
    final n = sorted.length;
    final median = n.isOdd
        ? sorted[n ~/ 2]
        : (sorted[(n ~/ 2) - 1] + sorted[n ~/ 2]) / 2.0;
    final p95Index = ((n - 1) * 0.95).round().clamp(0, n - 1);
    final p95 = sorted[p95Index];
    final elapsed = _lastMs! - _startedMs!;
    final fps = elapsed > 0 ? _evaluated * 1000.0 / elapsed : 0.0;

    return BenchmarkSummary(
      totalFramesEvaluated: _evaluated,
      droppedFrames: _droppedFrames,
      averageInferenceFps: fps,
      medianLatencyMs: median,
      p95LatencyMs: p95,
      minLatencyMs: sorted.first,
      maxLatencyMs: sorted.last,
      accelerator: _accelerator,
    );
  }

  Future<PerformanceSample> saveCurrentSampleToDb({String? sessionId}) async {
    final summary = computeSummary();
    final sample = PerformanceSample(
      id: 'prf-${_uuid.v4().substring(0, 8)}',
      sessionId: sessionId,
      sampledAt: DateTime.now().toUtc().toIso8601String(),
      fps: summary.averageInferenceFps,
      inferenceMs: summary.medianLatencyMs,
      droppedFrames: summary.droppedFrames,
      accelerator: summary.accelerator,
    );
    final db = await _dbHelper.database;
    await db.insert('performance_samples', sample.toMap());
    return sample;
  }

  Future<List<PerformanceSample>> listSavedSamples({int limit = 50}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'performance_samples',
      orderBy: 'sampled_at DESC',
      limit: limit,
    );
    return rows.map(PerformanceSample.fromMap).toList();
  }

  void reset() {
    _latenciesMs.clear();
    _evaluated = 0;
    _startedMs = null;
    _lastMs = null;
    _droppedFrames = 0;
  }
}
