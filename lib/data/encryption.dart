import 'package:cryptography/cryptography.dart';

/// Shared AES helpers used by the PBKE codec.
///
/// PBKE version `01_10` stores its bytes as:
/// `header + enc(zstd(jsonData)) + footer(iv + key)`
///
/// In that flow:
/// - `pbke_file.dart` owns the binary file layout
/// - this file owns AES-GCM encryption and decryption helpers
///
/// The encrypted PBKE payload is `ciphertext + 16-byte GCM tag`; the IV and key
/// are stored separately in the file footer.
class EncryptionAES {
  static const int keyLength = 32;
  static const int tagLength = 16;

  static AesGcm _aesGcmForNonceLength(int nonceLength) {
    return AesGcm.with256bits(nonceLength: nonceLength);
  }

  static void _validateInputs(
    List<int> payloadBytes,
    List<int> keyBytes,
    List<int> ivBytes, {
    required bool payloadIncludesTag,
  }) {
    if (keyBytes.length != keyLength) {
      throw Exception(
        "Decryption failed: invalid key length ${keyBytes.length}",
      );
    }
    if (ivBytes.isEmpty) {
      throw Exception("Decryption failed: invalid iv length ${ivBytes.length}");
    }
    if (payloadIncludesTag && payloadBytes.length <= tagLength) {
      throw Exception("Data to decrypt is too small");
    }
    if (!payloadIncludesTag && payloadBytes.isEmpty) {
      throw Exception("Data to encrypt is too small");
    }
  }

  static Future<List<int>> encryptAESGCM(
    List<int> plaintextBytes, {
    required List<int> keyBytes,
    required List<int> ivBytes,
  }) async {
    _validateInputs(
      plaintextBytes,
      keyBytes,
      ivBytes,
      payloadIncludesTag: false,
    );

    try {
      final algorithm = _aesGcmForNonceLength(ivBytes.length);
      final secretBox = await algorithm.encrypt(
        plaintextBytes,
        secretKey: SecretKey(keyBytes),
        nonce: ivBytes,
      );
      return secretBox.concatenation(nonce: false);
    } catch (e) {
      throw Exception("Encryption failed: $e");
    }
  }

  static Future<List<int>> decryptAESGCM(
    List<int> ciphertextBytes,
    List<int> keyBytes,
    List<int> ivBytes,
  ) async {
    _validateInputs(
      ciphertextBytes,
      keyBytes,
      ivBytes,
      payloadIncludesTag: true,
    );

    try {
      final algorithm = _aesGcmForNonceLength(ivBytes.length);
      final tagStart = ciphertextBytes.length - tagLength;
      final secretBox = SecretBox(
        ciphertextBytes.sublist(0, tagStart),
        nonce: ivBytes,
        mac: Mac(ciphertextBytes.sublist(tagStart)),
      );
      return algorithm.decrypt(secretBox, secretKey: SecretKey(keyBytes));
    } catch (e) {
      throw Exception("Decryption failed: $e");
    }
  }
}
