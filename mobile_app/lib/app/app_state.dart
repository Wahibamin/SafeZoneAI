import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../core/database/database_helper.dart';
import '../core/errors/app_exceptions.dart';
import '../core/storage/app_private_storage.dart';
import '../core/utils/csv_exporter.dart';

import '../features/benchmark/data/benchmark_service.dart';
import '../features/benchmark/data/video_benchmark_service.dart';
import '../features/benchmark/domain/benchmark_metrics.dart';
import '../features/camera/data/mobile_camera_service.dart';
import '../features/camera/domain/camera_source.dart';
import '../features/detection/data/litert_yolo_inference_engine.dart';
import '../features/detection/domain/detection_result.dart';
import '../features/detection/domain/inference_engine.dart';
import '../features/gate/domain/gate_analyzer.dart';
import '../features/gate/domain/gate_episode.dart';
import '../features/models/data/sqlite_model_repository.dart';
import '../features/models/domain/model_entry.dart';
import '../features/models/domain/model_repository.dart';
import '../features/safety/domain/safety_decision.dart';
import '../features/safety/domain/safety_policy.dart';
import '../features/statistics/data/sqlite_session_repository.dart';
import '../features/statistics/domain/session_models.dart';
import '../features/statistics/domain/session_repository.dart';

class AppState extends ChangeNotifier {
  final DatabaseHelper dbHelper;
  final AppPrivateStorage storage;
  final CameraSource cameraSource;
  final InferenceEngine inferenceEngine;
  final ModelRepository modelRepository;
  final SafetyPolicy safetyPolicy;
  final BenchmarkService benchmarkService;
  final VideoBenchmarkService videoBenchmark = VideoBenchmarkService();
  final GateAnalyzer gateAnalyzer;
  final SessionRepository sessionRepository;

  StreamSubscription<CameraImageFrame>? _cameraSub;
  bool _processing = false;
  bool _switching = false;
  bool _cameraTransition = false;
  bool _videoListenerAdded = false;
  int _generation = 0;
  Completer<void>? _idle;
  double memoryMb = 0;
  double? frameAspectRatio;

