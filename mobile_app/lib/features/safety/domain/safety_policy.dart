import '../../detection/domain/detection_result.dart';
import '../../models/domain/model_entry.dart';
import 'safety_decision.dart';

abstract class SafetyPolicy {
  SafetyDecision decide({
    required List<DetectionResult> detections,
    required ModelProfile profile,
    required int timestampMs,
  });
}

/// Default SafetyPolicy implementing MODEL_CONTRACT.md & ADR-007:
/// - Maps labels dynamically via ModelProfile.classMapping
/// - Never invents compliance when detections are empty, below threshold, or contradictory
/// - Emits SafetyStatus.review whenever uncertainty or conflict occurs
class DefaultSafetyPolicy implements SafetyPolicy {
  const DefaultSafetyPolicy();

  @override
  SafetyDecision decide({
    required List<DetectionResult> detections,
    required ModelProfile profile,
    required int timestampMs,
  }) {
    if (detections.isEmpty) {
      return SafetyDecision(
        status: SafetyStatus.review,
        evidenceFrames: 0,
        reason: 'لا يوجد وجه مرصود بوضوح في مجال الكاميرا.',
        timestampMs: timestampMs,
      );
    }

    // Separate detections above and below profile confidence threshold
    final confident = <DetectionResult>[];
    final uncertain = <DetectionResult>[];

    for (final d in detections) {
      if (d.confidence >= profile.confidenceThreshold) {
        confident.add(d);
      } else {
        uncertain.add(d);
      }
    }

    if (confident.isEmpty) {
      final bestUncertain = uncertain.reduce(
        (a, b) => a.confidence >= b.confidence ? a : b,
      );
      return SafetyDecision(
        status: SafetyStatus.review,
        evidenceFrames: 1,
        reason:
            'ثقة الكشف (${(bestUncertain.confidence * 100).toStringAsFixed(1)}%) أقل من عتبة الاعتماد (${(profile.confidenceThreshold * 100).toStringAsFixed(0)}%).',
        timestampMs: timestampMs,
        dominantLabel: bestUncertain.label,
        representativeConfidence: bestUncertain.confidence,
      );
    }

    // Map confident detections through profile.classMapping
    final mappedStatuses = <SafetyStatus>{};
    DetectionResult? highestViolation;
    DetectionResult? highestCompliant;

    for (final d in confident) {
      final rawMapped = profile.classMapping[d.label];
      if (rawMapped == null) {
        return SafetyDecision(
          status: SafetyStatus.review,
          evidenceFrames: 1,
          reason:
              'الفئة المرصودة (${d.label}) غير معرّفة في ملف قواعد السلامة النشط.',
          timestampMs: timestampMs,
          dominantLabel: d.label,
          representativeConfidence: d.confidence,
        );
      }
      final status = SafetyStatusExtension.fromString(rawMapped);
      mappedStatuses.add(status);

      if (status == SafetyStatus.violation) {
        if (highestViolation == null ||
            d.confidence > highestViolation.confidence) {
          highestViolation = d;
        }
      } else if (status == SafetyStatus.compliant) {
        if (highestCompliant == null ||
            d.confidence > highestCompliant.confidence) {
          highestCompliant = d;
        }
      }
    }

    // Check if two overlapping boxes on the same face report conflicting statuses
    if (mappedStatuses.contains(SafetyStatus.violation) &&
        mappedStatuses.contains(SafetyStatus.compliant) &&
        highestViolation != null &&
        highestCompliant != null) {
      final iou = _computeIoU(highestViolation.bbox, highestCompliant.bbox);
      if (iou >= profile.iouThreshold) {
        return SafetyDecision(
          status: SafetyStatus.review,
          evidenceFrames: 1,
          reason:
              'تعارض في قراءات نفس الوجه (ملتزم ومخالف في آنٍ واحد) — يتطلب مراجعة.',
          timestampMs: timestampMs,
          dominantLabel: highestViolation.label,
          representativeConfidence: highestViolation.confidence,
        );
      }
    }

    // Prioritize safety violation if present with high confidence
    if (highestViolation != null) {
      return SafetyDecision(
        status: SafetyStatus.violation,
        evidenceFrames: 1,
        reason:
            'تم رصد مخالفة سلامة (${highestViolation.label}) بثقة ${(highestViolation.confidence * 100).toStringAsFixed(1)}%.',
        timestampMs: timestampMs,
        dominantLabel: highestViolation.label,
        representativeConfidence: highestViolation.confidence,
      );
    }

    if (highestCompliant != null) {
      return SafetyDecision(
        status: SafetyStatus.compliant,
        evidenceFrames: 1,
        reason:
            'ملتزم بارتداء الكمامة الصحيحة (${highestCompliant.label}) بثقة ${(highestCompliant.confidence * 100).toStringAsFixed(1)}%.',
        timestampMs: timestampMs,
        dominantLabel: highestCompliant.label,
        representativeConfidence: highestCompliant.confidence,
      );
    }

    return SafetyDecision(
      status: SafetyStatus.review,
      evidenceFrames: 1,
      reason: 'قراءة غير حاسمة تتطلب مراجعة.',
      timestampMs: timestampMs,
    );
  }

  double _computeIoU(NormalizedBox a, NormalizedBox b) {
    final interLeft = a.left > b.left ? a.left : b.left;
    final interTop = a.top > b.top ? a.top : b.top;
    final interRight = a.right < b.right ? a.right : b.right;
    final interBottom = a.bottom < b.bottom ? a.bottom : b.bottom;

    final interWidth = (interRight - interLeft).clamp(0.0, 1.0);
    final interHeight = (interBottom - interTop).clamp(0.0, 1.0);
    final interArea = interWidth * interHeight;
    if (interArea <= 0) return 0.0;

    final unionArea = a.area + b.area - interArea;
    return unionArea <= 0 ? 0.0 : interArea / unionArea;
  }
}
