import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class Sha256Utils {
  Sha256Utils._();

  static String hashBytes(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  static Future<String> hashFile(File file) async {
    return (await sha256.bind(file.openRead()).first).toString();
  }

  /// Checks whether the byte buffer starts with a valid TFLite FlatBuffer magic 'TFL3' at offset 4..8.
  static bool hasValidTfliteMagicHeader(Uint8List bytes) {
    if (bytes.length < 32) return false;
    final magic = String.fromCharCodes(bytes.sublist(4, 8));
    return magic == 'TFL3';
  }

  /// Invalid fixture, solely for rejection tests; never a runnable model.
  static Uint8List buildInvalidTfliteFixture({String tag = 'invalid'}) {
    final tagBytes = tag.codeUnits;
    final buffer = Uint8List(64 + tagBytes.length);
    // Offset 0..3: root table offset
    buffer[0] = 0x10;
    buffer[1] = 0x00;
    buffer[2] = 0x00;
    buffer[3] = 0x00;
    // Offset 4..7: 'TFL3' magic identifier
    buffer[4] = 0x54; // 'T'
    buffer[5] = 0x46; // 'F'
    buffer[6] = 0x4C; // 'L'
    buffer[7] = 0x33; // '3'
    for (var i = 0; i < tagBytes.length; i++) {
      buffer[32 + i] = tagBytes[i];
    }
    return buffer;
  }
}