  Future<T> _changeModel<T>(Future<T> Function() action) async {
    if (videoBenchmark.running) {
      throw const ModelValidationException(
          'أوقف مقارنة الفيديو قبل تبديل النموذج.');
    }
    if (_switching) throw const ModelValidationException('تبديل نموذج جارٍ.');
    _switching = true;
    _generation++;
    try {
      await _idle?.future;
      await _flushGate();
      final result = await action();
      _models = await modelRepository.listModels();
      _activeModel = await modelRepository.getActiveModel();
      _activeProfile = _activeModel == null
          ? null
          : await modelRepository.getActiveProfileForModel(_activeModel!.id);
      _latestDetections = [];
      gateAnalyzer.resetEpisodes();
      benchmarkService.reset();
      _latestDecision = SafetyDecision(
          status: SafetyStatus.review,
          evidenceFrames: 0,
          reason: 'في انتظار دليل من النموذج النشط.',
          timestampMs: DateTime.now().millisecondsSinceEpoch);
      return result;
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  Future<void> _recordEpisode(PassageEpisode? ep) async {
    if (ep == null) return;
    await sessionRepository.recordEvent(
        status: ep.finalStatus,
        modelId: _activeModel?.id,
        modelLabel: ep.dominantLabel,
        confidence: ep.aggregatedConfidence,
        evidenceFrames: ep.evidenceFrames,
        durationMs: ep.durationMs,
        mode: 'gate');
  }

  Future<void> _flushGate() async {
    if (_activeProfile == null) return;
    await _recordEpisode(gateAnalyzer.flushOpenEpisode(
        profile: _activeProfile!,
        currentTimestampMs: DateTime.now().millisecondsSinceEpoch));
  }

  List<ModelEntry> _models = [];
  ModelEntry? _activeModel;
  ModelProfile? _activeProfile;
  List<DetectionResult> _latestDetections = [];
  SafetyDecision _latestDecision = const SafetyDecision(
    status: SafetyStatus.review,
    evidenceFrames: 0,
    reason: 'في انتظار بدء المعاينة وتفعيل النموذج.',
    timestampMs: 0,
  );
  bool _gateModeEnabled = false;
  bool _eventLoggingEnabled = false;
  int _forbiddenMediaCount = 0;
  String? _lastBannerMessage;

  AppState({
    required this.dbHelper,
    required this.storage,
    required this.cameraSource,
    required this.inferenceEngine,
    required this.modelRepository,
    required this.safetyPolicy,
    required this.benchmarkService,
    required this.gateAnalyzer,
    required this.sessionRepository,
  });

  factory AppState.createDefault() {
    final db = DatabaseHelper.instance;
    final store = AppPrivateStorage();
    final cam = MobileCameraService();
    final engine = LiteRtYoloInferenceEngine();
    final modelRepo = SqliteModelRepository(
      dbHelper: db,
      storage: store,
      inferenceEngine: engine,
    );
    const policy = DefaultSafetyPolicy();
    final bench = BenchmarkService(dbHelper: db);
    final gate = GateModeProcessor(safetyPolicy: policy);
    final sessionRepo = SqliteSessionRepository(dbHelper: db);

    return AppState(
      dbHelper: db,
      storage: store,
      cameraSource: cam,
      inferenceEngine: engine,
      modelRepository: modelRepo,
      safetyPolicy: policy,
      benchmarkService: bench,
      gateAnalyzer: gate,
      sessionRepository: sessionRepo,
    );
  }

  List<ModelEntry> get models => _models;
  ModelEntry? get activeModel => _activeModel;
  ModelProfile? get activeProfile => _activeProfile;
  List<DetectionResult> get latestDetections => _latestDetections;
  SafetyDecision get latestDecision => _latestDecision;
  bool get gateModeEnabled => _gateModeEnabled;
  bool get eventLoggingEnabled => _eventLoggingEnabled;
  int get forbiddenMediaCount => _forbiddenMediaCount;
  String? get lastBannerMessage => _lastBannerMessage;
  LiveSessionCounters get liveCounters => sessionRepository.liveCounters;
  BenchmarkSummary get benchmarkSummary => benchmarkService.computeSummary();
  List<PassageEpisode> get gateEpisodes => gateAnalyzer.completedEpisodes;

  Future<void> initialize() async {
    if (!_videoListenerAdded) {
      videoBenchmark.addListener(notifyListeners);
      _videoListenerAdded = true;
    }
    _models = await modelRepository.listModels();
    _activeModel = await modelRepository.getActiveModel();
    _activeProfile = null;
    if (_activeModel != null) {
      _activeProfile =
          await modelRepository.getActiveProfileForModel(_activeModel!.id);
      final restoration = await modelRepository.activateModel(_activeModel!.id);
      if (!restoration.success) _lastBannerMessage = restoration.error;
      _activeModel = await modelRepository.getActiveModel();
      _activeProfile = _activeModel == null
          ? null
          : await modelRepository.getActiveProfileForModel(_activeModel!.id);
      _models = await modelRepository.listModels();
    }
    _eventLoggingEnabled = await sessionRepository.isEventLoggingEnabled();
    _forbiddenMediaCount = await storage.countForbiddenMediaFiles();
    await sessionRepository.startNewSession(
      modelId: _activeModel?.id,
      profileId: _activeProfile?.id,
      profileName: _activeProfile?.profileName,
      sourceType: cameraSource.currentLens == CameraLensDirectionType.front
          ? 'front_camera'
          : 'rear_camera',
    );
    notifyListeners();
  }

  Future<void> startCameraPreview() async {
    try {
      if (videoBenchmark.running) {
        throw const ModelValidationException(
            'أوقف مقارنة الفيديو قبل تشغيل الكاميرا.');
      }
      _lastBannerMessage = null;
      await _cameraSub?.cancel();
      _cameraSub = cameraSource.observeImageFrames().listen(_onCameraFrame);
      benchmarkService.reset();
      await cameraSource.start(ownerTag: 'live_monitor_owner');
      notifyListeners();
    } catch (e) {
      _lastBannerMessage = e is SafeZoneException ? e.messageAr : e.toString();
      notifyListeners();
    }
  }

  Future<void> stopCameraPreview() async {
    try {
      await _cameraSub?.cancel();
      _cameraSub = null;
      _generation++;
      await _idle?.future;
      await cameraSource.stop(ownerTag: 'live_monitor_owner');
      await _flushGate();
      _latestDetections = [];
      _latestDecision = SafetyDecision(
          status: SafetyStatus.review,
          evidenceFrames: 0,
          reason: 'الكاميرا متوقفة.',
          timestampMs: DateTime.now().millisecondsSinceEpoch);
      notifyListeners();
    } catch (e) {
      _lastBannerMessage = e is SafeZoneException ? e.messageAr : e.toString();
      notifyListeners();
    }
  }

  Future<void> switchCameraLens() async {
    if (_cameraTransition) return;
    _cameraTransition = true;
    try {
      _generation++;
      await _idle?.future;
      _latestDetections = [];
      frameAspectRatio = null;
      _latestDecision = SafetyDecision(
          status: SafetyStatus.review,
          evidenceFrames: 0,
          reason: 'في انتظار دليل من الكاميرا الجديدة.',
          timestampMs: DateTime.now().millisecondsSinceEpoch);
      await _flushGate();
      await cameraSource.switchLens();
      notifyListeners();
    } catch (e) {
      _lastBannerMessage = e is SafeZoneException ? e.messageAr : e.toString();
      notifyListeners();
    } finally {
      _cameraTransition = false;
    }
  }

  Future<void> handleAppLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      await _cameraSub?.cancel();
      _cameraSub = null;
      _generation++;
      await _idle?.future;
      await _flushGate();
      _latestDetections = [];
      _latestDecision = SafetyDecision(
          status: SafetyStatus.review,
          evidenceFrames: 0,
          reason: 'المعاينة متوقفة مؤقتًا.',
          timestampMs: DateTime.now().millisecondsSinceEpoch);
      await cameraSource.onAppBackgrounded();
      await _cameraSub?.cancel();
      _cameraSub = null;
    } else if (state == AppLifecycleState.resumed) {
      await cameraSource.onAppResumed(ownerTag: 'live_monitor_owner');
      if (cameraSource.isRunning) {
        _cameraSub?.cancel();
        _cameraSub = cameraSource.observeImageFrames().listen(_onCameraFrame);
      }
    }
    notifyListeners();
  }

