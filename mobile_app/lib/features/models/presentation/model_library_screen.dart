import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../domain/model_entry.dart';

class ModelLibraryScreen extends StatefulWidget {
  final AppState appState;
  const ModelLibraryScreen({super.key, required this.appState});
  @override
  State<ModelLibraryScreen> createState() => _ModelLibraryScreenState();
}

class _ModelLibraryScreenState extends State<ModelLibraryScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _run(Future<String> Function() operation) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await operation();
      if (mounted) setState(() => _message = message);
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _details(ModelEntry model) async {
    final checks =
        await widget.appState.modelRepository.listChecksForModel(model.id);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(model.displayName),
                content: SizedBox(
                    width: 500,
                    child: SingleChildScrollView(
                        child: SelectableText(
                            const JsonEncoder.withIndent('  ').convert({
                      'بصمة SHA-256': model.sha256,
                      'تاريخ الاستيراد': model.importedAt,
                      'البيانات الفعلية': model.metadata,
                      'الفئات': model.labels,
                      'اختبارات الاستدلال':
                          checks.map((c) => c.toMap()).toList(),
                    })))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق'))
                ]));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('مكتبة النماذج',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const Text(
          'استورد نموذجًا من شاشة استيراد. التفعيل يتطلب استدلالًا حقيقيًا ناجحًا على الجهاز.'),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_message!)),
      if (app.models.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24), child: Text('لا توجد نماذج مستوردة.')),
      ...app.models.map((model) {
        final active = app.activeModel?.id == model.id;
        final states = {
          'pending': 'ينتظر فحص الاستدلال',
          'valid': 'اجتاز الاستدلال',
          'invalid': 'فشل التحقق'
        };
        final size = model.metadata['size_bytes'] as num?;
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${model.displayName}${active ? ' · نشط الآن ✓' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(states[model.validationState] ??
                          model.validationState),
                      Text(
                          'الحجم: ${size == null ? 'غير موثق' : '${(size / 1048576).toStringAsFixed(2)} MB'}'),
                      Text(
                          'الاستيراد: ${DateTime.tryParse(model.importedAt)?.toLocal() ?? model.importedAt}'),
                      Text(
                          'الدخل: ${model.inputWidth}×${model.inputHeight} · ${model.inputLayout} · ${model.tensorDtype}'),
                      Text('الفئات: ${model.labels.values.join('، ')}'),
                      if (model.errorMessage != null)
                        Text('سبب الفشل: ${model.errorMessage}'),
                      Wrap(spacing: 8, children: [
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      await _details(model);
                                      return '';
                                    }),
                            child: const Text('التفاصيل')),
                        OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      final check =
                                          await app.validateModel(model.id);
                                      return check.passed
                                          ? 'نجح فحص الاستدلال دون تغيير التفعيل.'
                                          : 'فشل الفحص: ${check.detail}';
                                    }),
                            child: const Text('فحص')),
                        ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      final result = await app
                                          .activateExistingModel(model.id);
                                      return result.success
                                          ? 'تم التفعيل بعد استدلال فعلي (${result.warmupInferenceMs?.toStringAsFixed(1)} ms).'
                                          : '${result.rolledBack ? 'فشل التفعيل واستعيد النموذج السابق.' : 'فشل التفعيل.'} ${result.error}';
                                    }),
                            child: Text(
                                active ? 'إعادة التحقق والتفعيل' : 'تفعيل')),
                        TextButton(
                            onPressed: _busy || active
                                ? null
                                : () => _run(() async {
                                      await app.deleteModel(model.id);
                                      return 'تم حذف النموذج.';
                                    }),
                            child: const Text('حذف')),
                      ]),
                    ])));
      }),
    ]);
  }
}
