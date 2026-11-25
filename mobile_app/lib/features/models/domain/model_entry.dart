import 'dart:convert';

class ModelEntry {
  final String id;
  final String displayName;
  final String filePath;
  final String sha256;
  final String format; // 'tflite'
  final String task; // 'detect'
  final String? family;
  final int inputWidth;
  final int inputHeight;
  final String inputLayout;
  final String tensorDtype;
  final Map<String, String> labels;
  final Map<String, dynamic> metadata;
  final String validationState; // 'pending' | 'valid' | 'invalid'
  final String? errorMessage;
  final String importedAt;
  final String? lastValidatedAt;

  const ModelEntry({
    required this.id,
    required this.displayName,
    required this.filePath,
    required this.sha256,
    this.format = 'tflite',
    this.task = 'detect',
    this.family,
    required this.inputWidth,
    required this.inputHeight,
    required this.inputLayout,
    required this.tensorDtype,
    required this.labels,
    this.metadata = const {},
    this.validationState = 'pending',
    this.errorMessage,
    required this.importedAt,
    this.lastValidatedAt,
  });

  bool get isValid => validationState == 'valid';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'display_name': displayName,
      'file_path': filePath,
      'sha256': sha256,
      'format': format,
      'task': task,
      'family': family,
      'input_width': inputWidth,
      'input_height': inputHeight,
      'input_layout': inputLayout,
      'tensor_dtype': tensorDtype,
      'labels_json': jsonEncode(labels),
      'metadata_json': jsonEncode(metadata),
      'validation_state': validationState,
      'error_message': errorMessage,
      'imported_at': importedAt,
      'last_validated_at': lastValidatedAt,
    };
  }

  factory ModelEntry.fromMap(Map<String, dynamic> map) {
    final rawLabels = jsonDecode(map['labels_json'] as String? ?? '{}')
        as Map<String, dynamic>;
    final rawMeta = jsonDecode(map['metadata_json'] as String? ?? '{}')
        as Map<String, dynamic>;
    return ModelEntry(
      id: map['id'] as String,
      displayName: map['display_name'] as String,
      filePath: map['file_path'] as String,
      sha256: map['sha256'] as String,
      format: map['format'] as String? ?? 'tflite',
      task: map['task'] as String? ?? 'detect',
      family: map['family'] as String?,
      inputWidth: map['input_width'] as int,
      inputHeight: map['input_height'] as int,
      inputLayout: map['input_layout'] as String,
      tensorDtype: map['tensor_dtype'] as String,
      labels: rawLabels.map((k, v) => MapEntry(k.toString(), v.toString())),
      metadata: rawMeta,
      validationState: map['validation_state'] as String? ?? 'pending',
      errorMessage: map['error_message'] as String?,
      importedAt: map['imported_at'] as String,
      lastValidatedAt: map['last_validated_at'] as String?,
    );
  }
}

class ModelProfile {
  final String id;
  final String modelId;
  final String profileName;
  final Map<String, String>
      classMapping; // label -> compliant | violation | review
  final double confidenceThreshold;
  final double iouThreshold;
  final int minEvidenceFrames;
  final int maxGapMs;
  final String createdAt;

  const ModelProfile({
    required this.id,
    required this.modelId,
    required this.profileName,
    required this.classMapping,
    this.confidenceThreshold = 0.45,
    this.iouThreshold = 0.45,
    this.minEvidenceFrames = 3,
    this.maxGapMs = 600,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'model_id': modelId,
      'profile_name': profileName,
      'class_mapping_json': jsonEncode(classMapping),
      'confidence_threshold': confidenceThreshold,
      'iou_threshold': iouThreshold,
      'min_evidence_frames': minEvidenceFrames,
      'max_gap_ms': maxGapMs,
      'created_at': createdAt,
    };
  }

  factory ModelProfile.fromMap(Map<String, dynamic> map) {
    final rawMap = jsonDecode(map['class_mapping_json'] as String? ?? '{}')
        as Map<String, dynamic>;
    return ModelProfile(
      id: map['id'] as String,
      modelId: map['model_id'] as String,
      profileName: map['profile_name'] as String,
      classMapping: rawMap.map((k, v) => MapEntry(k.toString(), v.toString())),
      confidenceThreshold: (map['confidence_threshold'] as num).toDouble(),
      iouThreshold: (map['iou_threshold'] as num).toDouble(),
      minEvidenceFrames: map['min_evidence_frames'] as int,
      maxGapMs: map['max_gap_ms'] as int,
      createdAt: map['created_at'] as String,
    );
  }
}

class ModelCheck {
  final String id;
  final String modelId;
  final String testedAt;
  final bool passed;
  final String? device;
  final String? runtimeName;
  final double? inferenceMs;
  final String? detail;

  const ModelCheck({
    required this.id,
    required this.modelId,
    required this.testedAt,
    required this.passed,
    this.device,
    this.runtimeName,
    this.inferenceMs,
    this.detail,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'model_id': modelId,
      'tested_at': testedAt,
      'passed': passed ? 1 : 0,
      'device': device,
      'runtime_name': runtimeName,
      'inference_ms': inferenceMs,
      'detail': detail,
    };
  }

  factory ModelCheck.fromMap(Map<String, dynamic> map) {
    return ModelCheck(
      id: map['id'] as String,
      modelId: map['model_id'] as String,
      testedAt: map['tested_at'] as String,
      passed: (map['passed'] as int) == 1,
      device: map['device'] as String?,
      runtimeName: map['runtime_name'] as String?,
      inferenceMs: (map['inference_ms'] as num?)?.toDouble(),
      detail: map['detail'] as String?,
    );
  }
}

/// Contract defined in MODEL_CONTRACT.md
class ModelActivationResult {
  final bool success;
  final String? modelId;
  final String runtime;
  final String? error;
  final bool rolledBack;
  final String? previousModelId;
  final double? warmupInferenceMs;

  const ModelActivationResult({
    required this.success,
    required this.modelId,
    required this.runtime,
    this.error,
    required this.rolledBack,
    this.previousModelId,
    this.warmupInferenceMs,
  });
}
