import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart';

/// Shared AES helpers used by the PBKE codec.
///
/// PBKE version `01_10` stores its bytes as:
/// `header + enc(zstd(jsonData)) + footer(iv + key)`
///
/// In that flow:
/// - `pbke_file.dart` owns the binary file layout
/// - this file owns key derivation and AES-GCM decryption helpers
///
/// The current `encryptAESGCM()` helper is intentionally left unchanged because
/// the caller may manage file footer fields itself. For PBKE reads, the
/// important mapping is:
///
/// `ciphertext + footer(key, iv) -> AES-GCM decrypt -> compressed bytes`
class EncryptionAES {
  static const String KEY = "viksviksviksvikspbkepbkepbkepbke";
  static const int KEY_LENGTH = EncryptionAES.KEY.length;
  static const int IV_LENGTH = 16;
  static const int SALT_LENGTH = 16;
  static const int TAG_LENGTH = 16;
  static const int KEY_ITERATIONS_COUNT = 10000;

  static Uint8List deriveKey(String key) {
    final saltBytes = enc.IV.fromSecureRandom(SALT_LENGTH).bytes;
    final pbkdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf.init(Pbkdf2Parameters(saltBytes, KEY_ITERATIONS_COUNT, KEY_LENGTH));
    return pbkdf.process(Uint8List.fromList(key.codeUnits));
  }

  static Future<List<int>> encryptAESGCM(List<int> plaintext) async {
    final key = enc.Key(deriveKey(KEY));
    final iv = enc.IV.fromSecureRandom(IV_LENGTH);

    try {
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      final encrypted = encrypter.encryptBytes(plaintext, iv: iv);
      return encrypted.bytes;
    } catch (e) {
      throw Exception("Encryption failed: $e");
    }
  }

  static Future<List<int>> decryptAESGCM(
    List<int> ciphertextBytes,
    List<int> keyBytes,
    List<int> ivBytes,
  ) async {
    if (keyBytes.length != KEY_LENGTH) {
      throw Exception(
        "Decryption failed: invalid key length ${keyBytes.length}",
      );
    }
    if (ivBytes.isEmpty) {
      throw Exception("Decryption failed: invalid iv length ${ivBytes.length}");
    }
    if (ciphertextBytes.isEmpty) {
      throw Exception("Data to decrypt is too small");
    }

    final key = enc.Key(Uint8List.fromList(keyBytes));
    final nonce = enc.IV(Uint8List.fromList(ivBytes));

    try {
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      return encrypter.decryptBytes(
        enc.Encrypted(Uint8List.fromList(ciphertextBytes)),
        iv: nonce,
      );
    } catch (e) {
      throw Exception("Decryption failed: $e");
    }
  }
}
