import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/cash_float.dart';
import '../services/google_sheets_service.dart';
import '../services/reconciliation_service.dart';
import '../utils/currency_formatter.dart';

/// Daily cash-float reconciliation.
///
/// The signed closing position is carried forward between days. When that
/// position is negative it represents personal money advanced by the engineer,
/// not negative physical cash.
class CashFloatScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const CashFloatScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<CashFloatScreen> createState() => _CashFloatScreenState();
}

class _CashFloatScreenState extends State<CashFloatScreen> {
  final _db = DatabaseHelper.instance;
  final _openingController = TextEditingController();
  final _floatController = TextEditingController();
  final _reportedController = TextEditingController();
  final _notesController = TextEditingController();

  CashFloat? _existingFloat;
  double _dailyExpenses = 0.0;
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final dateIso = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final cashFloat = await _db.getCashFloatBySiteAndDate(
      widget.siteId,
      dateIso,
    );
    final expenses = await _db.getTotalExpensesForSiteAndDate(
      widget.siteId,
      dateIso,
    );
    final previousFloat = await _db.getCashFloatBeforeDate(
      widget.siteId,
      dateIso,
    );

    if (!mounted) return;
    setState(() {
      _dailyExpenses = expenses;
      _existingFloat = cashFloat;
      if (cashFloat != null) {
        _openingController.text = cashFloat.openingBalance.toString();
        _floatController.text = cashFloat.floatReceived.toString();
        _reportedController.text = cashFloat.reportedClosingBalance.toString();
        _notesController.text = cashFloat.notes ?? '';
      } else {
        _openingController.text = (previousFloat?.expectedClosingBalance ?? 0)
            .toString();
        _floatController.clear();
        _reportedController.clear();
        _notesController.clear();
      }
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final opening = double.tryParse(_openingController.text) ?? 0.0;
    final floatReceived = double.tryParse(_floatController.text) ?? 0.0;
    final reported = double.tryParse(_reportedController.text) ?? 0.0;

    final result = ReconciliationService.reconcile(
      openingBalance: opening,
      floatReceived: floatReceived,
      lineItemTotals: [_dailyExpenses],
      reportedClosingBalance: reported,
    );

    final cashFloat = CashFloat(
      id: _existingFloat?.id ?? const Uuid().v4(),
      siteId: widget.siteId,
      date: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        12,
      ),
      openingBalance: opening,
      floatReceived: floatReceived,
      totalExpenses: _dailyExpenses,
      reportedClosingBalance: reported,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    final saved = await _db.upsertCashFloat(cashFloat);
    GoogleSheetsService.autoSyncSite(widget.siteId);

    setState(() => _existingFloat = saved);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.status == CashFloatStatus.ok
                ? (result.isOutOfPocketDeficit
                      ? 'Reconciled: engineer out-of-pocket advance recorded'
                      : 'Cash float reconciled: OK')
                : 'Variance detected: CHECK / MISMATCH',
          ),
          backgroundColor: result.status == CashFloatStatus.ok
              ? Colors.green
              : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final opening = double.tryParse(_openingController.text) ?? 0.0;
    final floatReceived = double.tryParse(_floatController.text) ?? 0.0;
    final reported = double.tryParse(_reportedController.text) ?? 0.0;
    final result = ReconciliationService.reconcile(
      openingBalance: opening,
      floatReceived: floatReceived,
      lineItemTotals: [_dailyExpenses],
      reportedClosingBalance: reported,
    );
    final expected = result.expectedClosingBalance;
    final expectedCash = result.expectedCashClosingBalance;
    final outOfPocketAdvance = result.outOfPocketAdvance;
    final variance = result.variance;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cash Float — ${widget.siteName}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [IconButton(icon: const Icon(Icons.save), onPressed: _save)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month),
                      title: const Text('Reconciliation date'),
                      subtitle: Text(DateFormat.yMMMMd().format(_selectedDate)),
                      trailing: const Icon(Icons.edit_calendar),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_existingFloat != null &&
                      _existingFloat!.status == CashFloatStatus.check)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CASH RECONCILIATION CHECK',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                Text(
                                  'Variance: ${CurrencyFormatter.format(_existingFloat!.variance)}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (expected < 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.orange.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Engineer Out-of-pocket Advance: '
                              '${CurrencyFormatter.format(outOfPocketAdvance)}. '
                              'Physical cash closing is '
                              '${CurrencyFormatter.format(expectedCash)}.',                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _buildCurrencyField(
                    _openingController,
                    'Opening / Carry-forward Balance',
                  ),
                  const SizedBox(height: 12),
                  _buildCurrencyField(_floatController, 'Float Received Today'),
                  const SizedBox(height: 12),
                  _buildCurrencyField(
                    _reportedController,
                    'Reported Cash Closing Balance',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Remarks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Reconciliation Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Divider(height: 24),
                          _buildSummaryRow('Opening / Carry-forward', opening),
                          _buildSummaryRow('Float Received', floatReceived),
                          _buildSummaryRow(
                            'Daily Expenses',
                            _dailyExpenses,
                            isDeduction: true,
                          ),
                          const Divider(),
                          if (result.isOutOfPocketDeficit) ...[
                            _buildSummaryRow(
                              'Expected Cash Closing',
                              expectedCash,
                              isBold: true,
                            ),
                            _buildSummaryRow(
                              'Engineer Out-of-pocket Advance',
                              outOfPocketAdvance,
                              isHighlight: true,
                            ),
                            _buildSummaryRow(
                              'Net Carry-forward',
                              expected,
                            ),
                          ] else
                            _buildSummaryRow(
                              'Expected Closing',
                              expectedCash,
                              isBold: true,
                            ),
                          _buildSummaryRow(
                            'Reported Cash Closing',
                            reported,
                          ),
                          const Divider(),
                          _buildSummaryRow(
                            'Variance',
                            variance,
                            isHighlight: true,
                            isAlert: variance.abs() >= 0.005,
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (result.status == CashFloatStatus.ok
                                          ? Colors.green
                                          : Colors.red)
                                      .withOpacity(.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              result.statusLabel,
                              style: TextStyle(
                                color: result.status == CashFloatStatus.ok
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null) return;
    setState(() {
      _selectedDate = selected;
      _isLoading = true;
    });
    await _loadData();
  }

  Widget _buildCurrencyField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₦ ',
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildSummaryRow(
    String label,
    double value, {
    bool isBold = false,
    bool isDeduction = false,
    bool isHighlight = false,
    bool isAlert = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold || isHighlight ? 16 : 14,
            ),
          ),
          Text(
            '${isDeduction ? '-' : ''}${CurrencyFormatter.format(value)}',
            style: TextStyle(
              fontWeight: isBold || isHighlight
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontSize: isBold || isHighlight ? 16 : 14,
              color: isAlert
                  ? Colors.red
                  : isDeduction
                  ? Colors.red.shade700
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _openingController.dispose();
    _floatController.dispose();
    _reportedController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
