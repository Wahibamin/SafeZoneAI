import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safezone_mobile/core/constants/app_constants.dart';
import 'package:safezone_mobile/core/database/database_helper.dart';
import 'package:safezone_mobile/core/errors/app_exceptions.dart';
import 'package:safezone_mobile/core/storage/app_private_storage.dart';
import 'package:safezone_mobile/core/utils/sha256_utils.dart';
import 'package:safezone_mobile/features/detection/data/litert_yolo_inference_engine.dart';
import 'package:safezone_mobile/features/models/data/native_model_runtime.dart';
import 'package:safezone_mobile/features/models/data/sqlite_model_repository.dart';
import 'package:safezone_mobile/features/models/domain/model_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// These are rejection/persistence tests, never evidence of runnable TFLite inference.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  final db = DatabaseHelper.instance;
  late AppPrivateStorage storage;
  late LiteRtYoloInferenceEngine engine;
  late SqliteModelRepository repo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('safezone_p02_');
    db.setOverridePathForTesting('${dir.path}/registry.db');
    storage = AppPrivateStorage(overrideBaseDir: dir);
    engine = LiteRtYoloInferenceEngine();
    repo = SqliteModelRepository(
        dbHelper: db, storage: storage, inferenceEngine: engine);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeModelRuntime.channel, (call) async {
      if (call.method == 'closeModels') return null;
      throw PlatformException(
          code: 'INVALID_MODEL', message: 'Invalid FlatBuffer fixture');
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeModelRuntime.channel, null);
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<ModelEntry> seedInvalidRegistry(String id) async {
    final bytes = Sha256Utils.buildInvalidTfliteFixture(tag: id);
    final path = await storage.saveModelWeights(modelId: id, bytes: bytes);
    final entry = ModelEntry(
        id: id,
        displayName: id,
        filePath: path,
        sha256: Sha256Utils.hashBytes(bytes),
        inputWidth: 640,
        inputHeight: 640,
        inputLayout: 'NHWC',
        tensorDtype: 'float32',
        labels: const {'0': 'unverified'},
        importedAt: DateTime.now().toUtc().toIso8601String());
    await (await db.database).insert('models', entry.toMap());
    return entry;
  }

  test('non-TFLite and wrong extension are rejected without registration',
      () async {
    for (final name in ['bad.tflite', 'bad.pt']) {
      await expectLater(
          repo.importModel(
              fileName: name, fileBytes: Uint8List.fromList([1, 2, 3])),
          throwsA(isA<ModelValidationException>()));
    }
    expect(await repo.listModels(), isEmpty);
  });
  test('TFL3-only fixture cannot pass import; staged directory is cleaned',
      () async {
    await expectLater(
        repo.importModel(
            fileName: 'fake.tflite',
            fileBytes: Sha256Utils.buildInvalidTfliteFixture()),
        throwsA(isA<PlatformException>()));
    expect(await repo.listModels(), isEmpty);
    expect(await (await storage.getModelsRootDirectory()).list().toList(),
        isEmpty);
  });
  test('duplicate fingerprint rejected even when file name changes', () async {
    final entry = await seedInvalidRegistry('legacy');
    final bytes = await (await storage.resolveRelativeModelPath(entry.filePath))
        .readAsBytes();
    await expectLater(
        repo.importModel(fileName: 'renamed.tflite', fileBytes: bytes),
        throwsA(isA<ModelValidationException>()));
    expect(await repo.listModels(), hasLength(1));
  });
  test(
      'invalid legacy activation fails, records failure and clears stale active ID',
      () async {
    final entry = await seedInvalidRegistry('legacy');
    await db.setSetting(AppConstants.settingActiveModelId, entry.id);
    final result = await repo.activateModel(entry.id);
    expect(result.success, isFalse);
    expect(result.rolledBack, isFalse);
    expect(await repo.getActiveModel(), isNull);
    expect(engine.isReady, isFalse);
    expect((await repo.listChecksForModel(entry.id)).single.passed, isFalse);
    expect((await repo.getModelById(entry.id))!.isValid, isFalse);
  });
  test('failed independent smoke check never creates an active model',
      () async {
    final entry = await seedInvalidRegistry('invalid');
    expect((await repo.validateModel(entry.id)).passed, isFalse);
    expect(await repo.getActiveModel(), isNull);
  });
  test('changed bytes rejected by SHA-256 before native loading', () async {
    final entry = await seedInvalidRegistry('tampered');
    await (await storage.resolveRelativeModelPath(entry.filePath))
        .writeAsString('changed');
    final result = await repo.activateModel(entry.id);
    expect(result.success, isFalse);
    expect(result.error, contains('بصمته'));
  });
  test('missing file and nonexistent registry ID fail safely', () async {
    final entry = await seedInvalidRegistry('missing');
    await (await storage.resolveRelativeModelPath(entry.filePath)).delete();
    expect((await repo.activateModel(entry.id)).success, isFalse);
    expect((await repo.activateModel('unknown')).rolledBack, isFalse);
  });
  test(
      'registry/active selection survives SQLite close; this does not prove native restoration',
      () async {
    final entry = await seedInvalidRegistry('persist');
    await db.setSetting(AppConstants.settingActiveModelId, entry.id);
    await db.close();
    expect((await repo.getActiveModel())?.id, entry.id);
    expect((await repo.listModels()).single.sha256, entry.sha256);
    expect((await repo.activateModel(entry.id)).success, isFalse);
  });
  test('active deletion is blocked and inactive removal cascades checks',
      () async {
    final entry = await seedInvalidRegistry('delete');
    await db.setSetting(AppConstants.settingActiveModelId, entry.id);
    await expectLater(
        repo.removeModel(entry.id), throwsA(isA<ModelValidationException>()));
    await db.setSetting(AppConstants.settingActiveModelId, null);
    await repo.validateModel(entry.id);
    await repo.removeModel(entry.id);
    expect(await repo.getModelById(entry.id), isNull);
    expect(await repo.listChecksForModel(entry.id), isEmpty);
    expect(await (await storage.getModelsRootDirectory()).list().toList(),
        isEmpty);
  });
  test(
      'concurrent invalid activations serialize and do not leave a stale selection',
      () async {
    final a = await seedInvalidRegistry('a');
    final b = await seedInvalidRegistry('b');
    final results =
        await Future.wait([repo.activateModel(a.id), repo.activateModel(b.id)]);
    expect(results.every((r) => !r.success), isTrue);
    expect(await repo.getActiveModel(), isNull);
  });
  test('private storage rejects traversal and unsafe model IDs', () async {
    await expectLater(storage.resolveRelativeModelPath('../outside.tflite'),
        throwsArgumentError);
    await expectLater(
        storage.deleteModelDirectory('../outside'), throwsArgumentError);
    await expectLater(storage.getModelDirectory('a/b'), throwsArgumentError);
  });
}
