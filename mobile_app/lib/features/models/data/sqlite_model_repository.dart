import 'dart:convert';
import 'dart:io';
import '../domain/model_inspector.dart';
import '../domain/model_contract_validator.dart';
import 'native_model_runtime.dart';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/storage/app_private_storage.dart';
import '../../../core/utils/sha256_utils.dart';
import '../../detection/domain/inference_engine.dart';
import '../domain/model_entry.dart';
import '../domain/model_repository.dart';

class SqliteModelRepository implements ModelRepository {
  final DatabaseHelper _dbHelper;
  final AppPrivateStorage _storage;
  final InferenceEngine _inferenceEngine;
  final Uuid _uuid = const Uuid();
  final ModelInspector _inspector;
  Future<void> _queue = Future<void>.value();

  SqliteModelRepository({
    required DatabaseHelper dbHelper,
    required AppPrivateStorage storage,
    required InferenceEngine inferenceEngine,
    ModelInspector? inspector,
  })  : _dbHelper = dbHelper,
        _storage = storage,
        _inferenceEngine = inferenceEngine,
        _inspector = inspector ?? NativeModelRuntime();

  @override
  Future<List<ModelEntry>> listModels() async {
    final db = await _dbHelper.database;
    final rows = await db.query('models', orderBy: 'imported_at DESC');
    return rows.map(ModelEntry.fromMap).toList();
  }

  @override
  Future<ModelEntry?> getModelById(String id) async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('models', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return ModelEntry.fromMap(rows.first);
  }

  @override
  Future<ModelEntry?> getActiveModel() async {
    final activeId =
        await _dbHelper.getSetting<String?>(AppConstants.settingActiveModelId);
    if (activeId == null || activeId.isEmpty) return null;
    return getModelById(activeId);
  }

  @override
  Future<ModelProfile?> getActiveProfileForModel(String modelId) async {
    final profiles = await listProfilesForModel(modelId);
    if (profiles.isEmpty) return null;
    final preferredId = await _dbHelper
        .getSetting<String?>(AppConstants.settingActiveProfileId);
    if (preferredId != null) {
      for (final p in profiles) {
        if (p.id == preferredId) return p;
      }
    }
    return profiles.first;
  }

  @override
  Future<List<ModelProfile>> listProfilesForModel(String modelId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'model_profiles',
      where: 'model_id = ?',
      whereArgs: [modelId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ModelProfile.fromMap).toList();
  }

  @override
  Future<List<ModelCheck>> listChecksForModel(String modelId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'model_checks',
      where: 'model_id = ?',
      whereArgs: [modelId],
      orderBy: 'tested_at DESC',
    );
    return rows.map(ModelCheck.fromMap).toList();
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<ModelEntry> importModel(
          {required String fileName,
          required Uint8List fileBytes,
          String? displayName,
          String? manifestJson}) =>
      _exclusive(() async {
        if (!fileName.toLowerCase().endsWith('.tflite') ||
            !Sha256Utils.hasValidTfliteMagicHeader(fileBytes)) {
          throw const ModelValidationException(
              'الملف ليس TFLite؛ الامتداد والترويسة لا يكفيان لإثبات صلاحيته.');
        }
        final manifest = ModelContractValidator.manifest(manifestJson);
        final digest = Sha256Utils.hashBytes(fileBytes);
        final db = await _dbHelper.database;
        if ((await db.query('models', where: 'sha256 = ?', whereArgs: [digest]))
            .isNotEmpty) {
          throw const ModelValidationException(
              'هذا النموذج مستورد مسبقًا بنفس بصمة SHA-256.');
        }
        final id = 'mdl-${_uuid.v4()}';
        try {
          final relative = await _storage.saveModelWeights(
              modelId: id, bytes: fileBytes, manifestJsonContent: manifestJson);
          final file = await _storage.resolveRelativeModelPath(relative);
          if (await Sha256Utils.hashFile(file) != digest) {
            throw const ModelValidationException(
                'فشل التحقق من النسخة الخاصة.');
          }
          final actual = await _inspector.inspect(file.path);
          final contract = ModelContractValidator.validate(
              actual: actual, manifest: manifest, digest: digest);
          final input = contract['input'] as Map;
          final name = displayName?.trim().isNotEmpty == true
              ? displayName!.trim()
              : (manifest['display_name'] as String? ?? fileName);
          final now = DateTime.now().toUtc().toIso8601String();
          final entry = ModelEntry(
              id: id,
              displayName: name,
              filePath: relative,
              sha256: digest,
              family: contract['family'] as String?,
              inputWidth: input['width'] as int,
              inputHeight: input['height'] as int,
              inputLayout: input['layout'] as String,
              tensorDtype: input['dtype'] as String,
              labels: Map<String, String>.from(contract['labels'] as Map),
              metadata: {
                'inspection_version': 1,
                'manifest': manifest,
                'contract': contract,
                'file_name': fileName,
                'size_bytes': fileBytes.length
              },
              importedAt: now);
          final profile = ModelProfile(
              id: 'prf-${_uuid.v4()}',
              modelId: id,
              profileName: 'قواعد $name',
              classMapping:
                  Map<String, String>.from(contract['mapping'] as Map),
              createdAt: now);
          await db.transaction((txn) async {
            await txn.insert('models', entry.toMap());
            await txn.insert('model_profiles', profile.toMap());
          });
          return entry;
        } catch (_) {
          await _storage.deleteModelDirectory(id);
          rethrow;
        }
      });

