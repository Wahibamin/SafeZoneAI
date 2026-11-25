import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../domain/camera_source.dart';
import '../platform/camera_preview_provider.dart';
import 'widgets/detection_bbox_overlay.dart';

/// SCREEN 01: الرئيسية / Live Monitor
/// Layout uses Column+Expanded so ALL controls are always visible without scrolling.
class LiveMonitorScreen extends StatelessWidget {
  final AppState appState;

  const LiveMonitorScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final cam = appState.cameraSource;
    final controller = cam is CameraPreviewProvider
        ? (cam as CameraPreviewProvider).controller
        : null;
    final activeModel = appState.activeModel;
    final decision = appState.latestDecision;

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final hPad = isLandscape ? 10.0 : 14.0;
    final vPad = isLandscape ? 4.0 : 10.0;
    final bannerVPad = isLandscape ? 4.0 : 10.0;
    final btnHeight = isLandscape ? 38.0 : 52.0;
    final btnHeight2 = isLandscape ? 36.0 : 48.0;
    final ctrlPad = isLandscape ? 8.0 : 12.0;
    final betweenGap = isLandscape ? 4.0 : 8.0;
    final bannerGap = isLandscape ? 4.0 : 10.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Status Banner (compact) ──────────────────────────────────
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: bannerVPad),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF172A40), Color(0xFF111F31)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF364E62)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    activeModel != null
                        ? 'النموذج: ${activeModel.displayName}'
                        : 'لا يوجد نموذج مفعّل',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEBF2FC),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(status: decision.status, large: false),
              ],
            ),
          ),
          SizedBox(height: bannerGap),
          if (appState.lastBannerMessage != null)
            Text(appState.lastBannerMessage!,
                style: const TextStyle(color: Color(0xFFFF8699))),

          // ── Camera Preview (Expanded — takes remaining space) ─────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0B1321),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cam.isRunning
                      ? const Color(0xFF63D7DD)
                      : const Color(0xFF283A50),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cam.isRunning &&
                        controller != null &&
                        controller.value.isInitialized) ...[
                      Center(
                          child: AspectRatio(
                              aspectRatio: appState.frameAspectRatio ??
                                  (isLandscape
                                      ? controller.value.aspectRatio
                                      : 1 / controller.value.aspectRatio),
                              child: Stack(fit: StackFit.expand, children: [
                                CameraPreview(controller),
                                DetectionBboxOverlay(
                                    detections: appState.latestDetections,
                                    overallStatus: decision.status,
                                    mirrored: cam.currentLens ==
                                        CameraLensDirectionType.front),
                              ]))),
                      // Live badge — top-right overlay
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF080E19).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF63D7DD)
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFB8F66A),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                cam.currentLens == CameraLensDirectionType.rear
                                    ? 'بث حي · خلفية'
                                    : 'بث حي · أمامية',
                                style: const TextStyle(
                                  color: Color(0xFFEBF2FC),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Rotation info — bottom-right
                      Positioned(
                        bottom: 8,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF080E19).withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${cam.sensorRotationDegrees}° · '
                            '${cam.currentLens == CameraLensDirectionType.rear ? "خلفية" : "أمامية"}',
                            style: const TextStyle(
                              color: Color(0xFF96ADC7),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Stopped / permission state
                      Center(
                        child: SingleChildScrollView(
                            child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              !cam.hasPermission
                                  ? Icons.no_photography_outlined
                                  : Icons.videocam_off_outlined,
                              size: 48,
                              color: !cam.hasPermission
                                  ? const Color(0xFFFF8699)
                                  : const Color(0xFF667F9D),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              !cam.hasPermission
                                  ? (cam.isPermanentlyDenied
                                      ? 'تم رفض إذن الكاميرا بشكل دائم.\nيرجى تفعيله من إعدادات النظام.'
                                      : 'يرجى منح إذن الكاميرا\nلبدء المعاينة المباشرة.')
                                  : (cam.errorMessage ??
                                      'الكاميرا متوقفة\nلا يتم حفظ أي صور أو فيديو'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: !cam.hasPermission
                                    ? const Color(0xFFFF8699)
                                    : const Color(0xFF96ADC7),
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            if (!cam.hasPermission) ...[
                              const SizedBox(height: 14),
                              if (cam.isPermanentlyDenied)
                                ElevatedButton.icon(
                                  onPressed: () => cam.openDeviceSettings(),
                                  icon: const Icon(Icons.settings_outlined,
                                      size: 16),
                                  label: const Text('فتح إعدادات التطبيق'),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      appState.startCameraPreview(),
                                  icon: const Icon(Icons.check_circle_outline,
                                      size: 16),
                                  label: const Text('منح إذن الكاميرا'),
                                ),
                            ],
                          ],
                        )),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: bannerGap),

          // ── Camera Controls (always visible at bottom) ───────────────
          Container(
            padding: EdgeInsets.all(ctrlPad),
            decoration: BoxDecoration(
              color: const Color(0xFF111C2C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF283A50)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Start / Stop — full width, min 48px
                SizedBox(
                  height: btnHeight,
                  child: ElevatedButton.icon(
                    onPressed: cam.isRunning
                        ? () => appState.stopCameraPreview()
                        : () => appState.startCameraPreview(),
                    icon: Icon(cam.isRunning
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded),
                    label: Text(
                      cam.isRunning ? 'إيقاف المعاينة' : 'بدء المعاينة الحية',
                    ),
                  ),
                ),
                SizedBox(height: betweenGap),
                // Switch + Flex — side by side
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: btnHeight2,
                        child: OutlinedButton.icon(
                          onPressed: () => appState.switchCameraLens(),
                          icon:
                              const Icon(Icons.cameraswitch_rounded, size: 18),
                          label: Text(
                            cam.currentLens == CameraLensDirectionType.rear
                                ? 'تبديل للأمامية'
                                : 'تبديل للخلفية',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: btnHeight2,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final next =
                                cam.currentPosture == FoldablePosture.flatOpen
                                    ? FoldablePosture.halfOpenedFlex
                                    : FoldablePosture.flatOpen;
                            appState.setFoldablePosture(next);
                          },
                          icon: const Icon(Icons.screen_rotation_alt_rounded,
                              size: 18),
                          label: Text(
                            cam.currentPosture == FoldablePosture.flatOpen
                                ? 'وسم Flex يدوي'
                                : 'وسم الشاشة مفتوحة',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
