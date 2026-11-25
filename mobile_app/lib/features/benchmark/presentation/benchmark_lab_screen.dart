import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../../models/data/native_model_runtime.dart';
import '../../../shared/widgets/section_card.dart';

class BenchmarkLabScreen extends StatefulWidget {
  final AppState appState;
  const BenchmarkLabScreen({super.key, required this.appState});
  @override
  State<BenchmarkLabScreen> createState() => _BenchmarkLabScreenState();
}

class _BenchmarkLabScreenState extends State<BenchmarkLabScreen> {
  String? _first;
  String? _second;
  String? _message;
  bool _busy = false;
  bool _enduranceRunning = false;
  bool _waitingForFirstFrame = false;
  String _enduranceAccelerator = 'cpu';
  Stopwatch? _enduranceClock;
  Timer? _enduranceTimer;
  String? _enduranceStatus;

  @override
  void dispose() {
    _enduranceTimer?.cancel();
    super.dispose();
  }

  Future<void> _stopEndurance(String status) async {
    _enduranceTimer?.cancel();
    _enduranceTimer = null;
    _enduranceRunning = false;
    _waitingForFirstFrame = false;
    _enduranceStatus = status;
    await widget.appState.stopCameraPreview();
    if (mounted) setState(() {});
  }

  Future<void> _startEndurance() async {
    final app = widget.appState;
    setState(() {
      _enduranceStatus = null;
      _waitingForFirstFrame = true;
      _enduranceRunning = true;
    });
    await app.stopCameraPreview();
    await app.inferenceEngine.setAccelerator(_enduranceAccelerator);
    app.benchmarkService.reset();
    await app.startCameraPreview();
    _enduranceTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final health = await NativeModelRuntime.channel
          .invokeMapMethod<String, dynamic>('getDeviceHealth');
      final thermal = (health?['thermal_status'] as num?)?.toInt() ?? 0;
      final summary = app.benchmarkSummary;
      if (_waitingForFirstFrame && summary.totalFramesEvaluated > 0) {
        _waitingForFirstFrame = false;
        _enduranceClock = Stopwatch()..start();
      }
      final elapsed = _enduranceClock?.elapsed.inSeconds ?? 0;
      if (thermal >= 3) {
        await _stopEndurance(
            'أوقف حراريًا: Thermal Status=$thermal بعد $elapsed ث');
      } else if (!_waitingForFirstFrame && elapsed >= 600) {
        await _stopEndurance('اكتمل 600 ثانية بعد أول استدلال ناجح.');
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _action(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _video() async {
    final app = widget.appState;
    final ids = {_first ?? app.activeModel?.id, _second}..remove(null);
    final models =
        app.models.where((m) => ids.contains(m.id) && m.isValid).toList();
    if (models.isEmpty) throw StateError('اختر نموذجًا ناجح الفحص أولًا.');
    await app.stopCameraPreview();
    final picked = await FilePicker.platform.pickFiles(type: FileType.video);
    if (picked == null) return;
    final path = picked.files.single.path;
    if (path == null) throw StateError('تعذر قراءة الفيديو.');
    try {
      await app.videoBenchmark.run(
          videoPath: path,
          models: models,
          storage: app.storage,
          accelerator: app.inferenceEngine.activeAccelerator);
    } finally {
      await FilePicker.platform.clearTemporaryFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    final summary = app.benchmarkSummary;
    final video = app.videoBenchmark;
    final busy = _busy || video.running;
    final total = summary.totalFramesEvaluated + summary.droppedFrames;
    final eligible = app.models.where((m) => m.isValid).toList();
    Widget modelChoice(
        String label, String? selected, ValueChanged<String?> changed,
        {bool optional = false}) {
      final value = eligible.any((m) => m.id == selected) ? selected : null;
      return DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (optional)
              const DropdownMenuItem<String>(
                  value: null, child: Text('دون نموذج ثانٍ')),
            ...eligible.map((m) => DropdownMenuItem(
                value: m.id,
                child: Text(m.displayName, overflow: TextOverflow.ellipsis)))
          ],
          onChanged: busy ? null : changed);
    }

    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionCard(
              title: 'مختبر النماذج — Model Benchmark Lab',
              subtitle:
                  'FPS للإطارات المكتملة عبر الزمن، وp50/p95 لاستدعاء المحرك فقط.',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        'النموذج النشط: ${app.activeModel?.displayName ?? "غير مفعّل"}'),
                    Text(
                        'Inference FPS: ${summary.averageInferenceFps.toStringAsFixed(2)} · CPU/GPU: ${summary.accelerator}'),
                    Text(
                        'p50: ${summary.medianLatencyMs.toStringAsFixed(1)} ms · p95: ${summary.p95LatencyMs.toStringAsFixed(1)} ms'),
                    Text(
                        'إطارات مكتملة: ${summary.totalFramesEvaluated} · إسقاط: ${summary.droppedFrames} (${total == 0 ? "0" : (summary.droppedFrames / total * 100).toStringAsFixed(1)}%)'),
                    Text(
                        'ذاكرة العملية PSS: ${app.memoryMb.toStringAsFixed(1)} MB · نافذة الزمن: آخر 500 إطار'),
                    const SizedBox(height: 12),
                    modelChoice('النموذج الأول (افتراضيًا النشط)', _first,
                        (v) => setState(() => _first = v)),
                    const SizedBox(height: 10),
                    modelChoice('النموذج الثاني للمقارنة', _second,
                        (v) => setState(() => _second = v),
                        optional: true),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ElevatedButton(
                          onPressed: busy
                              ? null
                              : () => _action(() async {
                                    if (_first != null) {
                                      final result = await app
                                          .activateExistingModel(_first!);
                                      if (!result.success) {
                                        throw StateError(
                                            result.error ?? 'فشل التفعيل');
                                      }
                                    }
                                    await app.startCameraPreview();
                                  }),
                          child: const Text('تشغيل الكاميرا بالنموذج')),
                      OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => _action(app.stopCameraPreview),
                          child: const Text('إيقاف الكاميرا')),
                      for (final accelerator in ['cpu', 'gpu'])
                        OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => _action(() async {
                                      await app.stopCameraPreview();
                                      await app.inferenceEngine
                                          .setAccelerator(accelerator);
                                      app.benchmarkService.reset();
                                      if (mounted) {
                                        setState(() => _message =
                                            'نجح اختبار ${accelerator.toUpperCase()} على الجهاز.');
                                      }
                                    }),
                            child: Text('اختبار ${accelerator.toUpperCase()}')),
                      OutlinedButton(
                          onPressed: busy
                              ? null
                              : () =>
                                  setState(() => app.benchmarkService.reset()),
                          child: const Text('تصفير القياس')),
                      OutlinedButton(
                          onPressed: busy || summary.totalFramesEvaluated == 0
                              ? null
                              : () => _action(() async {
                                    await app.benchmarkService
                                        .saveCurrentSampleToDb();
                                    final csv =
                                        'model_sha256,accelerator,completed,dropped,fps,p50_ms,p95_ms,memory_mb\r\n'
                                        '${app.activeModel?.sha256 ?? ""},${summary.accelerator},${summary.totalFramesEvaluated},${summary.droppedFrames},${summary.averageInferenceFps},${summary.medianLatencyMs},${summary.p95LatencyMs},${app.memoryMb}\r\n';
                                    await FilePicker.platform.saveFile(
                                        fileName: 'safezone_live.csv',
                                        bytes: Uint8List.fromList(
                                            utf8.encode(csv)));
                                  }),
                          child: const Text('حفظ وتصدير قياس الكاميرا CSV')),
                    ]),
                    const SizedBox(height: 16),
                    const Divider(),
                    Text('تحمل Profile (حتى 600 ثانية)',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(_enduranceRunning
                        ? (_waitingForFirstFrame
                            ? 'بانتظار أول استدلال ناجح…'
                            : 'المدة: ${_enduranceClock?.elapsed.inSeconds ?? 0}/600 ث')
                        : 'يبدأ العداد بعد أول استدلال ناجح. الإيقاف الحراري عند Status 3 أو أعلى.'),
                    DropdownButtonFormField<String>(
                      initialValue: _enduranceAccelerator,
                      decoration: const InputDecoration(labelText: 'المسرّع'),
                      items: const [
                        DropdownMenuItem(value: 'cpu', child: Text('CPU')),
                        DropdownMenuItem(value: 'gpu', child: Text('GPU')),
                      ],
                      onChanged: _enduranceRunning || busy
                          ? null
                          : (value) =>
                              setState(() => _enduranceAccelerator = value!),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      ElevatedButton(
                        onPressed: busy || _enduranceRunning
                            ? null
                            : () => _action(_startEndurance),
                        child: const Text('بدء تحمل 600 ث'),
                      ),
                      OutlinedButton(
                        onPressed: !_enduranceRunning
                            ? null
                            : () => _stopEndurance(
                                'أوقفه المستخدم مع حفظ القياسات الجزئية.'),
                        child: const Text('إيقاف التحمل'),
                      ),
                    ]),
                    if (_enduranceStatus != null) Text(_enduranceStatus!),
                  ])),
          SectionCard(
              title: 'مقارنة على فيديو محلي',
              subtitle:
                  'حتى 120 إطارًا بفاصل ثانية، وفك إطار واحد لكلا النموذجين. الإحماء مستبعد. لا تُحفظ إطارات.',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                        onPressed: busy ? null : () => _action(_video),
                        child: const Text('اختيار فيديو وتشغيل المقارنة')),
                    if (video.running) ...[
                      LinearProgressIndicator(
                          value: video.planned == 0
                              ? null
                              : video.completed / video.planned),
                      Text('${video.completed} / ${video.planned}'),
                      TextButton(
                          onPressed: video.cancel,
                          child: const Text(
                              'إيقاف المقارنة مع حفظ النتائج الجزئية')),
                    ],
                    if (video.message != null) Text(video.message!),
                    for (final model in app.models.where(
                        (m) => video.rows.any((r) => r['model_id'] == m.id)))
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                              '${model.displayName}\n${video.summary(model.id).entries.map((e) => "${e.key}: ${e.value.toStringAsFixed(2)}").join(" · ")}')),
                    OutlinedButton(
                        onPressed: busy || video.rows.isEmpty
                            ? null
                            : () => _action(() async {
                                  await FilePicker.platform.saveFile(
                                      fileName: 'safezone_comparison.csv',
                                      bytes: video.csvBytes);
                                }),
                        child: const Text('تصدير المقارنة CSV')),
                  ])),
          if (_message != null) Text(_message!),
          if (app.lastBannerMessage != null) Text(app.lastBannerMessage!),
        ]));
  }
}
