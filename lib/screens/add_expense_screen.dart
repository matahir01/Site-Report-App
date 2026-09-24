import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/cash_float.dart';
import '../models/expense.dart';
import '../services/google_sheets_service.dart';
import '../services/reconciliation_service.dart';
import '../utils/currency_formatter.dart';

/// Full itemized expense entry. New entries support any number of rows and are
/// committed atomically. Editing intentionally stays single-row to keep audit
/// history unambiguous.
class AddExpenseScreen extends StatefulWidget {
  final String siteId;
  final Expense? existingExpense;

  const AddExpenseScreen({
    super.key,
    required this.siteId,
    this.existingExpense,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _db = DatabaseHelper.instance;
  final _openingController = TextEditingController();
  final _floatController = TextEditingController();
  final _reportedController = TextEditingController();
  final _notesController = TextEditingController();
  final _lines = <_ExpenseLineDraft>[];

  late DateTime _entryDate;
  CashFloat? _existingFloat;
  double _savedExpenseTotal = 0;
  bool _loadingDay = true;
  bool _saving = false;

  bool get _isEditing => widget.existingExpense != null;

  @override
  void initState() {
    super.initState();
    _entryDate = widget.existingExpense?.date ?? DateTime.now();
    _lines.add(
      widget.existingExpense == null
          ? _ExpenseLineDraft()
          : _ExpenseLineDraft.fromExpense(widget.existingExpense!),
    );
    _loadDay();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _openingController.dispose();
    _floatController.dispose();
    _reportedController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_entryDate);

  Future<void> _loadDay() async {
    setState(() => _loadingDay = true);
    final existing = await _db.getCashFloatBySiteAndDate(
      widget.siteId,
      _dateKey,
    );
    final savedTotal = await _db.getTotalExpensesForSiteAndDate(
      widget.siteId,
      _dateKey,
    );
    final previous = existing == null
        ? await _db.getCashFloatBeforeDate(widget.siteId, _dateKey)
        : null;
    if (!mounted) return;
    setState(() {
      _existingFloat = existing;
      _savedExpenseTotal = savedTotal;
      _openingController.text = _editableNumber(
        existing?.openingBalance ?? previous?.expectedClosingBalance ?? 0,
      );
      _floatController.text = _editableNumber(existing?.floatReceived ?? 0);
      _reportedController.text = existing == null
          ? ''
          : _editableNumber(existing.reportedClosingBalance);
      _notesController.text = existing?.notes ?? '';
      _loadingDay = false;
    });
  }

  String _editableNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  double get _batchTotal => ReconciliationService.money(
    _lines.fold<double>(0, (sum, line) => sum + line.total),
  );

  double get _baseSavedExpenseTotal {
    if (!_isEditing) return _savedExpenseTotal;
    return ReconciliationService.money(
      _savedExpenseTotal - widget.existingExpense!.amount,
    );
  }

  ReconciliationResult get _reconciliation => ReconciliationService.reconcile(
    openingBalance: double.tryParse(_openingController.text.trim()) ?? 0,
    floatReceived: double.tryParse(_floatController.text.trim()) ?? 0,
    lineItemTotals: [_baseSavedExpenseTotal, _batchTotal],
    reportedClosingBalance:
        double.tryParse(_reportedController.text.trim()) ?? 0,
  );

  Future<void> _selectDate() async {
    if (_isEditing) return;
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _entryDate,
    );
    if (selected == null) return;
    setState(() => _entryDate = selected);
    await _loadDay();
  }

  void _addLine() => setState(() => _lines.add(_ExpenseLineDraft()));

  void _removeLine(int index) {
    if (_lines.length == 1) return;
    setState(() => _lines.removeAt(index).dispose());
  }

  Future<void> _pickReceipt(int index) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (file == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final receiptDir = Directory(p.join(appDir.path, 'receipts'));
    await receiptDir.create(recursive: true);
    final savedPath = p.join(
      receiptDir.path,
      '${const Uuid().v4()}${p.extension(file.path)}',
    );
    await File(file.path).copy(savedPath);
    if (mounted) setState(() => _lines[index].receiptPath = savedPath);
  }

  String? _validationError() {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.description.text.trim().isEmpty) {
        return 'Item ${i + 1}: enter a description';
      }
      if (line.quantity == null || line.quantity! <= 0) {
        return 'Item ${i + 1}: quantity must be greater than zero';
      }
      if (line.unitPrice == null || line.unitPrice! < 0) {
        return 'Item ${i + 1}: enter a valid unit price';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validationError();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    try {
      final month = DateFormat('yyyy-MM').format(_entryDate);
      var serial = _isEditing
          ? widget.existingExpense!.serialNo ?? 1
          : await _db.getNextExpenseSerialNo(widget.siteId, month);
      final expenses = _lines.map((line) {
        return Expense(
          id: _isEditing ? widget.existingExpense!.id : const Uuid().v4(),
          siteId: widget.siteId,
          date: DateTime(_entryDate.year, _entryDate.month, _entryDate.day, 12),
          category: line.category,
          amount: line.total,
          note: line.description.text.trim(),
          receiptPhotoPath: line.receiptPath,
          serialNo: serial++,
          description: line.description.text.trim(),
          unit: line.unit.text.trim().isEmpty ? '1' : line.unit.text.trim(),
          quantity: line.quantity!,
          unitPrice: line.unitPrice!,
          dailyFloatId: _existingFloat?.id,
          month: month,
        );
      }).toList();

      if (_isEditing) {
        await _db.updateExpense(expenses.single);
        if (_reportedController.text.trim().isNotEmpty) {
          await _db.upsertCashFloat(_cashFloatForForm());
        }
      } else if (_reportedController.text.trim().isEmpty) {
        await _db.insertExpenseBatch(expenses);
      } else {
        await _db.saveExpenseBatchAndReconciliation(
          expenses: expenses,
          cashFloat: _cashFloatForForm(),
        );
      }
      GoogleSheetsService.autoSyncSite(widget.siteId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save expenses: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  CashFloat _cashFloatForForm() => CashFloat(
    id: _existingFloat?.id ?? const Uuid().v4(),
    siteId: widget.siteId,
    date: DateTime(_entryDate.year, _entryDate.month, _entryDate.day, 12),
    openingBalance: double.tryParse(_openingController.text.trim()) ?? 0,
    floatReceived: double.tryParse(_floatController.text.trim()) ?? 0,
    totalExpenses: _reconciliation.totalExpenses,
    reportedClosingBalance:
        double.tryParse(_reportedController.text.trim()) ?? 0,
    notes: _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    final reconciliation = _reconciliation;
    final hasReported = _reportedController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Expense' : 'Add Itemized Expenses'),
      ),
      body: _loadingDay
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_month),
                    title: const Text('Entry date'),
                    subtitle: Text(DateFormat.yMMMMd().format(_entryDate)),
                    trailing: _isEditing
                        ? null
                        : const Icon(Icons.edit_calendar),
                    onTap: _selectDate,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _lines.length; i++) _buildLineCard(i),
                if (!_isEditing)
                  OutlinedButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add),
                    label: const Text('Add another line item'),
                  ),
                const SizedBox(height: 16),
                _buildReconciliationCard(reconciliation, hasReported),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isEditing
                        ? 'Update expense'
                        : 'Save ${_lines.length} expense item${_lines.length == 1 ? '' : 's'}',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLineCard(int index) {
    final line = _lines[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Line item ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_lines.length > 1)
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: () => _removeLine(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            DropdownButtonFormField<ExpenseCategory>(
              value: line.category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: ExpenseCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => line.category = value!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: line.description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: line.unit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      hintText: 'bag, litre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.unitPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Unit price',
                      prefixText: '₦ ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Line total: ${CurrencyFormatter.format(line.total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _pickReceipt(index),
                  icon: Icon(
                    line.receiptPath == null
                        ? Icons.camera_alt_outlined
                        : Icons.check_circle,
                  ),
                  label: Text(
                    line.receiptPath == null ? 'Receipt' : 'Attached',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReconciliationCard(
    ReconciliationResult result,
    bool hasReported,
  ) {
    final matched = hasReported && result.status == CashFloatStatus.ok;
    final badgeColor = !hasReported
        ? Colors.blueGrey
        : matched
        ? Colors.green
        : Colors.red;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Live float reconciliation',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _moneyField(_openingController, 'Opening')),
                const SizedBox(width: 8),
                Expanded(
                  child: _moneyField(_floatController, 'Float received'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _moneyField(
              _reportedController,
              'Reported closing (optional until cash is counted)',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Float notes',
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 28),
            _summaryRow('Already saved today', _baseSavedExpenseTotal),
            _summaryRow('This batch', _batchTotal),
            _summaryRow(
              'Total daily expenses',
              result.totalExpenses,
              bold: true,
            ),
            _summaryRow(
              'Expected closing',
              result.expectedClosingBalance,
              bold: true,
            ),
            _summaryRow('Variance', hasReported ? result.variance : 0),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(.12),
                border: Border.all(color: badgeColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                !hasReported
                    ? 'Expected balance calculated — enter reported closing to reconcile'
                    : matched
                    ? 'OK · ${CurrencyFormatter.format(0)} variance'
                    : 'CHECK / MISMATCH · ${CurrencyFormatter.format(result.variance)} variance',
                style: TextStyle(
                  color: badgeColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (result.isOutOfPocketDeficit)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  result.deficitLabel!,
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _moneyField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: '₦ ',
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      );

  Widget _summaryRow(String label, double value, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
              ),
            ),
            Text(
              CurrencyFormatter.format(value),
              style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
            ),
          ],
        ),
      );
}

class _ExpenseLineDraft {
  ExpenseCategory category;
  final TextEditingController description;
  final TextEditingController unit;
  final TextEditingController quantityController;
  final TextEditingController unitPriceController;
  String? receiptPath;

  _ExpenseLineDraft({
    this.category = ExpenseCategory.materials,
    String description = '',
    String unit = '1',
    String quantity = '1',
    String unitPrice = '',
    this.receiptPath,
  }) : description = TextEditingController(text: description),
       unit = TextEditingController(text: unit),
       quantityController = TextEditingController(text: quantity),
       unitPriceController = TextEditingController(text: unitPrice);

  factory _ExpenseLineDraft.fromExpense(Expense expense) => _ExpenseLineDraft(
    category: expense.category,
    description: expense.displayDescription,
    unit: expense.unit ?? '1',
    quantity: expense.quantity.toString(),
    unitPrice: (expense.unitPrice ?? expense.amount).toString(),
    receiptPath: expense.receiptPhotoPath,
  );

  double? get quantity => double.tryParse(quantityController.text.trim());
  double? get unitPrice => double.tryParse(unitPriceController.text.trim());

  double get total {
    final qty = quantity;
    final price = unitPrice;
    if (qty == null || qty <= 0 || price == null || price < 0) return 0;
    return ReconciliationService.lineTotal(quantity: qty, unitPrice: price);
  }

  void dispose() {
    description.dispose();
    unit.dispose();
    quantityController.dispose();
    unitPriceController.dispose();
  }
}
