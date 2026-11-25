# ADR-001: Flutter للواجهة واستخدام Native عند الضرورة فقط

## الحالة
معتمد (Accepted) — 2026-11-18

## القرار والتفسير
اعتماد Flutter/Dart لبناء واجهات المستخدم العربية RTL، وإدارة الحالة، وقاعدة البيانات SQLite، ومنطق تجميع الأدلة (SafetyPolicy & GateModeProcessor)، مع حصر الكود الأصلي (Kotlin / Platform Channel) في فحص ترويسة ملفات TFLite واستعلام خصائص الجهاز القابل للطي (Samsung Galaxy Z Flip3).
