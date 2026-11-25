import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages app-private storage for external model files:
/// files/models/<model-id>/weights.tflite
/// files/models/<model-id>/model.json
/// Strictly enforces ADR-003 & ADR-006: no photos, videos, or frames are ever written here.
class AppPrivateStorage {
  final Directory? _overrideBaseDir;

  AppPrivateStorage({Directory? overrideBaseDir})
      : _overrideBaseDir = overrideBaseDir;

  Future<Directory> getBaseDirectory() async {
    if (_overrideBaseDir != null) {
      if (!await _overrideBaseDir.exists()) {
        await _overrideBaseDir.create(recursive: true);
      }
      return _overrideBaseDir;
    }
    return getApplicationSupportDirectory();
  }

  Future<Directory> getModelsRootDirectory() async {
    final base = await getBaseDirectory();
    final modelsDir = Directory(p.join(base.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  Future<Directory> getModelDirectory(String modelId) async {
    _validateModelId(modelId);
    final root = await getModelsRootDirectory();
    final dir = Directory(p.join(root.path, modelId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Stores model weights inside files/models/<model-id>/weights.tflite and returns its relative path.
  Future<String> saveModelWeights({
    required String modelId,
    required Uint8List bytes,
    String? manifestJsonContent,
  }) async {
    final modelDir = await getModelDirectory(modelId);
    final weightsFile = File(p.join(modelDir.path, 'weights.tflite'));
    await weightsFile.writeAsBytes(bytes, flush: true);

    if (manifestJsonContent != null && manifestJsonContent.trim().isNotEmpty) {
      final manifestFile = File(p.join(modelDir.path, 'model.json'));
      await manifestFile.writeAsString(manifestJsonContent, flush: true);
    }

    return p.join('models', modelId, 'weights.tflite');
  }

  Future<File> resolveRelativeModelPath(String relativePath) async {
    final base = await getBaseDirectory();
    final target = p.normalize(p.join(base.path, relativePath));
    if (p.isAbsolute(relativePath) ||
        !p.isWithin(p.join(base.path, 'models'), target)) {
      throw ArgumentError(
          'Model path must stay inside private models directory');
    }
    return File(target);
  }

  Future<void> deleteModelDirectory(String modelId) async {
    _validateModelId(modelId);
    final root = await getModelsRootDirectory();
    final dir = Directory(p.join(root.path, modelId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  void _validateModelId(String modelId) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(modelId)) {
      throw ArgumentError('Invalid model ID');
    }
  }

  /// Privacy audit: verifies zero image/video media files exist inside app-private storage.
  Future<int> countForbiddenMediaFiles() async {
    final base = await getBaseDirectory();
    if (!await base.exists()) return 0;
    const forbiddenExts = {
      '.jpg',
      '.jpeg',
      '.png',
      '.mp4',
      '.avi',
      '.mkv',
      '.webp'
    };
    var count = 0;
    await for (final entity in base.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (forbiddenExts.contains(ext)) {
          count++;
        }
      }
    }
    return count;
  }
}
