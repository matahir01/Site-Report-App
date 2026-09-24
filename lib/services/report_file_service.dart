import 'dart:io';

import 'package:flutter/services.dart';

class ReportFileResult {
  final String location;
  final bool opened;

  const ReportFileResult({required this.location, required this.opened});
}

class ReportFileService {
  static const MethodChannel _channel = MethodChannel(
    'com.mat.civilsitemanager/reports',
  );

  static Future<ReportFileResult?> savePdfToDownloadsAndOpen(File file) async {
    if (!Platform.isAndroid) return null;

    final response = await _channel.invokeMapMethod<String, dynamic>(
      'saveAndOpen',
      {
        'sourcePath': file.path,
        'fileName': file.uri.pathSegments.last,
        'mimeType': 'application/pdf',
      },
    );
    if (response == null) {
      throw const FileSystemException('Android did not return a saved report.');
    }
    return ReportFileResult(
      location: response['location'] as String? ?? 'Downloads',
      opened: response['opened'] as bool? ?? false,
    );
  }
}
