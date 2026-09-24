import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/site.dart';
import '../models/project.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../services/pdf_report_service.dart';
import '../services/excel_export_service.dart';
import '../utils/currency_formatter.dart';
import 'add_daily_log_screen.dart';
import 'add_expense_screen.dart';
import 'attendance_screen.dart';
import 'cash_float_screen.dart';
import 'google_sheets_sync_screen.dart';
import 'material_equipment_log_screen.dart';
import 'daily_log_detail_screen.dart';
import 'daily_log_list_screen.dart';
import 'report_hub_screen.dart';
import '../widgets/quick_expense_sheet.dart';
import '../widgets/quick_log_sheet.dart';

class SiteDetailScreen extends StatefulWidget {
  final Site site;
  final Project project;
  const SiteDetailScreen({
    super.key,
    required this.site,
    required this.project,
  });

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<DailyLog> _logs = [];
  List<Expense> _expenses = [];
  List<MaterialItem> _materials = [];
  double _totalSpend = 0.0;
  double _totalFloat = 0.0;
  double _currentBalance = 0.0;
  double _todayExpenses = 0.0;
  bool _hasTodayFloat = false;
  bool _generatingPdf = false;
  bool _generatingExcel = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await _db.getLogsForSite(widget.site.id);
    final expenses = await _db.getExpensesForSite(widget.site.id);
    final materials = await _db.getMaterialsForSite(widget.site.id);
    final spend = expenses.fold<double>(0.0, (s, e) => s + e.amount);
    final float = await _db.getTotalFloatReceived(widget.site.id);

    // Live reconciliation: always reconcile TODAY's opening + float
    // against TODAY's *current* expense total, not the frozen snapshot
    // saved the last time the Cash Float screen was opened — so adding a
    // Quick Expense immediately moves this balance, without needing to
    // revisit and re-save Cash Float.
    final today = DateTime.now();
    final todayIso = today.toIso8601String().split('T').first;
    final todayFloat = await _db.getCashFloatBySiteAndDate(
      widget.site.id,
      todayIso,
    );
    final todayExpenses = await _db.getTotalExpensesForSiteAndDate(
      widget.site.id,
      todayIso,
    );
    final lastFloat = await _db.getLatestCashFloat(widget.site.id);

    final opening =
        todayFloat?.openingBalance ?? lastFloat?.expectedClosingBalance ?? 0.0;
    final floatReceivedToday = todayFloat?.floatReceived ?? 0.0;

