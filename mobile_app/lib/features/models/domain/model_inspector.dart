abstract class ModelInspector {
  Future<Map<String, dynamic>> inspect(String absoluteFilePath);
  Future<Map<String, dynamic>> smoke(String absoluteFilePath);
}
