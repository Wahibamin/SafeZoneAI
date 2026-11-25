# كتالوج واجهات المستخدم وجداول قاعدة البيانات — SafeZone AI Mobile

يُوثّق هذا الدليل جميع شاشات التطبيق الثماني (العربية RTL) وجميع جداول قاعدة البيانات السبعة في `safezone_mobile.db`.

---

## أولاً: كتالوج واجهات المستخدم (8 شاشات عربية RTL)

| رقم الشاشة | اسم الشاشة | المسار البرمجي (`lib/...`) | الوظيفة الأساسية والمكونات | المرحلة المرتبطة |
|---|---|---|---|---|
| **SCREEN 01** | **الرئيسية / المراقبة الحية (Live Monitor)** | `features/camera/presentation/live_monitor_screen.dart` | معاينة الكاميرا الحية، رسم صناديق الكشف (`DetectionBboxOverlay`)، شارة حالة السلامة الفورية (`COMPLIANT` / `VIOLATION` / `REVIEW`)، التبديل بين الكاميرا الأمامية والخلفية، دعم طيّ شاشة `Galaxy Z Flip3` (`Flex Mode 90°` / `Flat 180°`)، ومحاكاة الفئات الثلاث وحالات عدم اليقين. | P01, P03 |
| **SCREEN 02** | **مكتبة النماذج (Model Library)** | `features/models/presentation/model_library_screen.dart` | عرض كافة النماذج المستوردة في المساحة الخاصة بالتطبيق، عرض البصمة الرقمية `SHA-256` وأبعاد الدخل والفئات وحالة الفحص (`valid` / `invalid` / `pending`)، تفعيل أي نموذج فوريًا دون إعادة بناء APK، وحذف النماذج غير النشطة. | P02 |
| **SCREEN 03** | **استيراد نموذج (Model Import)** | `features/models/presentation/model_import_screen.dart` | استيراد ملف `.tflite` عبر منتقي ملفات النظام (`Android SAF`) مع ملف `model.json` الاختياري، فحص ترويسة `TFL3`، حساب `SHA-256`، تشغيل `Smoke Inference`، والتراجع التلقائي (`Rollback`) للنموذج السابق عند الفشل. | P02 |
| **SCREEN 04** | **قواعد السلامة (Safety Profiles)** | `features/safety/presentation/safety_profiles_screen.dart` | ربط فئات النموذج (`with_mask`, `without_mask`, `mask_weared_incorrect`) بأحكام السلامة (`compliant`, `violation`, `review`)، وضبط عتبة الثقة (`Confidence Threshold`) وعتبة التداخل (`IoU`) وأقل عدد إطارات دليل (`Min Evidence Frames`). | P02, P03 |
| **SCREEN 05** | **مختبر الأداء (Benchmark Lab)** | `features/benchmark/presentation/benchmark_lab_screen.dart` | عرض سرعة الاستدلال الحقيقية (`Inference FPS`)، الوسيط الحسابي לזمن الاستدلال (`Median p50 ms`)، الزمن المئيني (`p95 Latency ms`)، عدد الإطارات المتروكة بآلية منع التراكم (`Backpressure Drops`)، والتبديل بين `CPU` و`GPU Delegate`. | P04 |
| **SCREEN 06** | **وضع البوابة (Gate Mode)** | `features/gate/presentation/gate_mode_screen.dart` | تفعيل وضع مراقبة البوابة (`ROI`)، تجميع الأدلة الزمنية لتسجيل حدث واحد لكل مرور مرصود بدلاً من كل إطار، عرض سجل مرات المرور، وتشغيل السيناريو المرجعي (3 مرات مرور متتابعة: مخالفتان والتزام). | P05 |
| **SCREEN 07** | **لوحة الإحصائيات (Statistics Dashboard)** | `features/statistics/presentation/statistics_dashboard_screen.dart` | عرض عدادات الجلسة الحية في الذاكرة (`COMPLIANT`, `VIOLATION`, `REVIEW`, نسبة الالتزام، ومرات مرور البوابة)، زر بدء جلسة حية جديدة دون مسح التاريخ المحفوظ، وتصدير الأحداث إلى ملف `CSV` غير شخصي. | P06 |
| **SCREEN 08** | **الإعدادات والخصوصية (Settings & Privacy)** | `features/settings/presentation/settings_privacy_screen.dart` | التحكم في تفعيل/تعطيل حفظ سجل الأحداث النصية غير الشخصية (معطّل افتراضياً `OFF`)، عداد فحص الخصوصية المؤكد لعدم حفظ أي صور أو فيديو (`0 ملفات وسائط`)، زر المسح الشامل للتاريخ، ومعلومات الإصدار والتراخيص. | P06, P07 |