    setState(() {
      _logs = logs;
      _expenses = expenses;
      _materials = materials;
      _totalSpend = spend;
      _totalFloat = float;
      _todayExpenses = todayExpenses;
      _hasTodayFloat = todayFloat != null;
      _currentBalance = opening + floatReceivedToday - todayExpenses;
    });
  }

  Future<void> _exportPdf() async {
    setState(() => _generatingPdf = true);
    try {
      final file = await PdfReportService.generateSiteReport(
        project: widget.project,
        site: widget.site,
        logs: _logs,
        expenses: _expenses,
      );
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: '${widget.site.name} report',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _generatingExcel = true);
    try {
      final file = await ExcelExportService.generateSiteWorkbook(
        project: widget.project,
        site: widget.site,
        logs: _logs,
        materials: _materials,
        expenses: _expenses,
      );
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: '${widget.site.name} export',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate Excel file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingExcel = false);
    }
  }

  Future<void> _confirmDelete(String title, VoidCallback onConfirmed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $title?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirmed();
  }

  void _navigate(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.site.name),
          actions: [
            IconButton(
              icon: _generatingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf),
              tooltip: 'Export site report',
              onPressed: _generatingPdf ? null : _exportPdf,
            ),
            IconButton(
              icon: _generatingExcel
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.table_chart),
              tooltip: 'Export site report (.xlsx)',
              onPressed: _generatingExcel ? null : _exportExcel,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Daily Logs', icon: Icon(Icons.description)),
              Tab(text: 'Expenses', icon: Icon(Icons.attach_money)),
            ],
          ),
        ),
        body: TabBarView(children: [_buildDailyLogsTab(), _buildExpensesTab()]),
        floatingActionButton: Builder(
          builder: (ctx) {
            return GestureDetector(
              onLongPress: () async {
                final currentTab = DefaultTabController.of(ctx).index;
                if (currentTab == 0) {
                  await Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => AddDailyLogScreen(
                        siteId: widget.site.id,
                        siteName: widget.site.name,
                      ),
                    ),
                  );
                } else {
                  await Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => AddExpenseScreen(siteId: widget.site.id),
                    ),
                  );
                }
                _load();
              },
              child: FloatingActionButton.extended(
                onPressed: () async {
                  final currentTab = DefaultTabController.of(ctx).index;
                  final saved = await showModalBottomSheet<bool>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => currentTab == 0
                        ? QuickLogSheet(
                            siteId: widget.site.id,
                            siteName: widget.site.name,
                          )
                        : QuickExpenseSheet(siteId: widget.site.id),
                  );
                  if (saved == true) _load();
                },
                icon: const Icon(Icons.flash_on),
                label: const Text('Quick Add'),
                tooltip: 'Long-press for full form',
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDailyLogsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 16),
          _buildQuickActions(),
          const SizedBox(height: 16),
          _buildRecentLogs(),
          const SizedBox(height: 16),
          const Text(
            'All Daily Logs',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _logs.isEmpty
              ? const Center(child: Text('No daily logs yet.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _logs.length,
                  itemBuilder: (ctx, i) {
                    final log = _logs[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(DateFormat.yMMMd().format(log.date)),
                            const SizedBox(width: 8),
                            _SyncBadge(isSynced: log.isSynced),
                          ],
                        ),
                        subtitle: Text(
                          [
                            if (log.weather != null) 'Weather: ${log.weather}',
                            if (log.crewCount != null) 'Crew: ${log.crewCount}',
                            if (log.workCompleted != null) log.workCompleted!,
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (log.photoPaths.isNotEmpty)
                              Icon(
                                Icons.photo,
                                color: Colors.grey[600],
                                size: 18,
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  _confirmDelete('this log', () async {
                                    await _db.deleteDailyLog(log.id);
                                    _load();
                                  }),
                            ),
                          ],
                        ),
                        onTap: () => _navigate(
                          DailyLogDetailScreen(log: log, site: widget.site),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildExpensesTab() {
    return _expenses.isEmpty
        ? const Center(child: Text('No expenses yet.'))
        : ListView.builder(
            itemCount: _expenses.length,
            itemBuilder: (ctx, i) {
              final e = _expenses[i];
              return ListTile(
                leading: CircleAvatar(child: Text(e.category.label[0])),
                title: Text(
                  '${CurrencyFormatter.format(e.amount)} — ${e.category.label}',
                ),
                subtitle: Text(
                  '${DateFormat.yMMMd().format(e.date)}${e.note != null ? ' • ${e.note}' : ''}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete('this expense', () async {
                    await _db.deleteExpense(e.id);
                    _load();
                  }),
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddExpenseScreen(
                        siteId: widget.site.id,
                        existingExpense: e,
                      ),
                    ),
                  );
                  _load();
                },
              );
            },
          );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Total Spend',
                value: CurrencyFormatter.formatCompact(_totalSpend),
                color: Colors.red.shade50,
                icon: Icons.account_balance_wallet,
                iconColor: Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Float Received',
                value: CurrencyFormatter.formatCompact(_totalFloat),
                color: Colors.green.shade50,
                icon: Icons.input,
                iconColor: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: _hasTodayFloat
                    ? 'Cash Balance (Today)'
                    : 'Cash Balance (no float logged today)',
                value: CurrencyFormatter.formatCompact(_currentBalance),
                color: _currentBalance < 0
                    ? Colors.orange.shade50
                    : Colors.blue.shade50,
                icon: _currentBalance < 0 ? Icons.warning : Icons.savings,
                iconColor: _currentBalance < 0 ? Colors.orange : Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Log Count',
                value: '${_logs.length}',
                color: Colors.grey.shade100,
                icon: Icons.description,
                iconColor: Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _ActionButton(
              label: 'Add Expense',
              icon: Icons.add_card,
              color: Colors.red.shade700,
              onTap: () => _navigate(AddExpenseScreen(siteId: widget.site.id)),
            ),
            _ActionButton(
              label: 'Log Daily Progress',
              icon: Icons.edit_note,
              color: Colors.blue.shade800,
              onTap: () => _navigate(
                AddDailyLogScreen(
                  siteId: widget.site.id,
                  siteName: widget.site.name,
                ),
              ),
            ),
            _ActionButton(
              label: 'Reconcile Float',
              icon: Icons.account_balance_wallet,
              color: Colors.amber.shade900,
              onTap: () => _navigate(
                CashFloatScreen(
                  siteId: widget.site.id,
                  siteName: widget.site.name,
                ),
              ),
            ),
            _ActionButton(
              label: 'View Reports',
              icon: Icons.assessment,
              color: Colors.deepPurple,
              onTap: () => _navigate(
                ReportHubScreen(project: widget.project, site: widget.site),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'Site Operations',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _ActionButton(
              label: 'Crew Attendance',
              icon: Icons.people,
              color: Colors.indigo,
              onTap: () => _navigate(
                AttendanceScreen(
                  siteId: widget.site.id,
                  siteName: widget.site.name,
                ),
              ),
            ),
            _ActionButton(
              label: 'Material & Equipment',
              icon: Icons.construction,
              color: Colors.teal,
              onTap: () => _navigate(
                MaterialEquipmentLogScreen(
                  siteId: widget.site.id,
                  siteName: widget.site.name,
                ),
              ),
            ),
            _ActionButton(
              label: 'Sheets Sync',
              icon: Icons.table_chart,
              color: Colors.green.shade700,
              onTap: () => _navigate(GoogleSheetsSyncScreen(site: widget.site)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentLogs() {
    final recent = _logs.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Daily Logs',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            TextButton(
              onPressed: () => _navigate(DailyLogListScreen(site: widget.site)),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No daily logs yet')),
            ),
          )
        else
          ...recent.map(
            (log) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Text('${log.date.day.toString().padLeft(2, '0')}'),
                ),
                title: Text(
                  log.workCompleted?.split('\n').first ??
                      'No activity recorded',
                ),
                subtitle: Text(DateFormat.yMMMd().format(log.date)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _navigate(
                  DailyLogDetailScreen(log: log, site: widget.site),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final Color iconColor;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [color.withOpacity(0.8), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  final bool isSynced;
  const _SyncBadge({required this.isSynced});

  @override
  Widget build(BuildContext context) {
    final color = isSynced ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSynced ? Icons.cloud_done : Icons.cloud_off,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            isSynced ? 'Synced' : 'Pending Sync',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
