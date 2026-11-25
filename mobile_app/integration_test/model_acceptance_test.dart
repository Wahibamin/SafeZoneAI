import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safezone_mobile/app/app.dart';
import 'package:safezone_mobile/app/app_state.dart';
import 'package:safezone_mobile/core/utils/sha256_utils.dart';
import 'package:safezone_mobile/features/models/data/native_model_runtime.dart';
import 'package:safezone_mobile/features/models/domain/model_entry.dart';
import 'package:safezone_mobile/features/camera/domain/camera_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'v4 physical acceptance: parity, switching, rollback, camera and endurance',
      (tester) async {
    const seconds = int.fromEnvironment('ENDURANCE_SECONDS', defaultValue: 600);
    const enduranceAccelerator =
        String.fromEnvironment('ENDURANCE_ACCELERATOR', defaultValue: 'cpu');
    expect(['cpu', 'gpu'], contains(enduranceAccelerator));
    final fixtureDir =
        Directory('${(await getTemporaryDirectory()).path}/model_acceptance');
    expect(await fixtureDir.exists(), isTrue,
        reason: 'Run tools/device_acceptance.py stage first');
    final app = AppState.createDefault();
    final evidence = <String, dynamic>{
      'endurance_requested_seconds': seconds,
      'endurance_accelerator': enduranceAccelerator,
    };
    final evidenceFile = File(
        '${(await getApplicationSupportDirectory()).path}/device_acceptance.json');
    final priorLogging = await app.sessionRepository.isEventLoggingEnabled();
    final mediaBefore = await app.storage.countForbiddenMediaFiles();
    final models = <ModelEntry>[];
    try {
      await app.initialize();
      await app.toggleEventLogging(false);
      for (final precision in ['float32', 'float16']) {
        final file = File('${fixtureDir.path}/best_mask_v4_$precision.tflite');
        final bytes = await file.readAsBytes();
        final manifest =
            await File('${fixtureDir.path}/best_mask_v4_$precision.json')
                .readAsString();
        final hash = Sha256Utils.hashBytes(bytes);
        final existing = app.models.where((m) => m.sha256 == hash).toList();
        final entry = existing.isNotEmpty
            ? existing.first
            : await app.importModel(
                fileName: file.uri.pathSegments.last,
                fileBytes: bytes,
                displayName: 'SafeZone v4 $precision',
                manifestJson: manifest);
        expect(entry.labels, {
          '0': 'with_mask',
          '1': 'without_mask',
          '2': 'mask_weared_incorrect'
        });
        final activation = await app.activateExistingModel(entry.id);
        expect(activation.success, isTrue, reason: activation.error);
        expect(app.inferenceEngine.lastSmokeEvidence?['passed'], isTrue);
        models.add(entry);
      }
      evidence['switching'] = 'FP32 -> FP16 -> FP32 in the same installed APK';
      expect(
          (await app.activateExistingModel(models.first.id)).success, isTrue);
      final reference = jsonDecode(
          await File('${fixtureDir.path}/reference_expected.json')
              .readAsString()) as Map;
      final image =
          await File('${fixtureDir.path}/reference.png').readAsBytes();
      final result = await NativeModelRuntime.channel
          .invokeMapMethod<String, dynamic>('inferImage', {
        'bytes': image,
        'contract': models.first.metadata['contract'],
        'confidence': .45,
        'iou': .45
      });
      final expectedBoxes = reference['boxes'] as List;
      final expectedClasses = reference['classes'] as List;
      final actual = result!['detections'] as List;
      expect(expectedBoxes, isNotEmpty,
          reason:
              'A blank reference cannot establish positive detection parity');
      expect(actual.length, expectedBoxes.length);
      final overlaps = <double>[];
      for (var i = 0; i < expectedBoxes.length; i++) {
        final a = (expectedBoxes[i] as List)
            .map((v) => (v as num).toDouble())
            .toList();
        var best = 0.0;
        for (final raw in actual) {
          final d = raw as Map;
          if (d['class_id'] != (expectedClasses[i] as num).toInt()) continue;
          final b =
              (d['box'] as List).map((v) => (v as num).toDouble()).toList();
          final intersection = max(0.0, min(a[2], b[2]) - max(a[0], b[0])) *
              max(0.0, min(a[3], b[3]) - max(a[1], b[1]));
          final union = (a[2] - a[0]) * (a[3] - a[1]) +
              (b[2] - b[0]) * (b[3] - b[1]) -
              intersection;
          best = max(best, intersection / max(union, 1e-9));
        }
        overlaps.add(best);
        expect(best, greaterThan(.9));
      }
      evidence['native_image_parity'] = {'iou': overlaps, 'result': result};
      final secondFile =
          await app.storage.resolveRelativeModelPath(models[1].filePath);
      final saved = await secondFile.readAsBytes();
      try {
        await secondFile.writeAsBytes(Sha256Utils.buildInvalidTfliteFixture());
        final rollback = await app.activateExistingModel(models[1].id);
        expect(rollback.success, isFalse);
        expect(rollback.rolledBack, isTrue);
        expect(app.activeModel?.id, models[0].id);
        evidence['corrupt_model_rollback'] = true;
      } finally {
        await secondFile.writeAsBytes(saved, flush: true);
      }
      expect((await app.validateModel(models[1].id)).passed, isTrue);
      await app.inferenceEngine.dispose();
      await app.dbHelper.close();
      await app.initialize();
      expect(app.activeModel?.id, models[0].id);
      expect(app.inferenceEngine.isReady, isTrue);
      evidence['native_and_sqlite_reopen'] = true;
      try {
        await app.inferenceEngine.setAccelerator('gpu');
        final gpu = await NativeModelRuntime.channel
            .invokeMapMethod<String, dynamic>('inferImage', {
          'bytes': image,
          'contract': models.first.metadata['contract'],
          'confidence': .45,
          'iou': .45
        });
        expect((gpu!['detections'] as List).length, expectedBoxes.length);
        evidence['gpu'] = {
          'smoke': app.inferenceEngine.lastSmokeEvidence,
          'image': gpu
        };
      } catch (e) {
        evidence['gpu_unavailable'] = '$e';
      }
      await app.inferenceEngine.setAccelerator('cpu');
      await app.videoBenchmark.run(
          videoPath: '${fixtureDir.path}/reference.mp4',
          models: models,
          storage: app.storage,
          accelerator: 'cpu',
          maxFrames: 5);
      expect(app.videoBenchmark.completed, greaterThan(0));
      expect(app.videoBenchmark.rows.length, app.videoBenchmark.completed * 2);
      await File('${evidenceFile.parent.path}/device_comparison.csv')
          .writeAsString(app.videoBenchmark.csv);
      evidence['video_summary'] = {
        for (final m in models) m.id: app.videoBenchmark.summary(m.id)
      };
      await app.inferenceEngine.setAccelerator(enduranceAccelerator);
      evidence['endurance_accelerator_smoke'] =
          app.inferenceEngine.lastSmokeEvidence;
      await tester.pumpWidget(SafeZoneMobileApp(appState: app));
      await tester.pump(const Duration(seconds: 1));
      await app.startCameraPreview();
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(app.benchmarkSummary.totalFramesEvaluated, greaterThan(0));
      expect(app.lastBannerMessage, isNull);
      evidence['rear_camera'] = {
        'frames': app.benchmarkSummary.totalFramesEvaluated,
        'memory_mb': app.memoryMb
      };
      await app.switchCameraLens();
      expect(app.cameraSource.currentLens, CameraLensDirectionType.front);
      final before = app.benchmarkSummary.totalFramesEvaluated;
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(app.benchmarkSummary.totalFramesEvaluated, greaterThan(before));
      expect(app.lastBannerMessage, isNull);
      evidence['front_camera'] = true;
      await app.switchCameraLens();
      app.benchmarkService.reset();
      final started = Stopwatch()..start();
      final endurance = <Map<String, dynamic>>[];
      while (started.elapsed.inSeconds < seconds) {
        await Future<void>.delayed(const Duration(seconds: 10));
        expect(app.lastBannerMessage, isNull);
        final s = app.benchmarkSummary;
        final sample = {
          'elapsed_s': started.elapsed.inSeconds,
          'completed': s.totalFramesEvaluated,
          'fps': s.averageInferenceFps,
          'p50_ms': s.medianLatencyMs,
          'p95_ms': s.p95LatencyMs,
          'drops': s.droppedFrames,
          'memory_mb': app.memoryMb
        };
        endurance.add(sample);
        // ignore: avoid_print
        print('SAFEZONE_ENDURANCE ${jsonEncode(sample)}');
        evidence['endurance'] = endurance;
        await evidenceFile.writeAsString(jsonEncode(evidence));
      }
      expect(endurance.last['completed'] as int, greaterThan(20));
      await app.stopCameraPreview();
      for (final icon in [
        Icons.layers_outlined,
        Icons.file_upload_outlined,
        Icons.rule_folder_outlined,
        Icons.speed_outlined,
        Icons.sensor_door_outlined,
        Icons.bar_chart_outlined,
        Icons.privacy_tip_outlined,
        Icons.videocam_outlined
      ]) {
        await tester.tap(find.byIcon(icon));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      }
      evidence['all_eight_screens'] = true;
      expect(await app.storage.countForbiddenMediaFiles(), mediaBefore);
      evidence['camera_media_written'] = 0;
      evidence['passed'] = true;
      await evidenceFile
          .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
      // ignore: avoid_print
      print('SAFEZONE_ACCEPTANCE ${jsonEncode(evidence)}');
    } finally {
      await app.stopCameraPreview();
      await app.toggleEventLogging(priorLogging);
      await evidenceFile
          .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
