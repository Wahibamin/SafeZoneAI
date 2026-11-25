class SafeZoneException implements Exception {
  final String code;
  final String messageAr;
  final String? technicalDetail;

  const SafeZoneException({
    required this.code,
    required this.messageAr,
    this.technicalDetail,
  });

  @override
  String toString() =>
      '[$code] $messageAr${technicalDetail != null ? " ($technicalDetail)" : ""}';
}

class CameraOwnershipException extends SafeZoneException {
  const CameraOwnershipException(String detail)
      : super(
          code: 'CAMERA_OWNERSHIP_CONFLICT',
          messageAr:
              'لا يمكن فتح جلستي كاميرا في نفس الوقت حفاظاً على استقرار الجهاز.',
          technicalDetail: detail,
        );
}

class ModelValidationException extends SafeZoneException {
  const ModelValidationException(String messageAr, {String? detail})
      : super(
          code: 'MODEL_VALIDATION_FAILED',
          messageAr: messageAr,
          technicalDetail: detail,
        );
}

class ModelActivationRollbackException extends SafeZoneException {
  final String? restoredModelId;

  const ModelActivationRollbackException({
    required super.messageAr,
    this.restoredModelId,
    String? detail,
  }) : super(
          code: 'MODEL_ACTIVATION_ROLLED_BACK',
          technicalDetail: detail,
        );
}
