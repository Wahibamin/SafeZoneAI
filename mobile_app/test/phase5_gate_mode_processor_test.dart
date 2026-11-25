import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/features/detection/domain/detection_result.dart';
import 'package:safezone_mobile/features/gate/domain/gate_analyzer.dart';
import 'package:safezone_mobile/features/models/domain/model_entry.dart';
import 'package:safezone_mobile/features/safety/domain/safety_decision.dart';

void main() {
  group('Phase 05 Gate Mode Evidence Aggregation Tests (T14, T15)', () {
    test(
        'T14: Reference Scenario — 3 sequential passes produce 2 violations and 1 compliant',
        () {
      final processor = GateModeProcessor();
      const profile = ModelProfile(
        id: 'prf-gate',
        modelId: 'mdl-v4',
        profileName: 'Gate Profile',
        classMapping: {
          'with_mask': 'compliant',
          'without_mask': 'violation',
          'mask_weared_incorrect': 'violation',
        },
        minEvidenceFrames: 3,
        maxGapMs: 600,
        createdAt: '2026-11-18T00:00:00Z',
      );
      const box =
          NormalizedBox(left: 0.35, top: 0.25, right: 0.65, bottom: 0.75);

      // Pass 1: without_mask (violation)
      for (var i = 0; i < 4; i++) {
        processor.consumeFrameDetections(
          detections: [
            DetectionResult(
              timestampMs: 1000 + i * 100,
              classId: 1,
              label: 'without_mask',
              confidence: 0.90,
              bbox: box,
              modelId: 'mdl-v4',
            ),
          ],
          profile: profile,
          timestampMs: 1000 + i * 100,
        );
      }

      // Pass 2: with_mask (compliant) after 1200ms gap
      for (var i = 0; i < 4; i++) {
        processor.consumeFrameDetections(
          detections: [
            DetectionResult(
              timestampMs: 2600 + i * 100,
              classId: 0,
              label: 'with_mask',
              confidence: 0.93,
              bbox: box,
              modelId: 'mdl-v4',
            ),
          ],
          profile: profile,
          timestampMs: 2600 + i * 100,
        );
      }

      // Pass 3: mask_weared_incorrect (violation) after 1200ms gap
      for (var i = 0; i < 4; i++) {
        processor.consumeFrameDetections(
          detections: [
            DetectionResult(
              timestampMs: 4200 + i * 100,
              classId: 2,
              label: 'mask_weared_incorrect',
              confidence: 0.85,
              bbox: box,
              modelId: 'mdl-v4',
            ),
          ],
          profile: profile,
          timestampMs: 4200 + i * 100,
        );
      }

      processor.flushOpenEpisode(profile: profile, currentTimestampMs: 5500);

      final episodes = processor.completedEpisodes;
      expect(episodes.length, 3);
      expect(episodes[0].finalStatus, SafetyStatus.violation);
      expect(episodes[1].finalStatus, SafetyStatus.compliant);
      expect(episodes[2].finalStatus, SafetyStatus.violation);
    });
  });
}
