import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../services/excel_export_service.dart';
import '../utils/currency_formatter.dart';
import 'analytics_screen.dart';
import 'daily_log_detail_screen.dart';
import 'date_range_analytics_screen.dart';
import 'monthly_matrix_screen.dart';

class ReportHubScreen extends StatefulWidget {
  final Project project;
  final Site site;

  const ReportHubScreen({super.key, required this.project, required this.site});

  @override
  State<ReportHubScreen> createState() => _ReportHubScreenState();
}

class _ReportHubScreenState extends State<ReportHubScreen> {
  final _db = DatabaseHelper.instance;
  List<DailyLog> _logs = [];
  List<Expense> _expenses = [];
  List<MaterialItem> _materials = [];
  bool _loading = true;
  bool _exportingExcel = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _db.getLogsForSite(widget.site.id),
      _db.getExpensesForSite(widget.site.id),
      _db.getMaterialsForSite(widget.site.id),
    ]);
    if (!mounted) return;
    setState(() {
      _logs = results[0] as List<DailyLog>;
      _expenses = results[1] as List<Expense>;
      _materials = results[2] as List<MaterialItem>;
      _loading = false;
    });
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _chooseDailyReport() async {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log daily progress before generating a DPR.'),
        ),
      );
      return;
    }
    final log = await showModalBottomSheet<DailyLog>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Select DPR date',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final log in _logs)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(DateFormat.yMMMMEEEEd().format(log.date)),
                subtitle: Text(
                  log.workCompleted?.trim().isNotEmpty == true
                      ? log.workCompleted!.trim()
                      : 'No work activity summary',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, log),
              ),
          ],
        ),
      ),
    );
    if (log != null && mounted) {
      _open(DailyLogDetailScreen(log: log, site: widget.site));
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exportingExcel = true);
    try {
      final file = await ExcelExportService.generateSiteWorkbook(
        project: widget.project,
        site: widget.site,
        logs: _logs,
        materials: _materials,
        expenses: _expenses,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '${widget.site.name} construction management workbook',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel export failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold<double>(
      0,
      (sum, expense) => sum + expense.amount,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Report Hub — ${widget.site.name}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(Icons.assessment_outlined, size: 38),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.project.name,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${_logs.length} daily reports · ${_expenses.length} expense items · ${CurrencyFormatter.format(total)}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ReportAction(
                  title: 'Executive visual dashboard',
                  subtitle:
                      'KPIs, category donut, monthly spend and category trends',
                  icon: Icons.dashboard_outlined,
                  onTap: () => _open(
                    AnalyticsScreen(
                      siteId: widget.site.id,
                      siteName: widget.site.name,
                    ),
                  ),
                ),
                _ReportAction(
                  title: 'Daily Site Progress Report (PDF)',
                  subtitle: 'Select a date, preview the daily record and share the SWAS DPR',
                  icon: Icons.picture_as_pdf_outlined,
                  onTap: _chooseDailyReport,
                ),
                _ReportAction(
                  title: 'Custom date-range analytics',
                  subtitle: 'Filter by dates, categories, description or unit; export details',
                  icon: Icons.filter_alt_outlined,
                  onTap: () => _open(
                    DateRangeAnalyticsScreen(
                      siteId: widget.site.id,
                      siteName: widget.site.name,
                    ),
                  ),
                ),
                _ReportAction(
                  title: 'Monthly summary matrix',
                  subtitle: 'Live category-by-month pivot with category and monthly totals',
                  icon: Icons.pivot_table_chart_outlined,
                  onTap: () => _open(
                    MonthlyMatrixScreen(
                      siteId: widget.site.id,
                      siteName: widget.site.name,
                    ),
                  ),
                ),
                _ReportAction(
                  title: 'Complete Excel workbook',
                  subtitle: 'Export and share the audit workbook to WhatsApp, email or storage',
                  icon: Icons.table_view_outlined,
                  busy: _exportingExcel,
                  onTap: _exportExcel,
                ),
              ],
            ),
    );
  }
}

class _ReportAction extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  const _ReportAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: busy
          ? const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 30),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: busy ? null : onTap,
    ),
  );
}
