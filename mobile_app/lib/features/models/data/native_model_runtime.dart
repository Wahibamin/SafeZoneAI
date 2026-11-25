import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/model_inspector.dart';

class NativeModelRuntime implements ModelInspector {
  static const channel = MethodChannel('com.safezone.ai.mobile/native_runtime');
  Future<Map<String, dynamic>> invoke(String method, String path) async {
    final value =
        await channel.invokeMethod<Object?>(method, {'filePath': path});
    return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> inspect(String absoluteFilePath) =>
      invoke('inspectModel', absoluteFilePath);
  @override
  Future<Map<String, dynamic>> smoke(String absoluteFilePath) =>
      invoke('smokeModel', absoluteFilePath);
}
