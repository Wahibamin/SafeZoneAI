import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/database/database_helper.dart';
import 'package:safezone_mobile/features/safety/domain/safety_decision.dart';
import 'package:safezone_mobile/features/statistics/data/sqlite_session_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late SqliteSessionRepository sessionRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('safezone_p6_test_');
    dbHelper = DatabaseHelper.instance;
    dbHelper.setOverridePathForTesting('${tempDir.path}/safezone_mobile.db');
    sessionRepo = SqliteSessionRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group(
      'Phase 06 Privacy, Opt-In Logging & Session Reset Tests (T16, T17, T18)',
      () {
    test(
        'T17 & T18: Event logging defaults OFF; starting new live session preserves history',
        () async {
      expect(await sessionRepo.isEventLoggingEnabled(), isFalse);

      await sessionRepo.startNewSession();
      await sessionRepo.recordEvent(
        status: SafetyStatus.compliant,
        modelLabel: 'with_mask',
        confidence: 0.95,
      );

      // In-memory counter increments, but SQLite table remains empty while logging is OFF
      expect(sessionRepo.liveCounters.compliantCount, 1);
      expect((await sessionRepo.listPersistedEvents()).isEmpty, isTrue);

      // Enable opt-in logging
      await sessionRepo.setEventLoggingEnabled(true);
      await sessionRepo.startNewSession();
      await sessionRepo.recordEvent(
        status: SafetyStatus.violation,
        modelLabel: 'without_mask',
        confidence: 0.89,
      );

      final savedBeforeReset = await sessionRepo.listPersistedEvents();
      expect(savedBeforeReset.length, 1);

      // Start new live session -> live counters reset to 0, persisted history stays intact!
      await sessionRepo.startNewSession();
      expect(sessionRepo.liveCounters.totalEvents, 0);
      expect((await sessionRepo.listPersistedEvents()).length, 1);
    });
    test('purging history preserves settings and allows continued logging',
        () async {
      await sessionRepo.setEventLoggingEnabled(true);
      await sessionRepo.startNewSession();
      await sessionRepo.recordEvent(status: SafetyStatus.review);
      expect(await sessionRepo.listPersistedEvents(), hasLength(1));
      final db = await dbHelper.database;
      expect((await db.rawQuery('PRAGMA secure_delete')).first.values.first, 1);
      await sessionRepo.purgePersistedHistory();
      expect(await sessionRepo.listPersistedEvents(), isEmpty);
      expect(await sessionRepo.listPersistedSessions(), isEmpty);
      expect(await sessionRepo.isEventLoggingEnabled(), isTrue);
      await sessionRepo.recordEvent(status: SafetyStatus.compliant);
      expect(await sessionRepo.listPersistedEvents(), hasLength(1));
    });
  });
}
