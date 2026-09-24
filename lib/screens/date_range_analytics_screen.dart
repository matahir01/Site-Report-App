import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/expense.dart';
import '../models/reporting_models.dart';
import '../services/date_range_export_service.dart';
import '../services/reporting_service.dart';
import '../utils/currency_formatter.dart';

class DateRangeAnalyticsScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const DateRangeAnalyticsScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<DateRangeAnalyticsScreen> createState() =>
      _DateRangeAnalyticsScreenState();
}

class _DateRangeAnalyticsScreenState extends State<DateRangeAnalyticsScreen> {
  final _searchController = TextEditingController();
  final _categories = <ExpenseCategory>{};
  late DateTime _startDate;
  late DateTime _endDate;
  DateRangeAnalytics? _analytics;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month);
    _endDate = now;
    _applyFilters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _applyFilters() async {
    setState(() => _loading = true);
    final analytics = await ReportingService.dateRange(
      siteId: widget.siteId,
      startDate: _startDate,
      endDate: _endDate,
      categories: _categories,
      search: _searchController.text,
    );
    if (mounted) {
      setState(() {
        _analytics = analytics;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
        if (_startDate.isAfter(picked)) _startDate = picked;
      }
    });
  }

  Future<void> _export() async {
    final analytics = _analytics;
    if (analytics == null || analytics.expenses.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final file = await DateRangeExportService.generateCsv(
        siteName: widget.siteName,
        analytics: analytics,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text:
              '${widget.siteName} expense detail ${DateFormat.yMMMd().format(_startDate)} – ${DateFormat.yMMMd().format(_endDate)}',
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final analytics = _analytics;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Date Range Analytics'),
        actions: [
          IconButton(
            tooltip: 'Export filtered line items',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _DateButton(
                          label: 'Start date',
                          date: _startDate,
                          onTap: () => _pickDate(start: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateButton(
                          label: 'End date',
                          date: _endDate,
                          onTap: () => _pickDate(start: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _applyFilters(),
                    decoration: const InputDecoration(
                      labelText: 'Search unit or description',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      _categories.isEmpty
                          ? 'All categories'
                          : '${_categories.length} categories selected',
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: ExpenseCategory.values.map((category) {
                            return FilterChip(
                              label: Text(category.label),
                              selected: _categories.contains(category),
                              onSelected: (selected) => setState(() {
                                if (selected) {
                                  _categories.add(category);
                                } else {
                                  _categories.remove(category);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _applyFilters,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Apply filters'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (analytics != null) ...[
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'Filtered total',
                    value: CurrencyFormatter.format(analytics.total),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryCard(
                    label: 'Item count',
                    value: '${analytics.itemCount}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCategorySummary(analytics),
            const SizedBox(height: 12),
            _buildDetailTable(analytics),
          ],
        ],
      ),
    );
  }

  Widget _buildCategorySummary(DateRangeAnalytics analytics) {
    final entries = analytics.categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spend by category',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const Text('No matching expenses.')
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry.key.label)),
                      Text(
                        '${analytics.percentageFor(entry.key).toStringAsFixed(1)}% · ${CurrencyFormatter.format(entry.value)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailTable(DateRangeAnalytics analytics) {
    if (analytics.expenses.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                'Detailed line-item table',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('S/N')),
                  DataColumn(label: Text('Description')),
                  DataColumn(label: Text('Qty')),
                  DataColumn(label: Text('Unit')),
                  DataColumn(label: Text('Unit price')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Category')),
                ],
                rows: analytics.expenses.map((expense) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(DateFormat('yyyy-MM-dd').format(expense.date)),
                      ),
                      DataCell(Text('${expense.serialNo ?? ''}')),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(expense.displayDescription),
                        ),
                      ),
                      DataCell(Text('${expense.quantity}')),
                      DataCell(Text(expense.unit ?? '1')),
                      DataCell(
                        Text(
                          CurrencyFormatter.format(
                            expense.unitPrice ?? expense.amount,
                          ),
                        ),
                      ),
                      DataCell(Text(CurrencyFormatter.format(expense.amount))),
                      DataCell(Text(expense.category.label)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(DateFormat.yMMMd().format(date)),
        ],
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(label),
        ],
      ),
    ),
  );
}
