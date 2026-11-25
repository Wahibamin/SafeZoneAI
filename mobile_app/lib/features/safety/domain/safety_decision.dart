enum SafetyStatus {
  compliant, // ملتزم (مثل with_mask بثقة كافية)
  violation, // مخالف (مثل without_mask أو mask_weared_incorrect بثقة كافية)
  review, // مراجعة بشرية (ثقة منخفضة، وجه غير واضح، أو تعارض قراءات)
}

extension SafetyStatusExtension on SafetyStatus {
  String get dbValue {
    switch (this) {
      case SafetyStatus.compliant:
        return 'compliant';
      case SafetyStatus.violation:
        return 'violation';
      case SafetyStatus.review:
        return 'review';
    }
  }

  String get arabicLabel {
    switch (this) {
      case SafetyStatus.compliant:
        return 'ملتزم (COMPLIANT)';
      case SafetyStatus.violation:
        return 'مخالف (VIOLATION)';
      case SafetyStatus.review:
        return 'يتطلب مراجعة (REVIEW)';
    }
  }

  static SafetyStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'compliant':
        return SafetyStatus.compliant;
      case 'violation':
        return SafetyStatus.violation;
      default:
        return SafetyStatus.review;
    }
  }
}

/// Contract defined in MODEL_CONTRACT.md:
/// {status, evidenceFrames, reason, timestampMs}
class SafetyDecision {
  final SafetyStatus status;
  final int evidenceFrames;
  final String reason;
  final int timestampMs;
  final String? dominantLabel;
  final double? representativeConfidence;

  const SafetyDecision({
    required this.status,
    required this.evidenceFrames,
    required this.reason,
    required this.timestampMs,
    this.dominantLabel,
    this.representativeConfidence,
  });
}
