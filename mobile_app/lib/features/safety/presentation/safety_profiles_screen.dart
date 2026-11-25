import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../models/domain/model_entry.dart';

/// SCREEN 04: قواعد السلامة / Profiles
class SafetyProfilesScreen extends StatefulWidget {
  final AppState appState;

  const SafetyProfilesScreen({super.key, required this.appState});

  @override
  State<SafetyProfilesScreen> createState() => _SafetyProfilesScreenState();
}

class _SafetyProfilesScreenState extends State<SafetyProfilesScreen> {
  double _confidenceThreshold = 0.45;
  double _iouThreshold = 0.45;
  int _minEvidenceFrames = 3;
  int _maxGapMs = 600;
  Map<String, String> _mapping = {};

  @override
  void initState() {
    super.initState();
    final p = widget.appState.activeProfile;
    if (p != null) {
      _confidenceThreshold = p.confidenceThreshold;
      _iouThreshold = p.iouThreshold;
      _minEvidenceFrames = p.minEvidenceFrames;
      _maxGapMs = p.maxGapMs;
      _mapping = Map.from(p.classMapping);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.appState.activeProfile;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'SCREEN 04 · قواعد السلامة وربط الفئات (Model Profiles)',
            subtitle:
                'فصل أسماء فئات النموذج عن منطق الكاميرا بحيث يمكن تخصيص القواعد لكل نموذج مستقل',
            child: profile == null
                ? const Text(
                    'يرجى تفعيل نموذج أولاً لتعديل ملف قواعد السلامة المرتبط به.',
                    style: TextStyle(color: Color(0xFF96ADC7)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الملف التعريفي النشط: ${profile.profileName}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      ...profile.classMapping.entries.map(
                        (e) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('الفئة: ${e.key}'),
                          trailing: DropdownButton<String>(
                            value: _mapping[e.key] ?? 'review',
                            items: const [
                              DropdownMenuItem(value: 'compliant', child: Text('ملتزم')),
                              DropdownMenuItem(value: 'violation', child: Text('مخالف')),
                              DropdownMenuItem(value: 'review', child: Text('مراجعة')),
                            ],
                            onChanged: (value) => setState(() => _mapping[e.key] = value!),
                          ),
                        ),
                      ),
                      const Divider(height: 24),
                      Text(
                        'عتبة الثقة الدنيا (Confidence Threshold): ${(_confidenceThreshold * 100).toStringAsFixed(0)}%',
                      ),
                      Slider(
                        value: _confidenceThreshold,
                        min: 0.15,
                        max: 0.95,
                        divisions: 16,
                        onChanged: (v) =>
                            setState(() => _confidenceThreshold = v),
                      ),
                      Text(
                        'الحد الأدنى لإطارات الدليل في وضع البوابة (Min Evidence Frames): $_minEvidenceFrames',
                      ),
                      Text('عتبة تداخل NMS: ${_iouThreshold.toStringAsFixed(2)}'),
                      Slider(value: _iouThreshold, min: .1, max: .9, divisions: 16,
                        onChanged: (value) => setState(() => _iouThreshold = value)),
                      Slider(
                        value: _minEvidenceFrames.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        onChanged: (v) =>
                            setState(() => _minEvidenceFrames = v.round()),
                      ),
                      Text(
                        'أقصى فجوة زمنية بين قراءات المرور الواحد (Max Gap): $_maxGapMs ms',
                      ),
                      Slider(
                        value: _maxGapMs.toDouble(),
                        min: 200,
                        max: 2000,
                        divisions: 18,
                        onChanged: (v) => setState(() => _maxGapMs = v.round()),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          final updated = ModelProfile(
                            id: profile.id,
                            modelId: profile.modelId,
                            profileName: profile.profileName,
                            classMapping: Map.from(_mapping),
                            confidenceThreshold: _confidenceThreshold,
                            iouThreshold: _iouThreshold,
                            minEvidenceFrames: _minEvidenceFrames,
                            maxGapMs: _maxGapMs,
                            createdAt: profile.createdAt,
                          );
                          widget.appState.updateActiveProfile(updated);
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('حفظ قواعد السلامة'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
