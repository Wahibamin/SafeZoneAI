import '../../../core/errors/app_exceptions.dart';
import '../../camera/domain/camera_source.dart';
import '../../models/data/native_model_runtime.dart';
import '../domain/detection_result.dart';
import '../domain/inference_engine.dart';

/// Real native inference, with a single in-flight frame and no synthetic fallback.
class LiteRtYoloInferenceEngine implements InferenceEngine {
  final NativeModelRuntime _runtime;
  LiteRtYoloInferenceEngine({NativeModelRuntime? runtime})
      : _runtime = runtime ?? NativeModelRuntime();
  String? _activeModelId;
  String? _path;
  String _accelerator = 'cpu';
  Map<String, String> _labels = {};
  bool _busy = false;
  int _dropped = 0;
  @override
  Map<String, dynamic>? lastSmokeEvidence;
  @override
  String get runtimeName =>
      'LiteRT/1.4.2 ${_accelerator.toUpperCase()} Interpreter';
  @override
  String? get activeModelId => _activeModelId;
  @override
  String get activeAccelerator => _accelerator;
  @override
  int get droppedFramesCount => _dropped;
  @override
  bool get isReady => _activeModelId != null;
  @override
  Future<void> setAccelerator(String accelerator) async {
    if (!['cpu', 'gpu'].contains(accelerator) || _path == null || _busy) {
      throw const ModelValidationException(
          'يلزم نموذج نشط واختيار CPU أو GPU أثناء توقف الكاميرا.');
    }
    final evidence = await NativeModelRuntime.channel
        .invokeMapMethod<String, dynamic>(
            'switchModel', {'filePath': _path, 'accelerator': accelerator});
    if (evidence?['passed'] != true) {
      throw const ModelValidationException('فشل اختبار المسرع.');
    }
    _accelerator = accelerator;
    lastSmokeEvidence = evidence;
  }

  @override
  Future<double> switchModel(
      {required String modelId,
      required String absoluteFilePath,
      required int inputWidth,
      required int inputHeight,
      required Map<String, String> labels}) async {
    final evidence = await _runtime.invoke('switchModel', absoluteFilePath);
    if (evidence['passed'] != true || evidence['inference_ms'] is! num) {
      throw const ModelValidationException('لم يرجع المحرك دليل استدلال ناجح.');
    }
    lastSmokeEvidence = evidence;
    _activeModelId = modelId;
    _path = absoluteFilePath;
    _accelerator = 'cpu';
    _labels = labels;
    return (evidence['inference_ms'] as num).toDouble();
  }

  @override
  Future<FrameInferenceOutput> inferFrame({
    required int frameNumber,
    required int timestampMs,
    int sensorRotationDegrees = 90,
    bool isFrontMirrored = false,
    CameraImageFrame? image,
    Map<String, dynamic>? contract,
    double confidenceThreshold = 0.45,
    double iouThreshold = 0.45,
  }) async {
    if (!isReady || image == null || contract == null) {
      throw const ModelValidationException(
          'يلزم نموذج نشط وإطار كاميرا حقيقي وعقد متحقق.');
    }
    if (_busy) {
      _dropped++;
      return FrameInferenceOutput(
          frameNumber: frameNumber,
          timestampMs: timestampMs,
          inferenceMs: 0,
          droppedByBackpressure: true,
          acceleratorUsed: activeAccelerator,
          detections: const []);
    }
    _busy = true;
    final id = _activeModelId!;
    final labels = Map<String, String>.from(_labels);
    try {
      final raw = await NativeModelRuntime.channel
          .invokeMapMethod<String, dynamic>('inferCamera', {
        'width': image.meta.width,
        'height': image.meta.height,
        'format': image.format,
        'rotation': sensorRotationDegrees,
        'contract': contract,
        'confidence': confidenceThreshold,
        'iou': iouThreshold,
        'planes': image.planes
            .map((p) => {
                  'bytes': p.bytes,
                  'rowStride': p.bytesPerRow,
                  'pixelStride': p.bytesPerPixel ?? 1
                })
            .toList(),
      });
      if (raw == null) {
        throw const ModelValidationException('لم يرجع المحرك نتيجة.');
      }
      final detections = (raw['detections'] as List).map((v) {
        final d = v as Map;
        final box =
            (d['box'] as List).map((v) => (v as num).toDouble()).toList();
        final cls = d['class_id'] as int;
        return DetectionResult(
            timestampMs: timestampMs,
            classId: cls,
            label: labels['$cls']!,
            confidence: (d['confidence'] as num).toDouble(),
            bbox: NormalizedBox(
                left: box[0], top: box[1], right: box[2], bottom: box[3]),
            modelId: id);
      }).toList();
      lastFrameTelemetry = raw;
      return FrameInferenceOutput(
          frameNumber: frameNumber,
          timestampMs: timestampMs,
          inferenceMs: (raw['inference_ms'] as num).toDouble(),
          droppedByBackpressure: false,
          acceleratorUsed: activeAccelerator,
          detections: detections);
    } finally {
      _busy = false;
    }
  }

  Map<String, dynamic>? lastFrameTelemetry;

  @override
  void setDiagnosticScenario(List<DetectionResult>? scenarioDetections) {
    throw const ModelValidationException(
        'النتائج المصطنعة غير متاحة في محرك الإنتاج.');
  }

  @override
  Future<void> dispose() async {
    _activeModelId = null;
    _path = null;
    lastSmokeEvidence = null;
    await NativeModelRuntime.channel.invokeMethod<void>('closeModels');
  }
}
