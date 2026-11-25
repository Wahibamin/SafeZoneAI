import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../safety/domain/safety_decision.dart';
import '../domain/session_models.dart';
import '../domain/session_repository.dart';

class SqliteSessionRepository implements SessionRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  LiveSessionCounters _liveCounters = LiveSessionCounters(
    liveSessionId: 'live-init',
    startedAtUtc: DateTime.now().toUtc().toIso8601String(),
  );
  String? _persistedRunningSessionId;

  SqliteSessionRepository({required DatabaseHelper dbHelper})
      : _dbHelper = dbHelper;

  @override
  LiveSessionCounters get liveCounters => _liveCounters;

  @override
  Future<bool> isEventLoggingEnabled() async {
    final enabled = await _dbHelper.getSetting<bool>(
      AppConstants.settingEventLoggingEnabled,
      defaultValue: false,
    );
    return enabled ?? false;
  }

  @override
  Future<void> setEventLoggingEnabled(bool enabled) async {
    await _dbHelper.setSetting(
        AppConstants.settingEventLoggingEnabled, enabled);
    if (!enabled && _persistedRunningSessionId != null) {
      await closeCurrentSession();
    }
  }

  @override
  Future<LiveSessionCounters> startNewSession({
    String? modelId,
    String? profileId,
    String? profileName,
    String sourceType = 'rear_camera',
  }) async {
    // Close any prior persisted running session cleanly without deleting history
    await closeCurrentSession();

    final now = DateTime.now().toUtc().toIso8601String();
    final newId = 'ses-${_uuid.v4().substring(0, 8)}';
    _liveCounters = LiveSessionCounters(
      liveSessionId: newId,
      startedAtUtc: now,
      activeModelId: modelId,
      activeProfileName: profileName,
    );

    final loggingEnabled = await isEventLoggingEnabled();
    if (loggingEnabled) {
      final db = await _dbHelper.database;
      final session = MonitoringSession(
        id: newId,
        modelId: modelId,
        profileId: profileId,
        sourceType: sourceType,
        startedAt: now,
        state: 'running',
      );
      await db.insert('monitoring_sessions', session.toMap());
      _persistedRunningSessionId = newId;
    }

    return _liveCounters;
  }

  @override
  Future<void> recordEvent({
    required SafetyStatus status,
    String? modelId,
    String? modelLabel,
    double? confidence,
    int evidenceFrames = 1,
    int? durationMs,
    String mode = 'live',
  }) async {
    // 1. Always update in-memory live counters
    _liveCounters = _liveCounters.incrementForDecision(
      status,
      isGatePassage: mode == 'gate',
    );

    // 2. Write to SQLite ONLY if opt-in event logging is explicitly enabled
    final loggingEnabled = await isEventLoggingEnabled();
    if (!loggingEnabled) {
      return;
    }

    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();

    if (_persistedRunningSessionId == null) {
      final sessionId = _liveCounters.liveSessionId;
      final session = MonitoringSession(
        id: sessionId,
        modelId: modelId,
        profileId: null,
        sourceType: 'rear_camera',
        startedAt: _liveCounters.startedAtUtc,
        state: 'running',
      );
      await db.insert('monitoring_sessions', session.toMap());
      _persistedRunningSessionId = sessionId;
    }

    final event = DetectionEventRecord(
      id: 'evt-${_uuid.v4().substring(0, 8)}',
      sessionId: _persistedRunningSessionId!,
      modelId: modelId,
      occurredAt: now,
      safetyStatus: status.dbValue,
      modelLabel: modelLabel,
      confidence: confidence,
      evidenceFrames: evidenceFrames,
      durationMs: durationMs,
      mode: mode,
    );
    await db.insert('detection_events', event.toMap());
  }

  @override
  Future<void> closeCurrentSession() async {
    if (_persistedRunningSessionId == null) return;
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'monitoring_sessions',
      {
        'ended_at': now,
        'state': 'closed',
      },
      where: 'id = ?',
      whereArgs: [_persistedRunningSessionId],
    );
    _persistedRunningSessionId = null;
  }

  @override
  Future<List<MonitoringSession>> listPersistedSessions() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'monitoring_sessions',
      orderBy: 'started_at DESC',
    );
    return rows.map(MonitoringSession.fromMap).toList();
  }

  @override
  Future<List<DetectionEventRecord>> listPersistedEvents(
      {String? sessionId}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'detection_events',
      where: sessionId != null ? 'session_id = ?' : null,
      whereArgs: sessionId != null ? [sessionId] : null,
      orderBy: 'occurred_at DESC',
    );
    return rows.map(DetectionEventRecord.fromMap).toList();
  }

  @override
  Future<Map<String, int>> queryPersistedCountsByStatus(
      {String? sessionId}) async {
    final db = await _dbHelper.database;
    final sql = sessionId != null
        ? 'SELECT safety_status, COUNT(*) as cnt FROM detection_events WHERE session_id = ? GROUP BY safety_status'
        : 'SELECT safety_status, COUNT(*) as cnt FROM detection_events GROUP BY safety_status';
    final args = sessionId != null ? [sessionId] : const <Object?>[];
    final rows = await db.rawQuery(sql, args);

    final counts = <String, int>{
      'compliant': 0,
      'violation': 0,
      'review': 0,
    };
    for (final r in rows) {
      final status = r['safety_status'] as String;
      final cnt = (r['cnt'] as num).toInt();
      counts[status] = cnt;
    }
    return counts;
  }

  @override
  Future<void> purgePersistedHistory({int? olderThanDays}) async {
    final db = await _dbHelper.database;
    if (olderThanDays == null) {
      await db.delete('detection_events');
      await db.delete('monitoring_sessions');
      await db.delete('performance_samples');
      _persistedRunningSessionId = null;
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
    } else {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(Duration(days: olderThanDays))
          .toIso8601String();
      await db.delete(
        'detection_events',
        where: 'occurred_at < ?',
        whereArgs: [cutoff],
      );
      await db.delete(
        'monitoring_sessions',
        where: 'started_at < ? AND state != ?',
        whereArgs: [cutoff, 'running'],
      );
    }
  }
}
