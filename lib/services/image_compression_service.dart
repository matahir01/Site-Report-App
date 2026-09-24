import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Compresses photos before they are saved to local storage.
/// Reduces storage bloat and speeds up PDF report generation.
class ImageCompressionService {
  static const int _targetQuality = 70;
  static const int _maxWidth = 1920;
  static const int _maxHeight = 1080;

  static Future<File> compressAndSave({
    required String sourcePath,
    required String destinationPath,
  }) async {
    final result = await FlutterImageCompress.compressWithFile(
      sourcePath,
      quality: _targetQuality,
      minWidth: _maxWidth,
      minHeight: _maxHeight,
    );

    if (result == null) {
      throw Exception('Image compression failed for $sourcePath');
    }

    final file = File(destinationPath);
    await file.writeAsBytes(result, flush: true);
    return file;
  }
}