  Future<File> _verify(ModelEntry model) async {
    final file = await _storage.resolveRelativeModelPath(model.filePath);
    if (!await file.exists() ||
        await Sha256Utils.hashFile(file) != model.sha256) {
      throw const ModelValidationException(
          'ملف النموذج مفقود أو تغيرت بصمته منذ الاستيراد.');
    }
    final actual = await _inspector.inspect(file.path);
    ModelContractValidator.validate(
        actual: actual,
        manifest: Map<String, dynamic>.from(
            (model.metadata['manifest'] ?? model.metadata) as Map),
        digest: model.sha256);
    return file;
  }

  Future<void> _settings(
      DatabaseExecutor db, String? modelId, String? profileId) async {
    for (final pair in {
      AppConstants.settingActiveModelId: modelId,
      AppConstants.settingActiveProfileId: profileId
    }.entries) {
      await db.insert(
          'app_settings',
          {
            'key': pair.key,
            'value_json': jsonEncode(pair.value),
            'updated_at': DateTime.now().toUtc().toIso8601String()
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _record(ModelEntry model,
      {required bool passed,
      Map<String, dynamic>? evidence,
      String? error}) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert(
          'model_checks',
          ModelCheck(
                  id: 'chk-${_uuid.v4()}',
                  modelId: model.id,
                  testedAt: now,
                  passed: passed,
                  device: evidence?['device'] as String?,
                  runtimeName: evidence?['runtime'] as String? ??
                      _inferenceEngine.runtimeName,
                  inferenceMs: (evidence?['inference_ms'] as num?)?.toDouble(),
                  detail: passed ? jsonEncode(evidence) : error)
              .toMap());
      await txn.update(
          'models',
          {
            'validation_state': passed ? 'valid' : 'invalid',
            'error_message': error,
            'last_validated_at': now
          },
          where: 'id = ?',
          whereArgs: [model.id]);
    });
  }

  @override
  Future<ModelCheck> validateModel(String modelId) => _exclusive(() async {
        final model = await getModelById(modelId);
        if (model == null) {
          throw const ModelValidationException('النموذج غير موجود.');
        }
        try {
          final file = await _verify(model);
          final evidence = await _inspector.smoke(file.path);
          if (evidence['passed'] != true || evidence['inference_ms'] is! num) {
            throw const ModelValidationException(
                'لم ينفذ المحرك استدلالًا ناجحًا.');
          }
          await _record(model, passed: true, evidence: evidence);
        } catch (e) {
          await _record(model, passed: false, error: e.toString());
          if (_inferenceEngine.activeModelId == modelId) {
            await _inferenceEngine.dispose();
            final db = await _dbHelper.database;
            await db.transaction((txn) => _settings(txn, null, null));
          }
        }
        return (await listChecksForModel(modelId)).first;
      });

  @override
  Future<ModelActivationResult> activateModel(String modelId) =>
      _exclusive(() async {
        final target = await getModelById(modelId);
        final previous = await getActiveModel();
        final previousProfile = await _dbHelper
            .getSetting<String?>(AppConstants.settingActiveProfileId);
        if (target == null) {
          return ModelActivationResult(
              success: false,
              modelId: _inferenceEngine.activeModelId,
              runtime: _inferenceEngine.runtimeName,
              error: 'النموذج غير موجود.',
              rolledBack: false,
              previousModelId: previous?.id);
        }
        try {
          final file = await _verify(target);
          final ms = await _inferenceEngine.switchModel(
              modelId: target.id,
              absoluteFilePath: file.path,
              inputWidth: target.inputWidth,
              inputHeight: target.inputHeight,
              labels: target.labels);
          if (!ms.isFinite ||
              ms < 0 ||
              _inferenceEngine.activeModelId != target.id) {
            throw const ModelValidationException('دليل التفعيل غير صالح.');
          }
          final evidence = _inferenceEngine.lastSmokeEvidence;
          if (evidence == null ||
              evidence['passed'] != true ||
              evidence['device'] is! String ||
              evidence['runtime'] is! String) {
            throw const ModelValidationException(
                'لا يوجد دليل تشغيل أصلي مرتبط بالجهاز.');
          }
          final profiles = await listProfilesForModel(target.id);
          final db = await _dbHelper.database;
          await db.transaction((txn) async {
            final now = DateTime.now().toUtc().toIso8601String();
            await txn.insert(
                'model_checks',
                ModelCheck(
                        id: 'chk-${_uuid.v4()}',
                        modelId: target.id,
                        testedAt: now,
                        passed: true,
                        device: evidence['device'] as String?,
                        runtimeName: _inferenceEngine.runtimeName,
                        inferenceMs: ms,
                        detail: jsonEncode(evidence))
                    .toMap());
            await txn.update(
                'models',
                {
                  'validation_state': 'valid',
                  'error_message': null,
                  'last_validated_at': now
                },
                where: 'id = ?',
                whereArgs: [target.id]);
            await _settings(
                txn, target.id, profiles.isEmpty ? null : profiles.first.id);
          });
          return ModelActivationResult(
              success: true,
              modelId: target.id,
              runtime: _inferenceEngine.runtimeName,
              rolledBack: false,
              previousModelId: previous?.id,
              warmupInferenceMs: ms);
        } catch (e) {
          var error = e.toString();
          var rolledBack = false;
          if (previous != null && previous.id != target.id) {
            try {
              if (!_inferenceEngine.isReady ||
                  _inferenceEngine.activeModelId != previous.id) {
                final file = await _verify(previous);
                await _inferenceEngine.switchModel(
                    modelId: previous.id,
                    absoluteFilePath: file.path,
                    inputWidth: previous.inputWidth,
                    inputHeight: previous.inputHeight,
                    labels: previous.labels);
              }
              final db = await _dbHelper.database;
              await db.transaction(
                  (txn) => _settings(txn, previous.id, previousProfile));
              rolledBack = true;
            } catch (rollbackError) {
              error += '\nفشل استرجاع النموذج السابق: $rollbackError';
            }
          }
          if (!rolledBack) {
            try {
              await _inferenceEngine.dispose();
            } catch (_) {}
            final db = await _dbHelper.database;
            await db.transaction((txn) => _settings(txn, null, null));
          }
          await _record(target, passed: false, error: error);
          return ModelActivationResult(
              success: false,
              modelId: rolledBack ? previous?.id : null,
              runtime: _inferenceEngine.runtimeName,
              error: error,
              rolledBack: rolledBack,
              previousModelId: previous?.id);
        }
      });

  @override
  Future<void> saveProfile(ModelProfile profile) => _exclusive(() async {
        final db = await _dbHelper.database;
        final active = await getActiveModel();
        await db.transaction((txn) async {
          await txn.insert('model_profiles', profile.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace);
          if (active?.id == profile.modelId) {
            await _settings(txn, active!.id, profile.id);
          }
        });
      });
  @override
  Future<void> removeModel(String modelId) => _exclusive(() async {
        if ((await getActiveModel())?.id == modelId) {
          throw const ModelValidationException(
              'لا يمكن حذف النموذج النشط؛ فعّل نموذجًا آخر أولًا.');
        }
        final db = await _dbHelper.database;
        await db.delete('models', where: 'id = ?', whereArgs: [modelId]);
        await _storage.deleteModelDirectory(modelId);
      });
}
