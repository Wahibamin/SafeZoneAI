import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/constants/app_constants.dart';
import 'package:safezone_mobile/core/database/migrations.dart';

void main() {
  group('Phase 00 & 01 Foundation Tests (T01-T04)', () {
    test('T01: Verify package contract and database version constants', () {
      expect(AppConstants.appSlug, 'safezone_mobile');
      expect(AppConstants.appId, 'com.safezone.ai.mobile');
      expect(AppConstants.dbFileName, 'safezone_mobile.db');
      expect(AppConstants.dbVersion, 3);
    });

    test('T01: Verify SQLite migration scripts cover all 7 required tables',
        () {
      final allSql = DatabaseMigrations.statementsForUpgrade(0, 3).join('\n');
      expect(allSql.contains('CREATE TABLE IF NOT EXISTS models'), isTrue);
      expect(
          allSql.contains('CREATE TABLE IF NOT EXISTS model_profiles'), isTrue);
      expect(
          allSql.contains('CREATE TABLE IF NOT EXISTS app_settings'), isTrue);
      expect(
          allSql.contains('CREATE TABLE IF NOT EXISTS model_checks'), isTrue);
      expect(allSql.contains('CREATE TABLE IF NOT EXISTS monitoring_sessions'),
          isTrue);
      expect(allSql.contains('CREATE TABLE IF NOT EXISTS detection_events'),
          isTrue);
      expect(allSql.contains('CREATE TABLE IF NOT EXISTS performance_samples'),
          isTrue);
    });
  });
}
