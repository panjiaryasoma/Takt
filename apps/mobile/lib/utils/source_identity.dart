import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class SourceIdentity {
  const SourceIdentity._();

  static String urlSourceId(String url) {
    final clean = url.trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(url, 'url', 'must not be empty');
    }
    return 'src-url-${sha256.convert(utf8.encode(clean))}';
  }

  static String pdfContentHash(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  static String pdfSourceId(Uint8List bytes) =>
      'src-pdf-${pdfContentHash(bytes)}';

  static String pdfDocumentId(String filename, Uint8List bytes) {
    final safeName =
        filename.trim().isEmpty ? 'document.pdf' : filename.trim();
    final digest = pdfContentHash(bytes);
    return 'pdf:$safeName:${digest.substring(0, 16)}';
  }
}
