import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:personal_bahi_khata/data/encryption.dart';
import 'package:zstandard/zstandard.dart';

/// PBKE file codec.
///
/// The file is always:
/// `header + enc(compression(jsonData)) + footer`
///
/// For version `01_10`, the byte layout is:
///
/// 1. `header` (32 bytes)
///    - 11 bytes: `%PBKE%01_10`
///    - 4 bytes: big-endian unix timestamp in seconds
///    - 17 bytes: zero padding
/// 2. `content` (variable)
///    - AES-GCM ciphertext
/// 3. `footer` (48 bytes)
///    - 16 bytes: IV
///    - 32 bytes: key
///
/// The transformation pipeline for `01_10` is:
/// `json string -> utf8 bytes -> zstd compress -> AES-GCM encrypt`
///
/// The reader reverses the same pipeline:
/// `ciphertext -> AES-GCM decrypt -> zstd decompress -> utf8 decode -> json`
///
/// Legacy versions are intentionally isolated behind mode switches because
/// their header/footer sizes and payload transforms may differ.

final Zstandard _zstd = Zstandard();

enum PbkeFormatMode { legacy, v_01_10 }

class _PbkeFooter {
  const _PbkeFooter({
    required this.keyBytes,
    required this.ivBytes,
    required this.encryptedPayload,
  });

  final List<int> keyBytes;
  final List<int> ivBytes;
  final List<int> encryptedPayload;
}

class PbkeReadResult {
  const PbkeReadResult({
    required this.data,
    required this.lastDate,
    required this.version,
  });

  final Map<String, dynamic> data;
  final DateTime? lastDate;
  final String version;
}

class PbkeFile {
  static const String unsupportedFileMessage = "File is not-supported";
  static const String version = "01_10";
  static const String signature = "%PBKE%";
  static const String mimeType = "application/vnd.vins.bahi-khata";

  static const int _unixTimeLength = 4;
  static const int _previousHeaderSize = 23;
  static const int _currentHeaderSize = 32;
  static const int _previousPaddingLength =
      _previousHeaderSize - signature.length - _unixTimeLength;
  static const int _currentPaddingLength =
      _currentHeaderSize - signature.length - version.length - _unixTimeLength;

  static final List<int> _signatureBytes = utf8.encode(signature);
  static final List<int> _versionBytes = utf8.encode(version);

  static const int headerSize = _currentHeaderSize;

  static void _log(String message) {
    debugPrint("[PBKE] $message");
  }

  static String _previewBytes(List<int> bytes, {int count = 24}) {
    final preview = bytes.take(count).map((byte) {
      return byte.toRadixString(16).padLeft(2, '0');
    }).join(' ');
    return bytes.length > count ? "$preview ..." : preview;
  }

  static void validateHeaderConfig() {
    if (_previousHeaderSize >= 100 ||
        _currentHeaderSize >= 100 ||
        _previousPaddingLength < 0 ||
        _currentPaddingLength < 0) {
      throw const FormatException(unsupportedFileMessage);
    }
  }

  static List<int> _getUnixTime(DateTime? date) {
    if (date == null) {
      return <int>[0, 0, 0, 0];
    }

    final unixTime = date.millisecondsSinceEpoch ~/ 1000;
    return <int>[
      (unixTime >> 24) & 0xFF,
      (unixTime >> 16) & 0xFF,
      (unixTime >> 8) & 0xFF,
      unixTime & 0xFF,
    ];
  }

  static String _readSignature(List<int> fileBytes) {
    if (fileBytes.length < _signatureBytes.length) {
      throw const FormatException(unsupportedFileMessage);
    }
    return utf8.decode(fileBytes.sublist(0, _signatureBytes.length));
  }

  static bool _looksLikeVersionToken(String value) {
    return RegExp(r'^\d{2}[_\.]\d{2}$').hasMatch(value);
  }

  static void validateFileHeader(List<int> fileBytes) {
    validateHeaderConfig();
    final storedSignature = _readSignature(fileBytes);
    _log(
      "validateFileHeader length=${fileBytes.length} signature=$storedSignature",
    );
    if (storedSignature != signature) {
      throw const FormatException(unsupportedFileMessage);
    }
  }

