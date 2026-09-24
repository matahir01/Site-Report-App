import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/reporting_models.dart';

class DateRangeExportService {
  DateRangeExportService._();

  static Future<File> generateCsv({
    required String siteName,
    required DateRangeAnalytics analytics,
  }) async {
    final rows = <List<Object?>>[
      [
        'Date',
        'S/N',
        'Description',
        'Unit',
        'Quantity',
        'Unit Price',
        'Total Amount',
        'Category',
        'Month',
      ],
      for (final expense in analytics.expenses)
        [
          DateFormat('yyyy-MM-dd').format(expense.date),
          expense.serialNo ?? '',
          expense.displayDescription,
          expense.unit ?? '1',
          expense.quantity,
          expense.unitPrice ?? expense.amount,
          expense.amount,
          expense.category.label,
          expense.monthKey,
        ],
    ];
    final content = rows
        .map((row) => row.map((value) => _escape('$value')).join(','))
        .join('\r\n');
    final directory = await getTemporaryDirectory();
    final safeSite = siteName.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final range =
        '${DateFormat('yyyyMMdd').format(analytics.startDate)}-${DateFormat('yyyyMMdd').format(analytics.endDate)}';
    final file = File(
      p.join(directory.path, '${safeSite}_expenses_$range.csv'),
    );
    await file.writeAsString('\uFEFF$content', flush: true);
    return file;
  }

  static String _escape(String value) => '"${value.replaceAll('"', '""')}"';
}
