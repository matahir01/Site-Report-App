import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../services/pdf_report_service.dart';
import '../services/excel_export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_widgets.dart';
import 'site_detail_screen.dart';

class ProjectDashboardScreen extends StatefulWidget {
  final Project project;
  const ProjectDashboardScreen({super.key, required this.project});

  @override
  State<ProjectDashboardScreen> createState() => _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState extends State<ProjectDashboardScreen> {
  final _db = DatabaseHelper.instance;
  List<Site> _sites = [];
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  bool _generatingPdf = false;
  bool _generatingExcel = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _db.getSitesForProject(widget.project.id);
    if (!mounted) return;
    setState(() {
      _sites = data;
      _loading = false;
    });
  }

  Future<void> _exportProjectPdf() async {
    if (_sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one site before exporting a project report.',
          ),
        ),
      );
      return;
    }
    setState(() => _generatingPdf = true);
    try {
      final logsBySite = <String, List<DailyLog>>{};
      final expensesBySite = <String, List<Expense>>{};
      for (final site in _sites) {
        logsBySite[site.id] = await _db.getLogsForSite(site.id);
        expensesBySite[site.id] = await _db.getExpensesForSite(site.id);
      }
      final file = await PdfReportService.generateProjectReport(
        project: widget.project,
        sites: _sites,
        logsBySite: logsBySite,
        expensesBySite: expensesBySite,
      );
      if (mounted)
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: '${widget.project.name} project report',
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _exportProjectExcel() async {
    if (_sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one site before exporting a project workbook.',
          ),
        ),
      );
      return;
    }
    setState(() => _generatingExcel = true);
    try {
      final logsBySite = <String, List<DailyLog>>{};
      final materialsBySite = <String, List<MaterialItem>>{};
      final expensesBySite = <String, List<Expense>>{};
      for (final site in _sites) {
        logsBySite[site.id] = await _db.getLogsForSite(site.id);
        materialsBySite[site.id] = await _db.getMaterialsForSite(site.id);
        expensesBySite[site.id] = await _db.getExpensesForSite(site.id);
      }
      final file = await ExcelExportService.generateProjectWorkbook(
        project: widget.project,
        sites: _sites,
        logsBySite: logsBySite,
        materialsBySite: materialsBySite,
        expensesBySite: expensesBySite,
      );
      if (mounted)
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: '${widget.project.name} project export',
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate Excel file: $e')),
        );
    } finally {
      if (mounted) setState(() => _generatingExcel = false);
    }
  }

  Future<void> _addSite() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await _db.insertSite(
      Site(
        id: const Uuid().v4(),
        projectId: widget.project.id,
        name: name,
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        createdAt: DateTime.now(),
      ),
    );
    _nameController.clear();
    _addressController.clear();
    await _load();
  }

  Future<void> _deleteSite(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
        title: const Text('Delete site?'),
        content: const Text(
          'All daily logs and expenses for this site will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete site'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteSite(id);
      await _load();
    }
  }

  Future<void> _showAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
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
              'Add construction site',
              style: Theme.of(ctx).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const Text(
              'A site contains its own daily logs, resources, expenses and reports.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Site name',
                prefixIcon: Icon(Icons.location_city_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Location / address (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  if (_nameController.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  await _addSite();
                },
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add site'),
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
      appBar: AppBar(title: const Text('Project Workspace')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: BrandHeader(
                eyebrow: widget.project.client ?? 'Civil Site Manager',
                title: widget.project.name,
                subtitle:
                    '${_sites.length} active ${_sites.length == 1 ? 'site' : 'sites'} • Created ${DateFormat.yMMMd().format(widget.project.createdAt)}',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _generatingPdf ? null : _exportProjectPdf,
                        icon: _generatingPdf
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF Report'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _generatingExcel
                            ? null
                            : _exportProjectExcel,
                        icon: _generatingExcel
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.table_view_outlined),
                        label: const Text('Excel Export'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              sliver: SliverToBoxAdapter(
                child: SectionTitle(
                  title: 'Construction Sites',
                  subtitle: _sites.isEmpty
                      ? 'No sites have been added yet.'
                      : 'Open a site to manage daily field operations.',
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_sites.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _emptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                sliver: SliverList.separated(
                  itemCount: _sites.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => _siteCard(_sites[i]),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text(
          'Add Site',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_city_outlined,
              size: 52,
              color: AppColors.steel,
            ),
            const SizedBox(height: 14),
            Text(
              'Add the first site',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            const Text(
              'Each site gets its own logs, resources, cost ledger, analytics and reports.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add site'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _siteCard(Site site) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SiteDetailScreen(site: site, project: widget.project),
            ),
          );
          await _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.engineering_rounded,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      site.address?.trim().isNotEmpty == true
                          ? site.address!
                          : 'Location not specified',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Added ${DateFormat.yMMMd().format(site.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') _deleteSite(site.id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: AppColors.danger),
                        SizedBox(width: 10),
                        Text('Delete site'),
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
