import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/features/detection/domain/detection_result.dart';
import 'package:safezone_mobile/features/models/domain/model_entry.dart';
import 'package:safezone_mobile/features/safety/domain/safety_decision.dart';
import 'package:safezone_mobile/features/safety/domain/safety_policy.dart';

void main() {
  const policy = DefaultSafetyPolicy();
  const profile = ModelProfile(
    id: 'prf-1',
    modelId: 'mdl-1',
    profileName: 'Default Mask Profile',
    classMapping: {
      'with_mask': 'compliant',
      'without_mask': 'violation',
      'mask_weared_incorrect': 'violation',
    },
    confidenceThreshold: 0.45,
    iouThreshold: 0.45,
    createdAt: '2026-11-18T00:00:00Z',
  );

  group('Phase 03 Mask Detection & REVIEW Status Mapping (T10, T11, T19)', () {
    test(
        'T10 & T11: Maps with_mask -> COMPLIANT and without_mask/incorrect -> VIOLATION',
        () {
      const box = NormalizedBox(left: 0.2, top: 0.2, right: 0.6, bottom: 0.6);

      final compliantRes = policy.decide(
        detections: const [
          DetectionResult(
            timestampMs: 1000,
            classId: 0,
            label: 'with_mask',
            confidence: 0.91,
            bbox: box,
            modelId: 'mdl-1',
          ),
        ],
        profile: profile,
        timestampMs: 1000,
      );
      expect(compliantRes.status, SafetyStatus.compliant);

      final violationRes = policy.decide(
        detections: const [
          DetectionResult(
            timestampMs: 2000,
            classId: 2,
            label: 'mask_weared_incorrect',
            confidence: 0.78,
            bbox: box,
            modelId: 'mdl-1',
          ),
        ],
        profile: profile,
        timestampMs: 2000,
      );
      expect(violationRes.status, SafetyStatus.violation);
    });

    test(
        'T11 & T19: Emits REVIEW when face is missing or confidence is below threshold',
        () {
      const box = NormalizedBox(left: 0.2, top: 0.2, right: 0.6, bottom: 0.6);

      final emptyDecision = policy.decide(
        detections: const [],
        profile: profile,
        timestampMs: 3000,
      );
      expect(emptyDecision.status, SafetyStatus.review);

      final lowConfDecision = policy.decide(
        detections: const [
          DetectionResult(
            timestampMs: 4000,
            classId: 0,
            label: 'with_mask',
            confidence: 0.29,
            bbox: box,
            modelId: 'mdl-1',
          ),
        ],
        profile: profile,
        timestampMs: 4000,
      );
      expect(lowConfDecision.status, SafetyStatus.review);
    });
  });
}
