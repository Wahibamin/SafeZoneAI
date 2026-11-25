import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/section_card.dart';

/// SCREEN 08: الإعدادات والخصوصية
class SettingsPrivacyScreen extends StatelessWidget {
  final AppState appState;

  const SettingsPrivacyScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title:
                'SCREEN 08 · الخصوصية الصارمة وإدارة السجلات (Privacy & Retention)',
            subtitle:
                'لا تسجّل الكاميرا صورًا أو فيديو ولا تُنشأ بصمات وجه. عدد الوسائط في مخزن التطبيق الدائم: ${appState.forbiddenMediaCount}.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'حفظ سجل الأحداث النصية غير الشخصية (Opt-in Event History)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'معطّل افتراضياً (OFF). عند التفعيل يتم حفظ وقت الحدث وحالة السلامة فقط في SQLite دون أي صور.',
                  ),
                  value: appState.eventLoggingEnabled,
                  onChanged: (v) => appState.toggleEventLogging(v),
                ),
                const Text(
                    'عند اختيار فيديو للمقارنة يُنسخ مؤقتًا للقراءة، ثم يُحذف من ذاكرة التطبيق المؤقتة بعد انتهاء المقارنة أو إلغائها. يبقى الملف الأصلي في هاتفك.'),
                const Divider(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                                title: const Text('حذف السجل المحفوظ؟'),
                                content: const Text(
                                    'ستُحذف الأحداث والجلسات وقياسات الأداء المحفوظة نهائيًا. يمكنك تصدير CSV أولًا.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('إلغاء')),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('حذف السجل')),
                                ]));
                    if (confirmed == true) {
                      await appState.purgePersistedHistory();
                    }
                  },
                  icon: const Icon(
                    Icons.delete_forever_rounded,
                    color: Color(0xFFFF8699),
                  ),
                  label: const Text(
                    'مسح جميع الجلسات والأحداث التاريخية من قاعدة البيانات',
                  ),
                ),
              ],
            ),
          ),
          const SectionCard(
            title: 'معلومات الإصدار والتراخيص (Release & Licensing)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '• التطبيق: ${AppConstants.appName} (${AppConstants.appId})'),
                SizedBox(height: 6),
                Text(
                    '• الإصدار: ${AppConstants.appVersion} · قاعدة البيانات: ${AppConstants.dbFileName} (v${AppConstants.dbVersion})'),
                SizedBox(height: 6),
                Text(
                    '• الجهاز المرجعي: ${AppConstants.targetDevice}. وسم Flex يدوي؛ اختبار الطي الميكانيكي مستقل.'),
                SizedBox(height: 6),
                Text(
                    '• تنبيه التراخيص: نماذج Ultralytics YOLO تخضع لرخصة AGPL-3.0 ما لم يتم الحصول على ترخيص Enterprise للتوزيع التجاري المغلق.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
