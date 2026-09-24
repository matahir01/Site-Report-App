import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/expense.dart';
import '../services/google_sheets_service.dart';

class QuickExpenseSheet extends StatefulWidget {
  final String siteId;
  const QuickExpenseSheet({super.key, required this.siteId});

  static ExpenseCategory _lastCategory = ExpenseCategory.materials;

  @override
  State<QuickExpenseSheet> createState() => _QuickExpenseSheetState();
}

class _QuickExpenseSheetState extends State<QuickExpenseSheet> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  late ExpenseCategory _category = QuickExpenseSheet._lastCategory;
  String? _receiptPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_descriptionFocus);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _amountFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  Future<void> _snapReceipt() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
    );
    if (file == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final savedPath = p.join(appDir.path, 'receipts', fileName);
    await Directory(p.join(appDir.path, 'receipts')).create(recursive: true);
    await File(file.path).copy(savedPath);
    setState(() => _receiptPath = savedPath);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter an amount first')));
      return;
    }
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a description first')),
      );
      return;
    }

    setState(() => _saving = true);
    QuickExpenseSheet._lastCategory = _category;

    final now = DateTime.now();
    final monthKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final serialNo = await DatabaseHelper.instance.getNextExpenseSerialNo(
      widget.siteId,
      monthKey,
    );

    final expense = Expense(
      id: const Uuid().v4(),
      siteId: widget.siteId,
      date: now,
      category: _category,
      amount: amount,
      note: null,
      receiptPhotoPath: _receiptPath,
      serialNo: serialNo,
      description: description,
      unitPrice: amount,
      month: monthKey,
    );
    await DatabaseHelper.instance.insertExpense(expense);
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
                  'Quick Expense',
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
          DropdownButtonFormField<ExpenseCategory>(
            value: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: ExpenseCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            focusNode: _descriptionFocus,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What was this expense for?',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_amountFocus),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            focusNode: _amountFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              prefixText: 'N ',
              prefixStyle: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _snapReceipt,
                  icon: Icon(
                    _receiptPath == null
                        ? Icons.camera_alt
                        : Icons.check_circle,
                  ),
                  label: Text(
                    _receiptPath == null ? 'Snap Receipt' : 'Receipt Added',
                  ),
                ),
              ),
            ],
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
                : const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