  void setFoldablePosture(FoldablePosture posture) {
    cameraSource.setFoldablePosture(posture);
    notifyListeners();
  }

  void setGateModeEnabled(bool enabled) {
    if (!enabled) unawaited(_flushGate());
    _gateModeEnabled = enabled;
    notifyListeners();
  }

  Future<void> _onCameraFrame(CameraImageFrame frame) async {
    if (_switching ||
        _cameraTransition ||
        !inferenceEngine.isReady ||
        _activeModel == null ||
        _activeProfile == null) {
      return;
    }
    if (_processing) {
      benchmarkService.recordFrameTelemetry(
          inferenceMs: 0,
          dropped: true,
          accelerator: inferenceEngine.activeAccelerator);
      return;
    }
    _processing = true;
    _idle = Completer<void>();
    final generation = _generation;
    final model = _activeModel!;
    final profile = _activeProfile!;
    try {
      final output = await inferenceEngine.inferFrame(
          frameNumber: frame.meta.frameNumber,
          timestampMs: frame.meta.timestampMs,
          sensorRotationDegrees: frame.meta.sensorRotationDegrees,
          isFrontMirrored: frame.meta.lens == CameraLensDirectionType.front,
          image: frame,
          contract:
              Map<String, dynamic>.from(model.metadata['contract'] as Map),
          confidenceThreshold: profile.confidenceThreshold,
          iouThreshold: profile.iouThreshold);
      if (generation != _generation || output.droppedByBackpressure) return;
      _latestDetections = output.detections;
      final quarterTurn = frame.meta.sensorRotationDegrees % 180 != 0;
      frameAspectRatio = quarterTurn
          ? frame.meta.height / frame.meta.width
          : frame.meta.width / frame.meta.height;
      if (inferenceEngine is LiteRtYoloInferenceEngine) {
        memoryMb = ((inferenceEngine as LiteRtYoloInferenceEngine)
                    .lastFrameTelemetry?['memory_mb'] as num?)
                ?.toDouble() ??
            0;
      }
      benchmarkService.recordFrameTelemetry(
          inferenceMs: output.inferenceMs,
          dropped: false,
          accelerator: output.acceleratorUsed);
      _latestDecision = safetyPolicy.decide(
          detections: output.detections,
          profile: profile,
          timestampMs: output.timestampMs);
      if (_gateModeEnabled) {
        await _recordEpisode(gateAnalyzer.consumeFrameDetections(
            detections: output.detections,
            profile: profile,
            timestampMs: output.timestampMs));
      } else {
        await sessionRepository.recordEvent(
            status: _latestDecision.status,
            modelId: model.id,
            modelLabel: _latestDecision.dominantLabel,
            confidence: _latestDecision.representativeConfidence,
            mode: 'live');
      }
      _lastBannerMessage = null;
    } catch (e) {
      _latestDetections = [];
      _lastBannerMessage = 'تعذر الاستدلال: $e';
      _latestDecision = SafetyDecision(
          status: SafetyStatus.review,
          evidenceFrames: 0,
          reason: _lastBannerMessage!,
          timestampMs: frame.meta.timestampMs);
    } finally {
      _processing = false;
      _idle?.complete();
      _idle = null;
      notifyListeners();
    }
  }

