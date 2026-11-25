import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../../core/storage/app_private_storage.dart';
import '../../models/data/native_model_runtime.dart';
import '../../models/domain/model_entry.dart';

/// Samples one decoded bitmap for both models. Results contain timings, never media.
class VideoBenchmarkService extends ChangeNotifier {
  bool running = false;
  bool _cancelled = false;
  int completed = 0;
  int planned = 0;
  String? message;
  String videoSha256 = '';
  String accelerator = 'cpu';
  final List<Map<String, dynamic>> rows = [];
  void cancel() {
    _cancelled = true;
  }

  Future<void> run(
      {required String videoPath,
      required List<ModelEntry> models,
      required AppPrivateStorage storage,
      required String accelerator,
      int maxFrames = 120,
      int intervalMs = 1000}) async {
    if (running) throw StateError('Benchmark already running');
    if (models.isEmpty ||
        models.length > 2 ||
        maxFrames < 1 ||
        intervalMs < 1) {
      throw ArgumentError(
          'Select one or two compatible models and valid sampling limits');
    }
    running = true;
    _cancelled = false;
    completed = 0;
    planned = 0;
    rows.clear();
    message = null;
    this.accelerator = accelerator;
    notifyListeners();
    try {
      videoSha256 =
          (await sha256.bind(File(videoPath).openRead()).first).toString();
      final configs = <Map<String, dynamic>>[];
      for (final model in models) {
        final file = await storage.resolveRelativeModelPath(model.filePath);
        if ((await sha256.bind(file.openRead()).first).toString() !=
            model.sha256) {
          throw StateError('Model SHA-256 changed: ${model.displayName}');
        }
        configs.add({
          'id': model.id,
          'path': file.path,
          'contract': model.metadata['contract'],
          'confidence': 0.45,
          'iou': 0.45
        });
      }
      final info = await NativeModelRuntime.channel
          .invokeMapMethod<String, dynamic>('beginVideo', {
        'videoPath': videoPath,
        'models': configs,
        'accelerator': accelerator
      });
      final duration = (info!['duration_ms'] as num).toInt();
      if (duration <= 0) throw StateError('Video has no readable duration');
      planned = min(maxFrames, (duration / intervalMs).ceil());
      // A warmup on the same first bitmap is excluded from reported samples.
      await NativeModelRuntime.channel
          .invokeMethod<Object?>('videoFrame', {'timestampMs': 0});
      for (var index = 0; index < planned && !_cancelled; index++) {
        final stamp = index * intervalMs;
        final result = await NativeModelRuntime.channel
            .invokeListMethod<dynamic>('videoFrame', {'timestampMs': stamp});
        for (final raw in result!) {
          final r = Map<String, dynamic>.from(raw as Map);
          final model = models.firstWhere((m) => m.id == r['model_id']);
          rows.add({
            'model_id': model.id,
            'model_sha256': model.sha256,
            'video_sha256': videoSha256,
            'timestamp_ms': stamp,
            'accelerator': accelerator,
            'inference_ms': r['inference_ms'],
            'pipeline_ms': r['total_ms'],
            'memory_mb': r['memory_mb'],
            'detections': (r['detections'] as List).length
          });
        }
        completed++;
        notifyListeners();
      }
      message = _cancelled
          ? 'توقفت المقارنة؛ النتائج الجزئية متاحة.'
          : 'اكتملت المقارنة على الإطارات نفسها. لا توجد Ground Truth لحساب الدقة.';
    } catch (e) {
      message = 'تعذر الاختبار: $e';
      rethrow;
    } finally {
      try {
        await NativeModelRuntime.channel.invokeMethod<void>('endVideo');
      } finally {
        running = false;
        notifyListeners();
      }
    }
  }

  Map<String, double> summary(String modelId) {
    final selected = rows.where((r) => r['model_id'] == modelId).toList();
    if (selected.isEmpty) return {};
    final times = selected
        .map((r) => (r['inference_ms'] as num).toDouble())
        .toList()
      ..sort();
    final n = times.length;
    return {
      'frames': n.toDouble(),
      'p50': n.isOdd ? times[n ~/ 2] : (times[n ~/ 2 - 1] + times[n ~/ 2]) / 2,
      'p95': times[((n - 1) * .95).round()],
      'pipeline_fps': n *
          1000 /
          selected.fold<double>(0, (sum, r) => sum + (r['pipeline_ms'] as num)),
      'peak_memory_mb':
          selected.map((r) => (r['memory_mb'] as num).toDouble()).reduce(max)
    };
  }

  String get csv {
    const fields = [
      'model_id',
      'model_sha256',
      'video_sha256',
      'timestamp_ms',
      'accelerator',
      'inference_ms',
      'pipeline_ms',
      'memory_mb',
      'detections'
    ];
    String esc(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    return '${fields.join(',')}\r\n${rows.map((r) => fields.map((f) => esc(r[f])).join(',')).join('\r\n')}\r\n';
  }

  Uint8List get csvBytes => Uint8List.fromList(utf8.encode('\uFEFF$csv'));
}
