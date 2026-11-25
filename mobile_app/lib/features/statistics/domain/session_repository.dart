import '../../safety/domain/safety_decision.dart';
import 'session_models.dart';

abstract class SessionRepository {
  LiveSessionCounters get liveCounters;
  Future<bool> isEventLoggingEnabled();
  Future<void> setEventLoggingEnabled(bool enabled);

  /// Starts a new live in-memory session WITHOUT deleting persisted SQLite history (T18).
  /// If opt-in event logging is enabled, also opens a new row in `monitoring_sessions`.
  Future<LiveSessionCounters> startNewSession({
    String? modelId,
    String? profileId,
    String? profileName,
    String sourceType = 'rear_camera',
  });

  /// Updates in-memory live counters, and writes to `detection_events` ONLY if opt-in logging is enabled (T17).
  Future<void> recordEvent({
    required SafetyStatus status,
    String? modelId,
    String? modelLabel,
    double? confidence,
    int evidenceFrames = 1,
    int? durationMs,
    String mode = 'live',
  });

  Future<void> closeCurrentSession();
  Future<List<MonitoringSession>> listPersistedSessions();
  Future<List<DetectionEventRecord>> listPersistedEvents({String? sessionId});
  Future<Map<String, int>> queryPersistedCountsByStatus({String? sessionId});

  /// Explicitly deletes persisted historical records from SQLite (independent from resetting live view).
  Future<void> purgePersistedHistory({int? olderThanDays});
}
