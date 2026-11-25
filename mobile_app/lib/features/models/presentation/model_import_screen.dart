import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../../../shared/widgets/section_card.dart';

class ModelImportScreen extends StatefulWidget {
  final AppState appState;
  const ModelImportScreen({super.key, required this.appState});
  @override
  State<ModelImportScreen> createState() => _ModelImportScreenState();
}

class _ModelImportScreenState extends State<ModelImportScreen> {
  final _name = TextEditingController();
  final _manifest = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _name.dispose();
    _manifest.dispose();
    super.dispose();
  }

  Future<void> _pick({bool manifest = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final selection = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true, allowMultiple: false);
      if (selection == null) return;
      final file = selection.files.single;
      if (!file.name.toLowerCase().endsWith(manifest ? '.json' : '.tflite')) {
        throw FormatException(
            manifest ? 'اختر ملف model.json.' : 'اختر ملفًا بامتداد .tflite.');
      }
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const FormatException('تعذر قراءة الملف المختار.');
      }
      if (!mounted) return;
      if (manifest) {
        _manifest.text = utf8.decode(bytes);
        setState(() => _message = 'تم اختيار ملف البيانات المرافق.');
      } else {
        final entry = await widget.appState.importModel(
            fileName: file.name,
            fileBytes: bytes,
            displayName: _name.text,
            manifestJson:
                _manifest.text.trim().isEmpty ? null : _manifest.text);
        if (mounted) {
          setState(() => _message =
              'تم استيراد ${entry.displayName} وفحص التنسورات. ينتظر اختبار الاستدلال؛ فعّله من مكتبة النماذج.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'تعذر الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SectionCard(
          title: 'استيراد نموذج',
          subtitle: 'اختيار ملف من الهاتف ونسخه إلى مساحة التطبيق الخاصة.',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                controller: _name,
                enabled: !_busy,
                decoration:
                    const InputDecoration(labelText: 'اسم النموذج (اختياري)')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(manifest: true),
                icon: const Icon(Icons.description_outlined),
                label: const Text('اختيار model.json (اختياري)')),
            TextField(
                controller: _manifest,
                enabled: !_busy,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'بيانات النموذج المرافقة (اختياري)')),
            const SizedBox(height: 12),
            ElevatedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('اختيار واستيراد .tflite')),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!)),
          ])));
}