  static PbkeFormatMode _readFormatMode(List<int> fileBytes) {
    final storedSignature = _readSignature(fileBytes);
    if (storedSignature != signature) {
      throw const FormatException(unsupportedFileMessage);
    }

    if (fileBytes.length < _signatureBytes.length + version.length) {
      return PbkeFormatMode.legacy;
    }

    final versionStart = _signatureBytes.length;
    final versionEnd = versionStart + _versionBytes.length;
    final versionToken = utf8.decode(
      fileBytes.sublist(versionStart, versionEnd),
      allowMalformed: true,
    );
    _log(
      "_readFormatMode versionToken=$versionToken headerPreview=${_previewBytes(fileBytes, count: headerSize)}",
    );

    if (versionToken == version) {
      return PbkeFormatMode.v_01_10;
    }
    if (_looksLikeVersionToken(versionToken)) {
      return PbkeFormatMode.legacy;
    }
    return PbkeFormatMode.legacy;
  }

  static PbkeFormatMode modeForVersion(String fileVersion) {
    switch (fileVersion) {
      case "":
        return PbkeFormatMode.legacy;
      case version:
        return PbkeFormatMode.v_01_10;
      default:
        throw const FormatException(unsupportedFileMessage);
    }
  }

  static int keyLengthForMode(PbkeFormatMode mode) {
    switch (mode) {
      case PbkeFormatMode.legacy:
        return 32;
      case PbkeFormatMode.v_01_10:
        return 32;
    }
  }

  static int ivLengthForMode(PbkeFormatMode mode) {
    switch (mode) {
      case PbkeFormatMode.legacy:
        return 12;
      case PbkeFormatMode.v_01_10:
        return 16;
    }
  }

  static int footerLengthForMode(PbkeFormatMode mode) {
    return keyLengthForMode(mode) + ivLengthForMode(mode);
  }

  static int headerSizeForMode(PbkeFormatMode mode) {
    switch (mode) {
      case PbkeFormatMode.legacy:
        return _previousHeaderSize;
      case PbkeFormatMode.v_01_10:
        return _currentHeaderSize;
    }
  }

  static int paddingLengthForMode(PbkeFormatMode mode) {
    switch (mode) {
      case PbkeFormatMode.legacy:
        return _previousPaddingLength;
      case PbkeFormatMode.v_01_10:
        return _currentPaddingLength;
    }
  }

  static String readFileVersion(List<int> fileBytes) {
    final resolvedVersion =
        _readFormatMode(fileBytes) == PbkeFormatMode.v_01_10 ? version : "";
    _log(
      "readFileVersion resolved=${resolvedVersion.isEmpty ? "<legacy>" : resolvedVersion}",
    );
    return resolvedVersion;
  }

  static DateTime? extractLastDate(List<int> fileBytes) {
    validateFileHeader(fileBytes);
    final mode = _readFormatMode(fileBytes);
    final currentHeaderSize = headerSizeForMode(mode);
    final footerLength = footerLengthForMode(mode);
    if (fileBytes.length <= currentHeaderSize + footerLength) {
      throw const FormatException(unsupportedFileMessage);
    }

    final dateStart =
        mode == PbkeFormatMode.legacy
            ? _signatureBytes.length
            : _signatureBytes.length + _versionBytes.length;
    final unixTimeBytes = fileBytes.sublist(
      dateStart,
      dateStart + _unixTimeLength,
    );
    if (unixTimeBytes.every((byte) => byte == 0)) {
      return null;
    }

    final unixTime =
        unixTimeBytes[0] << 24 |
        unixTimeBytes[1] << 16 |
        unixTimeBytes[2] << 8 |
        unixTimeBytes[3];
    final lastDate = DateTime.fromMillisecondsSinceEpoch(unixTime * 1000);
    _log("extractLastDate mode=$mode unix=$unixTime iso=$lastDate");
    return lastDate;
  }

