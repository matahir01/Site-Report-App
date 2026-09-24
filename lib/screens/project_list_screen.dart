import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/project.dart';
import '../services/google_drive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_widgets.dart';
import 'project_dashboard_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  final _db = DatabaseHelper.instance;
  List<Project> _projects = [];
  final _nameController = TextEditingController();
  final _clientController = TextEditingController();
  final _locationController = TextEditingController();
  final _gpsController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientController.dispose();
    _locationController.dispose();
    _gpsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _db.getProjects();
    if (!mounted) return;
    setState(() {
      _projects = data;
      _loading = false;
    });
  }

  Future<void> _addProject() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final project = Project(
      id: const Uuid().v4(),
      name: name,
      client: _clientController.text.trim().isEmpty
          ? null
          : _clientController.text.trim(),
      siteLocation: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      gpsCoordinates: _gpsController.text.trim().isEmpty
          ? null
          : _gpsController.text.trim(),
      createdAt: DateTime.now(),
    );
    await _db.insertProject(project);
    _nameController.clear();
    _clientController.clear();
    _locationController.clear();
    _gpsController.clear();
    await _load();
  }

  Future<void> _deleteProject(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
        title: const Text('Delete project?'),
        content: const Text(
          'All sites, logs and expenses under this project will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete project'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteProject(id);
      await _load();
    }
  }

  Future<void> _showAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(ctx).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create project',
              style: Theme.of(ctx).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const Text(
              'Set up the project once, then add one or more construction sites.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Project name',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Client / Employer (optional)',
                prefixIcon: Icon(Icons.business_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Project location (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gpsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'GPS coordinates (optional)',
                hintText: '11.123456, 10.654321',
                prefixIcon: Icon(Icons.gps_fixed_rounded),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  if (_nameController.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  await _addProject();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create project'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Civil Site Manager'),
        actions: [
          IconButton(
            tooltip: 'Drive backup & restore',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const GoogleDriveBackupScreen(),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: BrandHeader(
                eyebrow: 'Field engineering workspace',
                title: 'Projects & Site Operations',
                subtitle: 'Daily records, resources, cost control and professional reporting in one place.',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_projects.length} ${_projects.length == 1 ? 'project' : 'projects'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              sliver: _loading
                  ? const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _projects.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(),
                    )
                  : SliverList.separated(
                      itemCount: _projects.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) => _projectCard(_projects[i]),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text(
          'New Project',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.navy.withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.domain_add_rounded,
                size: 38,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Start your first project',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a project, add its sites, then begin capturing daily engineering records.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.add),
              label: const Text('Create project'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectCard(Project project) {
    final client = project.client?.trim();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProjectDashboardScreen(project: project),
            ),
          );
          await _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.steel.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: AppColors.steel,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      client == null || client.isEmpty
                          ? 'No client specified'
                          : client,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    if (project.siteLocation?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        project.siteLocation!,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Created ${DateFormat.yMMMd().format(project.createdAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Project actions',
                onSelected: (value) {
                  if (value == 'delete') _deleteProject(project.id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: AppColors.danger),
                        SizedBox(width: 10),
                        Text('Delete project'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GoogleDriveBackupScreen extends StatefulWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  State<GoogleDriveBackupScreen> createState() =>
      _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState extends State<GoogleDriveBackupScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _backup() async {
    setState(() {
      _busy = true;
      _status = 'Connecting to Google Drive…';
    });
    try {
      final file = await GoogleDriveService.uploadBackup();
      setState(() => _status = 'Backup uploaded: ${file.name}');
    } catch (e) {
      setState(() => _status = 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _status = 'Fetching backups…';
    });
    try {
      final backups = await GoogleDriveService.listBackups();
      if (backups.isEmpty) {
        setState(() => _status = 'No Civil Site Manager backups were found.');
        return;
      }
      final chosen = await showDialog<drive.File>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Choose backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backups.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.cloud_done_outlined),
                title: Text(backups[i].name ?? 'Unnamed backup'),
                subtitle: Text(
                  backups[i].createdTime?.toLocal().toString() ?? '',
                ),
                onTap: () => Navigator.pop(ctx, backups[i]),
              ),
            ),
          ),
        ),
      );
      if (chosen != null) {
        setState(() => _status = 'Restoring database…');
        await GoogleDriveService.restoreFromBackup(chosen);
        setState(
          () => _status = 'Restore complete. Restart Civil Site Manager to reload the database.',
        );
      }
    } catch (e) {
      setState(() => _status = 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const BrandHeader(
            eyebrow: 'Data protection',
            title: 'Google Drive Backup',
            subtitle: 'Keep a private copy of your Civil Site Manager database in your Google Drive app-data storage.',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Database actions',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Backup creates a new cloud copy. Restore replaces the local database with the selected backup.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _backup,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Back up now'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore from backup'),
                  ),
                ],
              ),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceStrong,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _status!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
