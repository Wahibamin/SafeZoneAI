import '../../safety/domain/safety_decision.dart';

class LiveSessionCounters {
  final String liveSessionId;
  final String startedAtUtc;
  final String? activeModelId;
  final String? activeProfileName;
  final int compliantCount;
  final int violationCount;
  final int reviewCount;
  final int evaluatedFramesCount;
  final int gatePassagesCount;

  const LiveSessionCounters({
    required this.liveSessionId,
    required this.startedAtUtc,
    this.activeModelId,
    this.activeProfileName,
    this.compliantCount = 0,
    this.violationCount = 0,
    this.reviewCount = 0,
    this.evaluatedFramesCount = 0,
    this.gatePassagesCount = 0,
  });

  int get totalEvents => compliantCount + violationCount + reviewCount;

  double get complianceRatePercent {
    final decisive = compliantCount + violationCount;
    if (decisive == 0) return 0.0;
    return (compliantCount * 100.0) / decisive;
  }

  LiveSessionCounters incrementForDecision(
    SafetyStatus status, {
    bool isGatePassage = false,
  }) {
    return LiveSessionCounters(
      liveSessionId: liveSessionId,
      startedAtUtc: startedAtUtc,
      activeModelId: activeModelId,
      activeProfileName: activeProfileName,
      compliantCount: status == SafetyStatus.compliant
          ? compliantCount + 1
          : compliantCount,
      violationCount: status == SafetyStatus.violation
          ? violationCount + 1
          : violationCount,
      reviewCount:
          status == SafetyStatus.review ? reviewCount + 1 : reviewCount,
      evaluatedFramesCount:
          isGatePassage ? evaluatedFramesCount : evaluatedFramesCount + 1,
      gatePassagesCount:
          isGatePassage ? gatePassagesCount + 1 : gatePassagesCount,
    );
  }
}

class MonitoringSession {
  final String id;
  final String? modelId;
  final String? profileId;
  final String sourceType; // 'front_camera' | 'rear_camera' | 'video_test'
  final String startedAt;
  final String? endedAt;
  final String state; // 'running' | 'closed' | 'interrupted'

  const MonitoringSession({
    required this.id,
    this.modelId,
    this.profileId,
    required this.sourceType,
    required this.startedAt,
    this.endedAt,
    required this.state,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'model_id': modelId,
      'profile_id': profileId,
      'source_type': sourceType,
      'started_at': startedAt,
      'ended_at': endedAt,
      'state': state,
    };
  }

  factory MonitoringSession.fromMap(Map<String, dynamic> map) {
    return MonitoringSession(
      id: map['id'] as String,
      modelId: map['model_id'] as String?,
      profileId: map['profile_id'] as String?,
      sourceType: map['source_type'] as String,
      startedAt: map['started_at'] as String,
      endedAt: map['ended_at'] as String?,
      state: map['state'] as String,
    );
  }
}

class DetectionEventRecord {
  final String id;
  final String sessionId;
  final String? modelId;
  final String occurredAt;
  final String safetyStatus; // 'compliant' | 'violation' | 'review'
  final String? modelLabel;
  final double? confidence;
  final int evidenceFrames;
  final int? durationMs;
  final String mode; // 'live' | 'gate'

  const DetectionEventRecord({
    required this.id,
    required this.sessionId,
    this.modelId,
    required this.occurredAt,
    required this.safetyStatus,
    this.modelLabel,
    this.confidence,
    required this.evidenceFrames,
    this.durationMs,
    required this.mode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'model_id': modelId,
      'occurred_at': occurredAt,
      'safety_status': safetyStatus,
      'model_label': modelLabel,
      'confidence': confidence,
      'evidence_frames': evidenceFrames,
      'duration_ms': durationMs,
      'mode': mode,
    };
  }

  factory DetectionEventRecord.fromMap(Map<String, dynamic> map) {
    return DetectionEventRecord(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      modelId: map['model_id'] as String?,
      occurredAt: map['occurred_at'] as String,
      safetyStatus: map['safety_status'] as String,
      modelLabel: map['model_label'] as String?,
      confidence: (map['confidence'] as num?)?.toDouble(),
      evidenceFrames: map['evidence_frames'] as int,
      durationMs: map['duration_ms'] as int?,
      mode: map['mode'] as String,
    );
  }
}
