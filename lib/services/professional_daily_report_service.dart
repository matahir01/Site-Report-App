import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/attendance.dart';
import '../models/cash_float.dart';
import '../models/concrete_pour.dart';
import '../models/daily_log.dart';
import '../models/daily_site_report_meta.dart';
import '../models/diesel_activity_issuance.dart';
import '../models/equipment_dipping_log.dart';
import '../models/expense.dart';
import '../models/material_stock_log.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/worker.dart';
import '../services/reconciliation_service.dart';
import '../utils/currency_formatter.dart';

/// Generates a controlled three-page A4 Daily Site Progress Report.
///
/// The page allocation is deliberate so a shared report always has the same
/// audit structure. Large daily ledgers remain complete in the Excel workbook;
/// the PDF shows a bounded detail set plus an explicit continuation notice.
class ProfessionalDailyReportService {
  static final PdfColor _navy = PdfColor.fromHex('#153A5B');
  static final PdfColor _blue = PdfColor.fromHex('#2B6CB0');
  static final PdfColor _paleBlue = PdfColor.fromHex('#EAF2F8');
  static final PdfColor _border = PdfColors.blueGrey300;
  static pw.ThemeData? _cachedTheme;

  static Future<pw.ThemeData> _theme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _cachedTheme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    return _cachedTheme!;
  }

  static Future<File> generate({
    required Site site,
    Project? project,
    required DailyLog log,
    DailySiteReportMeta? meta,
    required List<Attendance> attendance,
    required List<Worker> workers,
    required List<MaterialStockLog> materials,
    required List<EquipmentDippingLog> equipment,
    required List<Expense> expenses,
    List<DieselActivityIssuance> dieselActivity = const [],
    List<ConcretePour> concretePours = const [],
    CashFloat? cashFloat,
    String companyName = 'SWAS GRADE LIMITED',
  }) async {
    final document = pw.Document(theme: await _theme());
    final reportNo = _reportNumber(log, meta);
    final workerById = {for (final worker in workers) worker.id: worker};
    final roleCounts = <String, int>{};
    for (final record in attendance) {
      if (record.status == AttendanceStatus.absent) continue;
      final role = workerById[record.workerId]?.role ?? 'Unclassified';
      roleCounts.update(role, (value) => value + 1, ifAbsent: () => 1);
    }
    final manpowerRows = roleCounts.entries
        .map((entry) => [entry.key, '${entry.value}'])
        .toList();
    if (manpowerRows.isEmpty && log.crewCount != null) {
      manpowerRows.add(['Reported crew count', '${log.crewCount}']);
    }

    final expenseTotal = ReconciliationService.money(
      expenses.fold<double>(0, (sum, expense) => sum + expense.amount),
    );
    final reconciliation = cashFloat == null
        ? null
        : ReconciliationService.reconcile(
            openingBalance: cashFloat.openingBalance,
            floatReceived: cashFloat.floatReceived,
            lineItemTotals: [expenseTotal],
            reportedClosingBalance: cashFloat.reportedClosingBalance,
          );

    document.addPage(
      _page(
        pageNumber: 1,
        companyName: companyName,
        reportNo: reportNo,
        children: [
          _title('DAILY SITE PROGRESS REPORT'),
          pw.Center(
            child: pw.Text(
              'Progress, Resources, Quality, Safety & Expense Reconciliation',
              style: const pw.TextStyle(
                fontSize: 7.8,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.SizedBox(height: 7),
          _infoGrid([
            ['Project', project?.name ?? 'N/A'],
            ['Client', project?.client ?? 'N/A'],
            ['Site', site.name],
            [
              'Location',
              project?.siteLocation ?? site.address ?? 'Not recorded',
            ],
            ['Report No.', reportNo],
            ['Date', DateFormat('dd MMMM yyyy').format(log.date)],
            ['Day', DateFormat('EEEE').format(log.date)],
            ['Weather', log.weather ?? 'Not recorded'],
            ['Shift', _fallback(meta?.shift, 'Day')],
            ['Prepared by', _fallback(meta?.preparedBy, 'Not recorded')],
            [
              'Position',
              _fallback(meta?.preparedByPosition, 'Site / Design Engineer'),
            ],
            [
              'GPS',
              log.latitude == null
                  ? project?.gpsCoordinates ?? 'Not recorded'
                  : '${log.latitude!.toStringAsFixed(6)}, ${log.longitude!.toStringAsFixed(6)}',
            ],
          ]),
          _gap(),
          _section('1. WORK ACTIVITIES & PROGRESS'),
          _textBlock(
            _fallback(log.workCompleted, 'No work activities recorded.'),
            maxCharacters: 650,
          ),
          pw.SizedBox(height: 4),
          _infoGrid([
            ['Measured quantity', _progressQuantity(meta)],
            [
              'Progress',
              meta?.percentComplete == null
                  ? 'Not recorded'
                  : '${meta!.percentComplete!.toStringAsFixed(1)}%',
            ],
          ]),
          _gap(),
          _section('2. LABOUR / MANPOWER ROSTER'),
          if (manpowerRows.isEmpty)
            _empty('No manpower record for this daily log.')
          else
            _boundedTable(
              headers: const ['Trade / Role', 'No. on Site'],
              rows: manpowerRows,
              widths: const [4, 1],
              maxRows: 5,
            ),
          pw.SizedBox(height: 4),
          _infoGrid([
            [
              'Present',
              '${attendance.where((a) => a.status == AttendanceStatus.present).length}',
            ],
            [
              'Half-day',
              '${attendance.where((a) => a.status == AttendanceStatus.halfDay).length}',
            ],
            [
              'Absent',
              '${attendance.where((a) => a.status == AttendanceStatus.absent).length}',
            ],
            ['Total rostered', '${attendance.length}'],
          ], columns: 4),
          _gap(),
          _section('3. MATERIAL STOCK & CONSUMPTION'),
          if (materials.isEmpty)
            _empty('No material stock records.')
          else
            _boundedTable(
              headers: const [
                'Material',
                'Unit',
                'Opening',
                'Received',
                'Issued',
                'Closing',
              ],
              rows: materials
                  .map(
                    (item) => [
                      item.itemName,
                      item.unit,
                      _number(item.openingBalance),
                      _number(item.received),
                      _number(item.issued),
                      _number(item.closingBalance),
                    ],
                  )
                  .toList(),
              widths: const [2.7, 1, 1, 1, 1, 1],
              maxRows: 5,
            ),
          _gap(),
          _section('4. FUEL, LUBRICANT & EQUIPMENT DIP READINGS'),
          if (equipment.isEmpty)
            _empty('No equipment dipping or utilisation records.')
          else
            _boundedTable(
              headers: const [
                'Equipment',
                'Open Dip',
                'Diesel L',
                'Oil L',
                'Close Dip',
                'Hours',
              ],
              rows: equipment
                  .map(
                    (item) => [
                      item.equipmentName,
                      item.openingDipCm?.toStringAsFixed(1) ?? '-',
                      item.dieselIssuedLitres.toStringAsFixed(1),
                      item.engineOilIssuedLitres.toStringAsFixed(1),
                      item.closingDipCm?.toStringAsFixed(1) ?? '-',
                      item.operatingHours?.toStringAsFixed(1) ?? '-',
                    ],
                  )
                  .toList(),
              widths: const [2.7, 1, 1, 1, 1, 1],
              maxRows: 4,
            ),
          if (dieselActivity.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'Direct activity diesel: ${dieselActivity.map((item) => '${item.activityName} (${item.litresIssued.toStringAsFixed(1)} L)').join(', ')}',
              maxLines: 2,
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ],
      ),
    );

    document.addPage(
      _page(
        pageNumber: 2,
        companyName: companyName,
        reportNo: reportNo,
        children: [
          _section('5. QUALITY CONTROL / INSPECTIONS'),
          _textBlock(
            _fallback(
              meta?.qualityInspections,
              'No quality-control observation recorded.',
            ),
            maxCharacters: 450,
          ),
          if (concretePours.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            _boundedTable(
              headers: const [
                'Element',
                'Grade',
                'Vol. m³',
                'Slump mm',
                'Cubes',
                'Ticket',
              ],
              rows: concretePours
                  .map(
                    (item) => [
                      item.elementName,
                      item.concreteGrade,
                      item.volumeM3.toStringAsFixed(2),
                      item.slumpMm?.toStringAsFixed(0) ?? '-',
                      '${item.cubesCast}',
                      item.batchTicketNo ?? '-',
                    ],
                  )
                  .toList(),
              widths: const [2.3, 1, 1, 1, .8, 1.3],
              maxRows: 4,
            ),
          ],
          _gap(),
          _section('6. HEALTH, SAFETY & ENVIRONMENT'),
          _textBlock(
            _fallback(meta?.hseObservations, 'No HSE observation recorded.'),
            maxCharacters: 450,
          ),
          _gap(),
          _section('7. SITE EXPENSES & FLOAT RECONCILIATION'),
          if (expenses.isEmpty)
            _empty('No expenses recorded for this date.')
          else ...[
            _boundedTable(
              headers: const [
                'S/N',
                'Description',
                'Qty',
                'Unit',
                'Unit Rate',
                'Total Amount',
              ],
              rows: expenses
                  .map(
                    (expense) => [
                      '${expense.serialNo ?? ''}',
                      expense.displayDescription.isEmpty
                          ? expense.category.label
                          : expense.displayDescription,
                      _number(expense.quantity),
                      expense.unit ?? '1',
                      CurrencyFormatter.format(
                        expense.unitPrice ?? expense.amount,
                      ),
                      CurrencyFormatter.format(expense.amount),
                    ],
                  )
                  .toList(),
              widths: const [.6, 3, .8, .9, 1.3, 1.4],
              maxRows: 10,
            ),
            pw.SizedBox(height: 4),
            _moneyBar('TOTAL DAILY EXPENSES', expenseTotal),
          ],
          pw.SizedBox(height: 5),
          if (cashFloat == null)
            _empty('Daily float has not been reconciled.')
          else ...[
            _infoGrid([
              [
                'Opening balance',
                CurrencyFormatter.format(cashFloat.openingBalance),
              ],
              [
                'Float received',
                CurrencyFormatter.format(cashFloat.floatReceived),
              ],
              [
                'Expected closing',
                CurrencyFormatter.format(
                  reconciliation!.expectedClosingBalance,
                ),
              ],
              [
                'Reported closing',
                CurrencyFormatter.format(cashFloat.reportedClosingBalance),
              ],
              ['Variance', CurrencyFormatter.format(reconciliation.variance)],
              ['Status', reconciliation.statusLabel],
            ]),
            if (reconciliation.isOutOfPocketDeficit)
              _auditFlag(reconciliation.deficitLabel!),
          ],
          _gap(),
          _section('8. DELAYS, ISSUES & NEXT-DAY PLAN'),
          _labelledText(
            'Issues / Delays',
            _fallback(log.issues, 'None recorded.'),
            maxCharacters: 300,
          ),
          _labelledText(
            'Site Instructions',
            _fallback(meta?.siteInstructions, 'None recorded.'),
            maxCharacters: 300,
          ),
          _labelledText(
            'Next-Day Plan',
            _fallback(meta?.nextDayPlan, 'Not recorded.'),
            maxCharacters: 300,
          ),
        ],
      ),
    );

    document.addPage(
      _page(
        pageNumber: 3,
        companyName: companyName,
        reportNo: reportNo,
        children: [
          _section('9. SITE PHOTOS & DOCUMENT REFERENCES'),
          _labelledText(
            'Document References',
            _fallback(meta?.documentReferences, 'None recorded.'),
            maxCharacters: 350,
          ),
          pw.SizedBox(height: 5),
          _photoGrid(log.photoPaths, maxPhotos: 4),
          _gap(height: 10),
          _section('10. DIGITAL SIGN-OFF'),
          _signOff(meta),
          pw.SizedBox(height: 12),
          _auditNote(
            'Audit note',
            'This report is generated from offline field records. Expense totals use Quantity × Unit Price. Expected closing balance uses Opening Balance + Float Received − Total Daily Expenses. Any non-zero variance is marked CHECK / MISMATCH.',
          ),
          pw.Spacer(),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            color: _paleBlue,
            child: pw.Text(
              'End of Daily Site Progress Report · $reportNo',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                color: _navy,
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
              ),
            ),
          ),
        ],
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final reportDirectory = Directory(p.join(directory.path, 'reports'));
    await reportDirectory.create(recursive: true);
    final safeSite = site.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File(
      p.join(
        reportDirectory.path,
        '${safeSite}_Daily_Site_Report_${DateFormat('yyyy-MM-dd').format(log.date)}.pdf',
      ),
    );
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }

  static pw.Page _page({
    required int pageNumber,
    required String companyName,
    required String reportNo,
    required List<pw.Widget> children,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(25, 22, 25, 22),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(companyName, reportNo),
          pw.SizedBox(height: 7),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          _footer(pageNumber, 3),
        ],
      ),
    );
  }

  static String _reportNumber(DailyLog log, DailySiteReportMeta? meta) {
    if (_text(meta?.reportNo).isNotEmpty) return _text(meta?.reportNo);
    final shortId = log.id.length > 6 ? log.id.substring(0, 6) : log.id;
    return 'DPR-${DateFormat('yyyyMMdd').format(log.date)}-${shortId.toUpperCase()}';
  }

  static String _text(String? value) => value?.trim() ?? '';

  static String _fallback(String? value, String fallback) {
    final normalized = _text(value);
    return normalized.isEmpty ? fallback : normalized;
  }

  static String _clip(String text, int maxCharacters) {
    if (text.length <= maxCharacters) return text;
    return '${text.substring(0, maxCharacters - 1).trimRight()}…';
  }

  static String _progressQuantity(DailySiteReportMeta? meta) {
    final quantity = _text(meta?.progressQuantity);
    final unit = _text(meta?.progressUnit);
    if (quantity.isEmpty) return 'Not recorded';
    return unit.isEmpty ? quantity : '$quantity $unit';
  }

  static String _number(double value) {
    if ((value - value.roundToDouble()).abs() < .0001) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  static pw.Widget _header(String companyName, String reportNo) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 1.4)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              companyName,
              style: pw.TextStyle(
                fontSize: 12.5,
                fontWeight: pw.FontWeight.bold,
                color: _navy,
              ),
            ),
            pw.Text(
              'Construction Site Management',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.Text(
          reportNo,
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
      ],
    ),
  );

  static pw.Widget _footer(int pageNumber, int totalPages) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.blueGrey200, width: .5),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Civil Site Manager · Generated from field records',
          style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
        ),
        pw.Text(
          'Page $pageNumber of $totalPages',
          style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
        ),
      ],
    ),
  );

  static pw.Widget _title(String text) => pw.Center(
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 15,
        fontWeight: pw.FontWeight.bold,
        color: _navy,
        letterSpacing: .4,
      ),
    ),
  );

  static pw.Widget _section(String title) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
    margin: const pw.EdgeInsets.only(bottom: 4),
    color: _navy,
    child: pw.Text(
      title,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 8.5,
      ),
    ),
  );

  static pw.Widget _gap({double height = 7}) => pw.SizedBox(height: height);

  static pw.Widget _empty(String message) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      border: pw.Border.all(color: _border, width: .45),
    ),
    child: pw.Text(
      message,
      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
    ),
  );

  static pw.Widget _textBlock(String text, {required int maxCharacters}) =>
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border, width: .45),
        ),
        child: pw.Text(
          _clip(text, maxCharacters),
          style: const pw.TextStyle(fontSize: 7.5, lineSpacing: 1.5),
        ),
      );

  static pw.Widget _labelledText(
    String label,
    String text, {
    required int maxCharacters,
  }) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 3),
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _border, width: .45),
    ),
    child: pw.RichText(
      text: pw.TextSpan(
        style: const pw.TextStyle(fontSize: 7.5),
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _navy),
          ),
          pw.TextSpan(text: _clip(text, maxCharacters)),
        ],
      ),
    ),
  );

  static pw.Widget _infoGrid(List<List<String>> items, {int columns = 2}) {
    final rows = <pw.TableRow>[];
    for (var index = 0; index < items.length; index += columns) {
      rows.add(
        pw.TableRow(
          children: [
            for (var offset = 0; offset < columns; offset++)
              if (index + offset < items.length)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4.5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        items[index + offset][0],
                        style: pw.TextStyle(
                          fontSize: 6.4,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        _clip(items[index + offset][1], 100),
                        maxLines: 2,
                        style: const pw.TextStyle(fontSize: 7.2),
                      ),
                    ],
                  ),
                )
              else
                pw.SizedBox(),
          ],
        ),
      );
    }
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: .4),
      children: rows,
    );
  }

  static pw.Widget _boundedTable({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> widths,
    required int maxRows,
  }) {
    final visibleRows = rows.take(maxRows).toList();
    final remaining = rows.length - visibleRows.length;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _table(headers, visibleRows, widths: widths),
        if (remaining > 0)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            color: PdfColors.grey100,
            child: pw.Text(
              '+ $remaining additional row${remaining == 1 ? '' : 's'} retained in the Excel audit workbook.',
              style: const pw.TextStyle(
                fontSize: 6.4,
                color: PdfColors.grey700,
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    required List<double> widths,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: .4),
      columnWidths: {
        for (var index = 0; index < widths.length; index++)
          index: pw.FlexColumnWidth(widths[index]),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _paleBlue),
          children: headers
              .map(
                (header) => pw.Padding(
                  padding: const pw.EdgeInsets.all(3.2),
                  child: pw.Text(
                    header,
                    style: pw.TextStyle(
                      fontSize: 6.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        ...rows.map(
          (row) => pw.TableRow(
            children: row
                .map(
                  (cell) => pw.Padding(
                    padding: const pw.EdgeInsets.all(3.2),
                    child: pw.Text(
                      _clip(cell, 80),
                      maxLines: 2,
                      style: const pw.TextStyle(fontSize: 6.5),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  static pw.Widget _moneyBar(String label, double amount) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    color: _navy,
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          CurrencyFormatter.format(amount),
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  static pw.Widget _auditFlag(String message) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 4),
    padding: const pw.EdgeInsets.all(5),
    color: PdfColors.orange100,
    child: pw.Text(
      message,
      style: pw.TextStyle(
        fontSize: 7,
        color: PdfColors.deepOrange900,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  static pw.Widget _photoGrid(List<String> paths, {required int maxPhotos}) {
    final available = paths.where((path) => File(path).existsSync()).toList();
    if (available.isEmpty) return _empty('No site photographs attached.');
    final photos = available.take(maxPhotos).toList();
    return pw.Column(
      children: [
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: photos.asMap().entries.map((entry) {
            final bytes = File(entry.value).readAsBytesSync();
            return pw.Container(
              width: 257,
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _border, width: .5),
              ),
              child: pw.Column(
                children: [
                  pw.Image(
                    pw.MemoryImage(bytes),
                    width: 249,
                    height: 142,
                    fit: pw.BoxFit.cover,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Photo ${entry.key + 1}',
                    style: const pw.TextStyle(
                      fontSize: 6.5,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        if (available.length > photos.length)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              '+ ${available.length - photos.length} additional photo${available.length - photos.length == 1 ? '' : 's'} retained with the daily log.',
              style: const pw.TextStyle(
                fontSize: 6.5,
                color: PdfColors.grey700,
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _signOff(DailySiteReportMeta? meta) {
    final signers = <_Signer>[
      _Signer(
        label: 'Prepared by',
        name: _fallback(meta?.preparedBy, '____________________'),
        role: _fallback(meta?.preparedByPosition, 'Site / Design Engineer'),
        signaturePath: meta?.preparedSignaturePath,
      ),
      _Signer(
        label: 'Reviewed by',
        name: _fallback(meta?.reviewedBy, '____________________'),
        role: 'Project / Site Manager',
        signaturePath: meta?.reviewedSignaturePath,
      ),
      _Signer(
        label: 'Approved / Noted by',
        name: _fallback(meta?.approvedBy, '____________________'),
        role: 'Authorised Representative',
        signaturePath: meta?.approvedSignaturePath,
      ),
    ];
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: signers.map((signer) {
        final signatureFile = signer.signaturePath == null
            ? null
            : File(signer.signaturePath!);
        final hasSignature = signatureFile?.existsSync() == true;
        return pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 5),
            padding: const pw.EdgeInsets.all(7),
            height: 140,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _border, width: .5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  signer.label,
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy,
                  ),
                ),
                pw.SizedBox(height: 5),
                if (hasSignature)
                  pw.Center(
                    child: pw.Image(
                      pw.MemoryImage(signatureFile!.readAsBytesSync()),
                      height: 42,
                      fit: pw.BoxFit.contain,
                    ),
                  )
                else
                  pw.SizedBox(height: 42),
                pw.Divider(color: _border, height: 3),
                pw.Text(signer.name, style: const pw.TextStyle(fontSize: 7.2)),
                pw.Text(
                  signer.role,
                  style: const pw.TextStyle(
                    fontSize: 6.3,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  'Date: __________________',
                  style: const pw.TextStyle(fontSize: 6.3),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _auditNote(String label, String text) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _blue, width: .6),
      color: _paleBlue,
    ),
    child: pw.RichText(
      text: pw.TextSpan(
        style: const pw.TextStyle(fontSize: 7.2),
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(color: _navy, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(text: text),
        ],
      ),
    ),
  );
}

class _Signer {
  final String label;
  final String name;
  final String role;
  final String? signaturePath;

  const _Signer({
    required this.label,
    required this.name,
    required this.role,
    required this.signaturePath,
  });
}
