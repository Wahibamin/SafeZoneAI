import 'dart:typed_data';
import 'model_entry.dart';

abstract class ModelRepository {
  Future<List<ModelEntry>> listModels();
  Future<ModelEntry?> getModelById(String id);
  Future<ModelEntry?> getActiveModel();
  Future<ModelProfile?> getActiveProfileForModel(String modelId);
  Future<List<ModelProfile>> listProfilesForModel(String modelId);
  Future<List<ModelCheck>> listChecksForModel(String modelId);

  /// Native smoke inference without changing the active model.
  Future<ModelCheck> validateModel(String modelId);

  /// Imports a .tflite file (and optional model.json manifest) into app-private storage
  /// and registers it as pending after actual tensor/metadata inspection.
  Future<ModelEntry> importModel({
    required String fileName,
    required Uint8List fileBytes,
    String? displayName,
    String? manifestJson,
  });

  /// Runs a smoke check and switches the active model.
  /// If validation or warmup inference fails, automatically rolls back to the prior active model.
  Future<ModelActivationResult> activateModel(String modelId);

  Future<void> saveProfile(ModelProfile profile);
  Future<void> removeModel(String modelId);
}
