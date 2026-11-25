# دليل التشغيل والبناء والنشر المباشر — SafeZone AI Mobile

هذا الدليل مخصص لتشغيل مشروع `SafeZone_Mobile` مباشرةً على نظام Windows (داخل Google Antigravity أو VS Code) وتثبيته على هاتف **Samsung Galaxy Z Flip3**.

---

## 1. فك الضغط ومكان وضع المشروع

1. فك ضغط الملف `SafeZone_AI_Mobile_Complete_Project.zip`.
2. انقل مجلد `SafeZone_Mobile` إلى المسار المعتمد لديك (أو أي مسار تختاره):
   ```text
   mobile_app/
   ```
   *(ملاحظة: المشروع مستقل تماماً ولا يلمس مجلد `../src/` الخاص بنسخة Windows).*

---

## 2. تشغيل المشروع والتحقق من الاختبارات

افتح الطرفية (Terminal) داخل مجلد `SafeZone_Mobile` ونفّذ الأوامر التالية بالترتيب:

```powershell
# 1. جلب الحزم والتبعيات
flutter pub get

# 2. التحليل الثابت للكود والتأكد من خلوه من الأخطاء
flutter analyze

# 3. تشغيل حزمة الاختبارات المؤتمتة للمراحل (T01 إلى T20)
flutter test
```

---

## 3. التشغيل المباشر على هاتف Samsung Galaxy Z Flip3

1. فعّل **خيارات المطور (Developer Options)** و**تصحيح أخطاء USB (USB Debugging)** على هاتف Galaxy Z Flip3.
2. وصّل الهاتف بالحاسوب عبر كابل USB وتحقق من ظهوره:
   ```powershell
   flutter devices
   ```
3. لتشغيل التطبيق مباشرةً في وضع التطوير:
   ```powershell
   flutter run
   ```
4. لبناء ملف `APK` النهائي الجاهز للتثبيت المستقل (المرحلة P07):
   ```powershell
   flutter build apk --release
   ```
   سيتم إنتاج ملف الـ APK في المسار:
   `build/app/outputs/flutter-apk/app-release.apk`

---

## 4. تصدير نموذج الكمامات `best_mask_v4.pt` واستيراده إلى الهاتف (المرحلة P03)

1. افتح Google Colab وارفع ملف النموذج المدرّب `best_mask_v4.pt` مع السكربت المرفق في المشروع:
   `tools/colab_export_yolo11n_to_tflite.py`
2. شغّل دالة التصدير في Colab:
   ```python
   from colab_export_yolo11n_to_tflite import export_yolo11n_for_safezone
   export_yolo11n_for_safezone("best_mask_v4.pt", imgsz=640)
   ```
3. سينتج ملفان:
   - `best_mask_v4_saved_model/best_mask_v4_float32.tflite` (أو `mask_v4.tflite`)
   - ملف العقد المرافق `.model.json` المحتوي على بصمة `SHA-256` والفئات الثلاث.
4. انقل ملف `.tflite` إلى ذاكرة هاتف Galaxy Z Flip3، وافتح تطبيق **SafeZone AI Mobile** ← تبويب **استيراد (SCREEN 03)** ← اختر الملف ليتم فحصه وتفعيله فوراً دون الحاجة لإعادة بناء الـ APK.