---

## ثانياً: كتالوج جداول قاعدة البيانات المحلية (`safezone_mobile.db` — 7 جداول)

تُدار القاعدة عبر `DatabaseHelper` وترقيات مرقمة (`DatabaseMigrations` V1 → V2 → V3) مع تفعيل `PRAGMA foreign_keys = ON`.

| # | اسم الجدول | مرحلة الإنشاء | الوظيفة الأساسية | الحقول الرئيسية والقيود |
|---|---|---|---|---|
| 1 | `models` | **P02 (Migration V1)** | سجل النماذج المستوردة ومساراتها في المساحة الخاصة وبصمتها وحالة التحقق منها. | `id (PK)`, `display_name`, `file_path`, `sha256 (UNIQUE)`, `format CHECK('tflite')`, `task CHECK('detect')`, `family`, `input_width`, `input_height`, `input_layout`, `tensor_dtype`, `labels_json`, `metadata_json`, `validation_state CHECK('pending','valid','invalid')`, `error_message`, `imported_at`, `last_validated_at` |
| 2 | `model_profiles` | **P02 (Migration V1)** | ربط فئات كل نموذج بحالات السلامة وعتبات الثقة وتجميع الأدلة. | `id (PK)`, `model_id (FK → models.id ON DELETE CASCADE)`, `profile_name`, `class_mapping_json`, `confidence_threshold (0..1)`, `iou_threshold (0..1)`, `min_evidence_frames (>0)`, `max_gap_ms (>=0)`, `created_at` |
| 3 | `app_settings` | **P01/P02 (Migration V1)** | مصدر الحقيقة الموحد لإعدادات التطبيق والنموذج النشط وحالة التسجيل (`event_logging_enabled = false`). | `key (PK)`, `value_json`, `updated_at` |
| 4 | `model_checks` | **P02 (Migration V1)** | سجل اختبارات التحقق الفعلي (`Smoke Inference`) للنموذج على الهاتف قبل تفعيله. | `id (PK)`, `model_id (FK → models.id ON DELETE CASCADE)`, `tested_at`, `passed CHECK(0,1)`, `device`, `runtime_name`, `inference_ms`, `detail` |
| 5 | `performance_samples` | **P04 (Migration V2)** | حفظ عينات قياس الأداء غير الحساسة في مختبر الاختبار. | `id (PK)`, `session_id (FK → monitoring_sessions.id)`, `sampled_at`, `fps (>=0)`, `inference_ms (>=0)`, `dropped_frames (>=0)`, `accelerator CHECK('cpu','gpu','other','unknown')` |
| 6 | `monitoring_sessions` | **P06 (Migration V3)** | بيانات جلسات المراقبة (يُنشأ السجل فقط عند تفعيل المستخدم لخيار حفظ السجل التاريخي). | `id (PK)`, `model_id (FK → models.id)`, `profile_id (FK → model_profiles.id)`, `source_type CHECK('front_camera','rear_camera','video_test')`, `started_at`, `ended_at`, `state CHECK('running','closed','interrupted')` |
| 7 | `detection_events` | **P06 (Migration V3)** | سجل الأحداث المجمّعة غير الشخصية (لا يحتوي على أي صور أو إطارات أو بصمات وجه). | `id (PK)`, `session_id (FK → monitoring_sessions.id ON DELETE CASCADE)`, `model_id`, `occurred_at`, `safety_status CHECK('compliant','violation','review')`, `model_label`, `confidence (0..1)`, `evidence_frames`, `duration_ms`, `mode CHECK('live','gate')` |