  static _PbkeFooter _extractFooter(List<int> fileBytes) {
    validateFileHeader(fileBytes);
    final mode = _readFormatMode(fileBytes);
    final currentHeaderSize = headerSizeForMode(mode);
    final keyLength = keyLengthForMode(mode);
    final ivLength = ivLengthForMode(mode);
    final footerLength = footerLengthForMode(mode);
    if (fileBytes.length <= currentHeaderSize + footerLength) {
      throw const FormatException(unsupportedFileMessage);
    }

    final footerStart = fileBytes.length - footerLength;
    final encryptedPayload = fileBytes.sublist(currentHeaderSize, footerStart);
    final ivBytes = fileBytes.sublist(footerStart, footerStart + ivLength);
    final keyBytes = fileBytes.sublist(footerStart + ivLength, fileBytes.length);

    if (ivBytes.length != ivLength || keyBytes.length != keyLength) {
      throw const FormatException(unsupportedFileMessage);
    }

    _log(
      "_extractFooter mode=$mode headerSize=$currentHeaderSize payloadLength=${encryptedPayload.length} ivLength=${ivBytes.length} keyLength=${keyBytes.length} payloadPreview=${_previewBytes(encryptedPayload)}",
    );
    return _PbkeFooter(
      keyBytes: keyBytes,
      ivBytes: ivBytes,
      encryptedPayload: encryptedPayload,
    );
  }

