import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../constants/app_constants.dart';
import 'migrations.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  Database? _db;
  String? _overridePath;

  DatabaseHelper._internal();

  void setOverridePathForTesting(String path) {
    _overridePath = path;
  }

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = _overridePath ??
        p.join(await getDatabasesPath(), AppConstants.dbFileName);

    return openDatabase(
      dbPath,
      version: AppConstants.dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await db.rawQuery('PRAGMA secure_delete = ON;');
      },
      onCreate: (db, version) async {
        final statements = DatabaseMigrations.statementsForUpgrade(0, version);
        for (final sql in statements) {
          await db.execute(sql);
        }
        await _seedDefaultSettings(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        final statements =
            DatabaseMigrations.statementsForUpgrade(oldVersion, newVersion);
        for (final sql in statements) {
          await db.execute(sql);
        }
      },
    );
  }

  Future<void> _seedDefaultSettings(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final defaults = <String, dynamic>{
      AppConstants.settingEventLoggingEnabled: false,
      AppConstants.settingActiveModelId: null,
      AppConstants.settingActiveProfileId: null,
      AppConstants.settingDefaultCameraLens: 'rear_camera',
      AppConstants.settingPreferredAccelerator: 'cpu',
      AppConstants.settingRetentionDays: 14,
    };

    for (final entry in defaults.entries) {
      await db.insert(
        'app_settings',
        {
          'key': entry.key,
          'value_json': jsonEncode(entry.value),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<T?> getSetting<T>(String key, {T? defaultValue}) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return defaultValue;
    final raw = rows.first['value_json'] as String?;
    if (raw == null) return defaultValue;
    final decoded = jsonDecode(raw);
    if (decoded == null) return defaultValue;
    return decoded as T;
  }

  Future<void> setSetting(String key, dynamic value) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'app_settings',
      {
        'key': key,
        'value_json': jsonEncode(value),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