  Future<ModelEntry> importModel(
      {required String fileName,
      required Uint8List fileBytes,
      String? displayName,
      String? manifestJson}) async {
    final entry = await modelRepository.importModel(
        fileName: fileName,
        fileBytes: fileBytes,
        displayName: displayName,
        manifestJson: manifestJson);
    _models = await modelRepository.listModels();
    notifyListeners();
    return entry;
  }

  /// Imports and activates a model, rolling back automatically on failure.
  Future<ModelActivationResult> importAndActivateModel({
    required String fileName,
    required Uint8List fileBytes,
    String? displayName,
    String? manifestJson,
  }) async {
    final entry = await modelRepository.importModel(
      fileName: fileName,
      fileBytes: fileBytes,
      displayName: displayName,
      manifestJson: manifestJson,
    );
    final res =
        await _changeModel(() => modelRepository.activateModel(entry.id));
    _models = await modelRepository.listModels();
    _activeModel = await modelRepository.getActiveModel();
    _activeProfile = null;
    if (_activeModel != null) {
      _activeProfile =
          await modelRepository.getActiveProfileForModel(_activeModel!.id);
    }
    _lastBannerMessage = res.success
        ? 'تم استيراد وتفعيل النموذج (${entry.displayName}) بنجاح.'
        : 'فشل تفعيل النموذج: ${res.error}';
    notifyListeners();
    return res;
  }

  Future<ModelActivationResult> activateExistingModel(String modelId) async {
    final res =
        await _changeModel(() => modelRepository.activateModel(modelId));
    _models = await modelRepository.listModels();
    _activeModel = await modelRepository.getActiveModel();
    _activeProfile = null;
    if (_activeModel != null) {
      _activeProfile =
          await modelRepository.getActiveProfileForModel(_activeModel!.id);
    }
    _lastBannerMessage = res.success
        ? 'تم التبديل إلى النموذج النشط دون إعادة بناء APK.'
        : 'تعذر التفعيل: ${res.error}';
    notifyListeners();
    return res;
  }

  Future<ModelCheck> validateModel(String modelId) async {
    final check =
        await _changeModel(() => modelRepository.validateModel(modelId));
    _models = await modelRepository.listModels();
    _activeModel = await modelRepository.getActiveModel();
    _activeProfile = _activeModel == null
        ? null
        : await modelRepository.getActiveProfileForModel(_activeModel!.id);
    _lastBannerMessage = check.passed
        ? 'نجح الاستدلال الفعلي دون تغيير النموذج النشط.'
        : 'فشل الفحص: ${check.detail}';
    notifyListeners();
    return check;
  }

  Future<void> deleteModel(String modelId) async {
    if (videoBenchmark.running) {
      throw const ModelValidationException(
          'أوقف مقارنة الفيديو قبل حذف النموذج.');
    }
    await modelRepository.removeModel(modelId);
    _models = await modelRepository.listModels();
    notifyListeners();
  }

  Future<void> updateActiveProfile(ModelProfile updated) async {
    await modelRepository.saveProfile(updated);
    _activeProfile = updated;
    _lastBannerMessage = 'تم تحديث قواعد السلامة وعتبات الثقة.';
    notifyListeners();
  }

  Future<void> toggleEventLogging(bool enabled) async {
    await sessionRepository.setEventLoggingEnabled(enabled);
    _eventLoggingEnabled = enabled;
    notifyListeners();
  }

  Future<void> startNewLiveSessionOnly() async {
    await sessionRepository.startNewSession(
      modelId: _activeModel?.id,
      profileId: _activeProfile?.id,
      profileName: _activeProfile?.profileName,
    );
    gateAnalyzer.resetEpisodes();
    notifyListeners();
  }

  Future<void> purgePersistedHistory() async {
    await sessionRepository.purgePersistedHistory();
    notifyListeners();
  }

  Future<String> exportPersistedEventsCsv() async {
    final events = await sessionRepository.listPersistedEvents();
    return CsvExporter.exportDetectionEvents(events);
  }
}