  static List<int> extractEncryptedPayload(List<int> fileBytes) {
    return _extractFooter(fileBytes).encryptedPayload;
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static Future<List<int>> _compressJsonForMode(
    String jsonData,
    PbkeFormatMode mode,
  ) async {
    switch (mode) {
      case PbkeFormatMode.legacy:
      case PbkeFormatMode.v_01_10:
        final zstdCompressed = await _zstd.compress(utf8.encode(jsonData), 13);
        return List<int>.from(zstdCompressed?.toList() ?? <int>[]);
    }
  }

  static Future<List<int>> _decompressJsonForMode(
    List<int> compressedData,
    PbkeFormatMode mode,
  ) async {
    switch (mode) {
      case PbkeFormatMode.legacy:
      case PbkeFormatMode.v_01_10:
        final zstdDecompressed = await _zstd.decompress(
          Uint8List.fromList(compressedData),
        );
        return List<int>.from(zstdDecompressed ?? <int>[]);
    }
  }

  static List<int> buildFileHeader(
    DateTime? date, {
    String fileVersion = version,
  }) {
    validateHeaderConfig();
    final dateBytes = _getUnixTime(date);
    switch (fileVersion) {
      case "":
        return <int>[
          ..._signatureBytes,
          ...dateBytes,
          ...List<int>.filled(paddingLengthForMode(PbkeFormatMode.legacy), 0),
        ];
      case version:
        return <int>[
          ..._signatureBytes,
          ..._versionBytes,
          ...dateBytes,
          ...List<int>.filled(paddingLengthForMode(PbkeFormatMode.v_01_10), 0),
        ];
      default:
        throw const FormatException(unsupportedFileMessage);
    }
  }

  static Future<_PbkeFooter> _encryptCompressedData(
    List<int> compressedData,
    PbkeFormatMode mode,
  ) async {
    switch (mode) {
      case PbkeFormatMode.legacy:
      case PbkeFormatMode.v_01_10:
        final keyBytes = _randomBytes(keyLengthForMode(mode));
        final ivBytes = _randomBytes(ivLengthForMode(mode));
        final key = enc.Key(Uint8List.fromList(keyBytes));
        final iv = enc.IV(Uint8List.fromList(ivBytes));
        final encryptedPayload =
            enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm))
                .encryptBytes(compressedData, iv: iv)
                .bytes;
        return _PbkeFooter(
          keyBytes: keyBytes,
          ivBytes: ivBytes,
          encryptedPayload: encryptedPayload,
        );
    }
  }

  static Future<List<int>> compressAndEncryptJson(
    String jsonData, {
    String fileVersion = version,
  }) async {
    final mode = modeForVersion(fileVersion);
    final compressedData = await _compressJsonForMode(jsonData, mode);
    final footer = await _encryptCompressedData(compressedData, mode);
    _log(
      "compressAndEncryptJson mode=$mode compressedLength=${compressedData.length} encryptedLength=${footer.encryptedPayload.length} footerLength=${footer.ivBytes.length + footer.keyBytes.length}",
    );
    return <int>[
      ...footer.encryptedPayload,
      ...footer.ivBytes,
      ...footer.keyBytes,
    ];
  }

  static Future<Map<String, dynamic>> decryptAndDecompressJson(
    List<int> encryptedCompressedData, {
    required List<int> keyBytes,
    required List<int> ivBytes,
    String fileVersion = version,
  }) async {
    final mode = modeForVersion(fileVersion);
    _log(
      "decryptAndDecompressJson version=${fileVersion.isEmpty ? "<legacy>" : fileVersion} mode=$mode encryptedLength=${encryptedCompressedData.length} encryptedPreview=${_previewBytes(encryptedCompressedData)} ivLength=${ivBytes.length} keyLength=${keyBytes.length}",
    );

    late final List<int> decryptedData;
    try {
      decryptedData = await EncryptionAES.decryptAESGCM(
        encryptedCompressedData,
        keyBytes,
        ivBytes,
      );
      _log(
        "decryptAndDecompressJson decryptedLength=${decryptedData.length} decryptedPreview=${_previewBytes(decryptedData)}",
      );
    } catch (e, st) {
      _log("decryptAndDecompressJson decrypt failed: $e");
      debugPrintStack(
        label: "[PBKE] decryptAndDecompressJson decrypt stack",
        stackTrace: st,
      );
      rethrow;
    }

    late final List<int> decompressedData;
    try {
      decompressedData = await _decompressJsonForMode(decryptedData, mode);
      _log(
        "decryptAndDecompressJson decompressedLength=${decompressedData.length} decompressedPreview=${_previewBytes(decompressedData)}",
      );
    } catch (e, st) {
      _log(
        "decryptAndDecompressJson decompress failed for version=${fileVersion.isEmpty ? "<legacy>" : fileVersion}: $e",
      );
      debugPrintStack(
        label: "[PBKE] decryptAndDecompressJson decompress stack",
        stackTrace: st,
      );
      rethrow;
    }

    late final dynamic decodedJson;
    try {
      final jsonString = utf8.decode(decompressedData);
      _log(
        "decryptAndDecompressJson jsonPreview=${jsonString.length > 200 ? "${jsonString.substring(0, 200)}..." : jsonString}",
      );
      decodedJson = jsonDecode(jsonString);
    } catch (e, st) {
      _log("decryptAndDecompressJson json decode failed: $e");
      debugPrintStack(
        label: "[PBKE] decryptAndDecompressJson json stack",
        stackTrace: st,
      );
      rethrow;
    }

    if (decodedJson is! Map<String, dynamic>) {
      _log(
        "decryptAndDecompressJson decoded top-level type=${decodedJson.runtimeType}",
      );
      throw const FormatException(unsupportedFileMessage);
    }
    _log("decryptAndDecompressJson decoded keys=${decodedJson.keys.toList()}");
    return decodedJson;
  }

  static Future<PbkeReadResult?> readPbkeFile(String filePath) async {
    _log("readPbkeFile path=$filePath");
    final file = File(filePath);
    if (!await file.exists()) {
      _log("readPbkeFile file does not exist");
      return null;
    }

    final contents = await file.readAsBytes();
    _log(
      "readPbkeFile bytesRead=${contents.length} headerPreview=${_previewBytes(contents, count: headerSize)}",
    );
    if (contents.isEmpty) {
      _log("readPbkeFile empty file");
      return null;
    }

    try {
      final fileVersion = readFileVersion(contents);
      final lastDate = extractLastDate(contents);
      final footer = _extractFooter(contents);
      final decodedJson = await decryptAndDecompressJson(
        footer.encryptedPayload,
        keyBytes: footer.keyBytes,
        ivBytes: footer.ivBytes,
        fileVersion: fileVersion,
      );
      _log(
        "readPbkeFile success version=${fileVersion.isEmpty ? "<legacy>" : fileVersion} lastDate=$lastDate keys=${decodedJson.keys.toList()}",
      );
      return PbkeReadResult(
        data: decodedJson,
        lastDate: lastDate,
        version: fileVersion,
      );
    } catch (e, st) {
      _log("readPbkeFile failed path=$filePath error=$e");
      debugPrintStack(label: "[PBKE] readPbkeFile stack", stackTrace: st);
      rethrow;
    }
  }

  static Future<File> writePbkeFile(
    String filePath,
    String jsonData,
    DateTime? date, {
    String fileVersion = version,
  }) async {
    validateHeaderConfig();

    final encryptedCompressedBytes = await compressAndEncryptJson(
      jsonData,
      fileVersion: fileVersion,
    );
    final fileContent = <int>[
      ...buildFileHeader(date, fileVersion: fileVersion),
      ...encryptedCompressedBytes,
    ];

    return File(filePath).writeAsBytes(fileContent);
  }
}
