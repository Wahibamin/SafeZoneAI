import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../../app/app_state.dart';
import '../../../shared/widgets/metric_tile.dart';
import '../../../shared/widgets/section_card.dart';

/// SCREEN 07: الإحصائيات / Dashboard
class StatisticsDashboardScreen extends StatefulWidget {
  final AppState appState;

  const StatisticsDashboardScreen({super.key, required this.appState});

  @override
  State<StatisticsDashboardScreen> createState() =>
      _StatisticsDashboardScreenState();
}

class _StatisticsDashboardScreenState extends State<StatisticsDashboardScreen> {
  String? _exportedCsvPreview;

  @override
  Widget build(BuildContext context) {
    final counters = widget.appState.liveCounters;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'SCREEN 07 · لوحة الإحصائيات الحية (In-Memory Live Session)',
            subtitle:
                'الجلسة الحالية: ${counters.liveSessionId} · بدأت: ${counters.startedAtUtc}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 160,
                  children: [
                    MetricTile(
                      label: 'ملتزم (COMPLIANT)',
                      value: '${counters.compliantCount}',
                      sublabel:
                          'نسبة الالتزام: ${counters.complianceRatePercent.toStringAsFixed(1)}%',
                      accentColor: const Color(0xFFB8F66A),
                    ),
                    MetricTile(
                      label: 'مخالف (VIOLATION)',
                      value: '${counters.violationCount}',
                      sublabel: 'حالات مخالفة مؤكدة',
                      accentColor: const Color(0xFFFF8699),
                    ),
                    MetricTile(
                      label: 'مراجعة (REVIEW)',
                      value: '${counters.reviewCount}',
                      sublabel: 'حالات غير حاسمة معروضة بوضوح',
                      accentColor: const Color(0xFFF5CA74),
                    ),
                    MetricTile(
                      label: 'مرات المرور / الإطارات',
                      value:
                          '${counters.gatePassagesCount} / ${counters.evaluatedFramesCount}',
                      sublabel: 'مرور بوابة مقابل إطارات حية',
                      accentColor: const Color(0xFF63D7DD),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () =>
                          widget.appState.startNewLiveSessionOnly(),
                      icon: const Icon(Icons.fiber_new_rounded),
                      label: const Text(
                          'بدء جلسة حية جديدة (دون مسح التاريخ المحفوظ)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final csv =
                            await widget.appState.exportPersistedEventsCsv();
                        if (!mounted) return;
                        setState(() => _exportedCsvPreview = csv);
                        try {
                          await FilePicker.platform.saveFile(
                              fileName: 'safezone_events.csv',
                              bytes: Uint8List.fromList(
                                  utf8.encode('\uFEFF$csv')));
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('تعذر حفظ CSV: $e')));
                          }
                        }
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('تصدير CSV للأحداث المحفوظة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_exportedCsvPreview != null)
            SectionCard(
              title: 'معاينة ملف CSV المصدّر (بيانات غير شخصية فقط)',
              child: SelectableText(
                _exportedCsvPreview!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: Color(0xFFBBE1DE),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
