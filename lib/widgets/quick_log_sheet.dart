import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../services/google_sheets_service.dart';
import '../services/image_compression_service.dart';
import '../services/photo_watermark_service.dart';

class QuickLogSheet extends StatefulWidget {
  final String siteId;
  final String siteName;
  const QuickLogSheet({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<QuickLogSheet> {
  final List<String> _photoPaths = [];
  String? _weather;
  int _crewCount = 0;
  final _noteController = TextEditingController();
  bool _saving = false;

  static const _weatherOptions = [
    ('Sunny', Icons.wb_sunny),
    ('Cloudy', Icons.cloud),
    ('Rainy', Icons.umbrella),
    ('Windy', Icons.air),
  ];

  Future<void> _snapPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
    );
    if (file == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final rawPath = p.join(appDir.path, 'photos', fileName);
    await Directory(p.join(appDir.path, 'photos')).create(recursive: true);

    // 1. Compress first
    final compressed = await ImageCompressionService.compressAndSave(
      sourcePath: file.path,
      destinationPath: rawPath,
    );

    // 2. Watermark after compression
    final watermarked = await PhotoWatermarkService.watermarkPhoto(
      imagePath: compressed.path,
      siteName: widget.siteName,
    );

    setState(() => _photoPaths.add(watermarked.path));
    HapticFeedback.lightImpact();
  }

  Future<Position?> _tryGetLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final position = await _tryGetLocation();

    final log = DailyLog(
      id: const Uuid().v4(),
      siteId: widget.siteId,
      date: DateTime.now(),
      weather: _weather,
      crewCount: _crewCount > 0 ? _crewCount : null,
      workCompleted: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      issues: null,
      photoPaths: _photoPaths,
      lat: position?.latitude,
      lng: position?.longitude,
    );
    await DatabaseHelper.instance.insertDailyLog(log);
    GoogleSheetsService.autoSyncSite(widget.siteId);

    HapticFeedback.lightImpact();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Quick Check-in',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                InkWell(
                  onTap: _snapPhoto,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_a_photo, size: 32),
                  ),
                ),
                ..._photoPaths.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(path),
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Weather', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _weatherOptions.map((w) {
              final (label, icon) = w;
              return ChoiceChip(
                label: Text(label),
                avatar: Icon(icon, size: 18),
                selected: _weather == label,
                onSelected: (_) =>
                    setState(() => _weather = _weather == label ? null : label),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Crew on site',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _crewCount > 0
                    ? () => setState(() => _crewCount--)
                    : null,
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '$_crewCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _crewCount++),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Check-in', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
