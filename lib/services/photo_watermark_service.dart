import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Stamps GPS coordinates, site name, and date/time onto a photo.
/// If watermarking fails for any reason, returns the original file.
class PhotoWatermarkService {
  static Future<File> watermarkPhoto({
    required String imagePath,
    required String siteName,
  }) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return File(imagePath);

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
      } catch (_) {
        // GPS unavailable
      }

      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final gpsStr = position != null
          ? 'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}'
          : 'GPS: Unavailable';

      final lines = [siteName, '$dateStr | $timeStr', gpsStr];
      final barHeight = 28 * lines.length + 16;
      final yStart = image.height - barHeight;

      // Draw semi-transparent bar directly on image (bar area only — fast)
      for (int y = yStart; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          image.setPixel(
            x,
            y,
            img.ColorRgba8(
              (pixel.r * 0.3).toInt(),
              (pixel.g * 0.3).toInt(),
              (pixel.b * 0.3).toInt(),
              200,
            ),
          );
        }
      }

      // Draw text if font is available (image >=4.1.0 may not ship fonts)
      try {
        final font = img.arial14;
        for (int i = 0; i < lines.length; i++) {
          img.drawString(
            image,
            lines[i],
            font: font,
            x: 16,
            y: yStart + 8 + (i * 24),
            color: img.ColorRgba8(255, 255, 255, 255),
          );
        }
      } catch (_) {
        // Font unavailable — bar-only watermark is still valid
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'wm_${now.millisecondsSinceEpoch}.png';
      final outPath = p.join(dir.path, fileName);
      final file = File(outPath);
      await file.writeAsBytes(img.encodePng(image));
      return file;
    } catch (e) {
      return File(imagePath);
    }
  }
}
