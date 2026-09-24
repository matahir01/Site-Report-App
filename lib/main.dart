import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/project_list_screen.dart';
import 'services/google_drive_service.dart';
import 'services/google_sheets_service.dart';
import 'services/offline_queue_service.dart';
import 'services/sync_engine.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await OfflineQueueService.instance.init();
  GoogleDriveService.registerQueueHandler();
  GoogleSheetsService.registerQueueHandler();
  await SyncEngine.instance.init();
  unawaited(SyncEngine.instance.runSync());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SyncStatusProvider()),
        ChangeNotifierProvider.value(value: SyncEngine.instance),
      ],
      child: const CivilSiteManagerApp(),
    ),
  );
}

class CivilSiteManagerApp extends StatelessWidget {
  const CivilSiteManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Civil Site Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const ProjectListScreen(),
    );
  }
}
