import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/status_badge.dart';

/// SCREEN 06: Gate Mode
class GateModeScreen extends StatelessWidget {
  final AppState appState;

  const GateModeScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final episodes = appState.gateEpisodes;
    final roi = appState.gateAnalyzer.doorwayRoi;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'SCREEN 06 · وضع البوابة (Gate Mode Evidence Aggregator)',
            subtitle:
                'حدث واحد لكل مرور مرصود داخل نطاق الباب (ROI) بدلاً من تسجيل كل إطار كحدث منفصل',
            trailing: Switch(
              value: appState.gateModeEnabled,
              onChanged: (v) => appState.setGateModeEnabled(v),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'نطاق البوابة النشط (ROI): Left ${(roi.left * 100).toInt()}% → Right ${(roi.right * 100).toInt()}% | Top ${(roi.top * 100).toInt()}% → Bottom ${(roi.bottom * 100).toInt()}%',
                  style:
                      const TextStyle(fontSize: 12.5, color: Color(0xFF96ADC7)),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF183043),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF31556A)),
                  ),
                  child: const Text(
                    'تنبيه هندسي: يمثل كل حدث فترة ظهور وجه متصلة (Face Visibility Episode) داخل نطاق البوابة، ولا يدعي التطبيق التعرف على الهوية الشخصية.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB7DCE9)),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => appState.startCameraPreview(),
                  icon: const Icon(Icons.play_lesson_rounded),
                  label: const Text(
                    'تشغيل الكاميرا للبوابة',
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'سجل مرات المرور المرصودة في الجلسة (${episodes.length})',
            child: episodes.isEmpty
                ? const Text(
                    'فعّل وضع البوابة وشغّل الكاميرا من الرئيسية. لا تُعد الإطارات كأشخاص.',
                    style: TextStyle(color: Color(0xFF96ADC7)),
                  )
                : Column(
                    children: episodes.reversed.map((ep) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF162337),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF283A50)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${ep.episodeId} · الفئة: ${ep.dominantLabel}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ep.explanationAr,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF96ADC7),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'الأدلة: ${ep.evidenceFrames} إطارات · المدة: ${ep.durationMs} ms · الثقة: ${(ep.aggregatedConfidence * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF80A6AC),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(status: ep.finalStatus),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
