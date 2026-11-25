import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safezone_mobile/app/app_state.dart';
import 'package:safezone_mobile/features/models/data/native_model_runtime.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('reference YUV camera planes and rotations preserve boxes',
      (tester) async {
    final app = AppState.createDefault();
    await app.initialize();
    expect(app.activeModel, isNotNull);
    final fixtures = '${(await getTemporaryDirectory()).path}/model_acceptance';
    final reference = jsonDecode(
        await File('$fixtures/reference_expected.json').readAsString()) as Map;
    final expected = reference['boxes'] as List;
    expect(expected, isNotEmpty);
    final evidence = <String, dynamic>{};
    for (final accelerator in ['cpu', 'gpu']) {
      await app.inferenceEngine.setAccelerator(accelerator);
      for (final rotation in [0, 90, 270]) {
        final args = Map<String, dynamic>.from(jsonDecode(
            await File('$fixtures/geometry_$rotation.json').readAsString()) as Map);
        args['planes'] = (args['planes'] as List).map((raw) {
          final p = Map<String, dynamic>.from(raw as Map);
          p['bytes'] = base64Decode(p['bytes'] as String);
          return p;
        }).toList();
        args.addAll({'contract': app.activeModel!.metadata['contract'],
          'confidence': .45, 'iou': .45});
        final result = await NativeModelRuntime.channel
            .invokeMapMethod<String, dynamic>('inferCamera', args);
        expect(result!['width'], 432);
        expect(result['height'], 768);
        final actual = result['detections'] as List;
        expect(actual.length, expected.length);
        final overlaps = <double>[];
        for (var i = 0; i < expected.length; i++) {
          final a = (expected[i] as List).cast<num>();
          var best = 0.0;
          for (final raw in actual) {
            final d = raw as Map;
            if (d['class_id'] != (reference['classes'] as List)[i]) continue;
            final b = (d['box'] as List).cast<num>();
            final intersection = max(0.0, min(a[2], b[2]) - max(a[0], b[0])) *
                max(0.0, min(a[3], b[3]) - max(a[1], b[1]));
            final union = (a[2]-a[0])*(a[3]-a[1]) +
                (b[2]-b[0])*(b[3]-b[1]) - intersection;
            best = max(best, intersection / max(union, 1e-9));
          }
          expect(best, greaterThan(.9));
          overlaps.add(best);
        }
        evidence['${accelerator}_$rotation'] = {'iou': overlaps, 'result': result};
      }
    }
    await app.inferenceEngine.setAccelerator('cpu');
    evidence['passed'] = true;
    await File('${(await getApplicationSupportDirectory()).path}/device_geometry.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
  });
}
