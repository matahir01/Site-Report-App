import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/reporting_models.dart';
import '../services/reporting_service.dart';
import '../utils/currency_formatter.dart';

class MonthlyMatrixScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const MonthlyMatrixScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<MonthlyMatrixScreen> createState() => _MonthlyMatrixScreenState();
}

class _MonthlyMatrixScreenState extends State<MonthlyMatrixScreen> {
  MonthlyExpenseMatrix? _matrix;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final matrix = await ReportingService.monthlyMatrix(widget.siteId);
    if (mounted) setState(() => _matrix = matrix);
  }

  @override
  Widget build(BuildContext context) {
    final matrix = _matrix;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Monthly Matrix — ${widget.siteName}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: matrix == null
          ? const Center(child: CircularProgressIndicator())
          : matrix.months.isEmpty
          ? const Center(child: Text('No expenses have been logged yet.'))
          : Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: MaterialStatePropertyAll(
                      Theme.of(context).colorScheme.primaryContainer,
                    ),
                    columns: [
                      const DataColumn(label: Text('Category')),
                      for (final month in matrix.months)
                        DataColumn(numeric: true, label: Text(month)),
                      const DataColumn(
                        numeric: true,
                        label: Text('Category total'),
                      ),
                    ],
                    rows: [
                      for (final category in ExpenseCategory.values)
                        DataRow(
                          cells: [
                            DataCell(
                              SizedBox(width: 220, child: Text(category.label)),
                            ),
                            for (final month in matrix.months)
                              DataCell(
                                Text(
                                  CurrencyFormatter.formatCompact(
                                    matrix.categoryRows[category]?[month] ?? 0,
                                  ),
                                ),
                              ),
                            DataCell(
                              Text(
                                CurrencyFormatter.formatCompact(
                                  matrix.categoryTotal(category),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      DataRow(
                        color: MaterialStatePropertyAll(
                          Theme.of(context).colorScheme.secondaryContainer,
                        ),
                        cells: [
                          const DataCell(
                            Text(
                              'MONTHLY TOTAL',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          for (final month in matrix.months)
                            DataCell(
                              Text(
                                CurrencyFormatter.formatCompact(
                                  matrix.monthTotal(month),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          DataCell(
                            Text(
                              CurrencyFormatter.formatCompact(
                                matrix.grandTotal,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
