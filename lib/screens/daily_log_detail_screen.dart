import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/daily_site_report_meta.dart';
import '../models/site.dart';
import '../models/project.dart';
import '../models/attendance.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';
import '../models/diesel_activity_issuance.dart';
import '../models/concrete_pour.dart';
import '../models/cash_float.dart';
import '../models/expense.dart';
import '../models/worker.dart';
import '../utils/currency_formatter.dart';
import '../services/daily_site_report_store.dart';
import '../services/professional_daily_report_service.dart';
import '../services/report_file_service.dart';

/// Read-only daily log detail with attendance, materials, equipment,
/// concrete/QC, expenses, professional report metadata, and one-tap PDF export.
class DailyLogDetailScreen extends StatefulWidget {
  final DailyLog log;
  final Site site;

  const DailyLogDetailScreen({
    super.key,
    required this.log,
    required this.site,
  });

  @override
  State<DailyLogDetailScreen> createState() => _DailyLogDetailScreenState();
}

class _DailyLogDetailScreenState extends State<DailyLogDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<Attendance> _attendance = [];
  List<Worker> _workers = [];
  List<MaterialStockLog> _materials = [];
  List<EquipmentDippingLog> _equipment = [];
  List<DieselActivityIssuance> _dieselActivity = [];
  List<ConcretePour> _concretePours = [];
  List<Expense> _expenses = [];
  CashFloat? _cashFloat;
  DailySiteReportMeta? _reportMeta;
  Project? _project;
  bool _isLoading = true;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final attData = await _db.getAttendanceForLog(widget.log.id);
    final matData = await _db.getMaterialStockLogsForLog(widget.log.id);
    final eqData = await _db.getEquipmentDippingLogsForLog(widget.log.id);
    final dieselActivityData = await _db.getDieselActivityForLog(widget.log.id);
    final concretePourData = await _db.getConcretePoursForLog(widget.log.id);
    final workerData = await _db.getWorkersForSite(
      widget.site.id,
      activeOnly: false,
    );
    final dateIso = widget.log.date.toIso8601String().split('T').first;
    final expData = await _db.getExpensesForSiteAndDate(
      widget.site.id,
      dateIso,
    );
    final cashFloatData = await _db.getCashFloatBySiteAndDate(
      widget.site.id,
      dateIso,
    );
    final metaData = await DailySiteReportStore.instance.getForLog(
      widget.log.id,
    );
    final projects = await _db.getProjects();
    final project = projects.firstWhereOrNull(
      (p) => p.id == widget.site.projectId,
    );

    if (!mounted) return;
    setState(() {
      _attendance = attData;
      _materials = matData;
      _equipment = eqData;
      _dieselActivity = dieselActivityData;
      _concretePours = concretePourData;
      _workers = workerData;
      _expenses = expData;
      _cashFloat = cashFloatData;
      _reportMeta = metaData;
      _project = project;
      _isLoading = false;
    });
  }

  Future<void> _generatePdf() async {
    setState(() => _generatingPdf = true);
    try {
      final file = await ProfessionalDailyReportService.generate(
        site: widget.site,
        project: _project,
        log: widget.log,
        meta: _reportMeta,
        attendance: _attendance,
        workers: _workers,
        materials: _materials,
        equipment: _equipment,
        expenses: _expenses,
        dieselActivity: _dieselActivity,
        concretePours: _concretePours,
        cashFloat: _cashFloat,
      );
      if (mounted) {
        final saved = await ReportFileService.savePdfToDownloadsAndOpen(file);
        if (!mounted) return;
        if (saved == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF generated at ${file.path}')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                saved.opened
                    ? 'DPR saved to Downloads/Civil Site Manager and opened.'
                    : 'DPR saved to Downloads/Civil Site Manager. No PDF viewer opened it automatically.',
              ),
            ),
          );
        }
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

  String _workerName(String workerId) {
    final w = _workers.where((x) => x.id == workerId).firstOrNull;
    return w?.name ?? 'Unknown';
  }

  String _workerRole(String workerId) {
    final w = _workers.where((x) => x.id == workerId).firstOrNull;
    return w?.role ?? '';
  }

  String _metaText(String? value, {String empty = 'Not recorded'}) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? empty : text;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.yMMMd().format(widget.log.date);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$dateStr — ${widget.site.name}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: _generatingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
            onPressed: _generatingPdf || _isLoading ? null : _generatePdf,
            tooltip: 'Generate professional daily report',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('Daily Log'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_project != null)
                            _detailRow('Project', _project!.name),
                          _detailRow('Site', widget.site.name),
                          if (widget.log.weather != null)
                            _detailRow('Weather', widget.log.weather!),
                          if (widget.log.crewCount != null)
                            _detailRow('Crew Count', '${widget.log.crewCount}'),
                          if (widget.log.workCompleted != null &&
                              widget.log.workCompleted!.isNotEmpty)
                            _detailRow(
                              'Work Completed',
                              widget.log.workCompleted!,
                            ),
                          if (widget.log.issues != null &&
                              widget.log.issues!.isNotEmpty)
                            _detailRow('Issues', widget.log.issues!),
                          if (widget.log.latitude != null)
                            _detailRow(
                              'GPS',
                              '${widget.log.latitude!.toStringAsFixed(6)}, ${widget.log.longitude!.toStringAsFixed(6)}',
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionHeader('Professional Report Details'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow(
                            'Report No.',
                            _metaText(
                              _reportMeta?.reportNo,
                              empty: 'Auto-generated on export',
                            ),
                          ),
                          _detailRow(
                            'Shift',
                            _metaText(_reportMeta?.shift, empty: 'Day'),
                          ),
                          _detailRow(
                            'Measured Progress',
                            _reportMeta?.progressQuantity == null
                                ? 'Not recorded'
                                : '${_reportMeta!.progressQuantity}${_reportMeta!.progressUnit == null ? '' : ' ${_reportMeta!.progressUnit}'}',
                          ),
                          if (_reportMeta?.percentComplete != null)
                            _detailRow(
                              'Progress %',
                              '${_reportMeta!.percentComplete!.toStringAsFixed(1)}%',
                            ),
                          _detailRow(
                            'QC / Inspections',
                            _metaText(_reportMeta?.qualityInspections),
                          ),
                          _detailRow(
                            'HSE',
                            _metaText(_reportMeta?.hseObservations),
                          ),
                          _detailRow(
                            'Site Instructions',
                            _metaText(_reportMeta?.siteInstructions),
                          ),
                          _detailRow(
                            'Next-Day Plan',
                            _metaText(_reportMeta?.nextDayPlan),
                          ),
                          _detailRow(
                            'Document References',
                            _metaText(_reportMeta?.documentReferences),
                          ),
                          _detailRow(
                            'Prepared by',
                            _metaText(_reportMeta?.preparedBy),
                          ),
                          _detailRow(
                            'Reviewed by',
                            _metaText(_reportMeta?.reviewedBy),
                          ),
                          _detailRow(
                            'Approved by',
                            _metaText(_reportMeta?.approvedBy),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_hasAnySignature) ...[
                    const SizedBox(height: 18),
                    _sectionHeader('Digital Sign-off'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _signaturePreview(
                              label: 'Prepared by',
                              name: _reportMeta?.preparedBy,
                              path: _reportMeta?.preparedSignaturePath,
                            ),
                            _signaturePreview(
                              label: 'Reviewed by',
                              name: _reportMeta?.reviewedBy,
                              path: _reportMeta?.reviewedSignaturePath,
                            ),
                            _signaturePreview(
                              label: 'Approved by',
                              name: _reportMeta?.approvedBy,
                              path: _reportMeta?.approvedSignaturePath,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (widget.log.photoPaths.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _sectionHeader('Photos'),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.log.photoPaths.length,
                        itemBuilder: (ctx, i) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(widget.log.photoPaths[i]),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _sectionHeader('Crew Attendance'),
                  if (_attendance.isEmpty)
                    _emptyCard('No attendance records')
                  else
                    ..._attendance.map(
                      (a) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(_workerName(a.workerId)),
                          subtitle: Text(_workerRole(a.workerId)),
                          trailing: Chip(
                            label: Text(a.status.label),
                            backgroundColor:
                                a.status == AttendanceStatus.present
                                ? Colors.green.shade100
                                : a.status == AttendanceStatus.halfDay
                                ? Colors.orange.shade100
                                : Colors.red.shade100,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  _sectionHeader('Material Stock Reconciliation'),
                  if (_materials.isEmpty)
                    _emptyCard('No material records')
                  else
                    _buildDataTable(
                      columns: ['Item', 'Open', 'Recv', 'Issue', 'Close'],
                      rows: _materials
                          .map(
                            (m) => [
                              '${m.itemName} (${m.unit})',
                              m.openingBalance.toStringAsFixed(1),
                              m.received.toStringAsFixed(1),
                              m.issued.toStringAsFixed(1),
                              m.closingBalance.toStringAsFixed(1),
                            ],
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 24),
                  _sectionHeader('Equipment Dipping & Fuel'),
                  if (_equipment.isEmpty)
                    _emptyCard('No equipment records')
                  else
                    _buildDataTable(
                      columns: [
                        'Equipment',
                        'Open',
                        'Close',
                        'Diesel',
                        'Oil',
                        'Hours',
                      ],
                      rows: _equipment
                          .map(
                            (e) => [
                              e.equipmentName,
                              e.openingDipCm?.toStringAsFixed(1) ?? '-',
                              e.closingDipCm?.toStringAsFixed(1) ?? '-',
                              e.dieselIssuedLitres.toStringAsFixed(1),
                              e.engineOilIssuedLitres.toStringAsFixed(1),
                              e.operatingHours?.toStringAsFixed(1) ?? '-',
                            ],
                          )
                          .toList(),
                    ),
                  if (_dieselActivity.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionHeader('Diesel Issued to Activities'),
                    _buildDataTable(
                      columns: ['Activity / Machine', 'Litres'],
                      rows: _dieselActivity
                          .map(
                            (a) => [
                              a.activityName,
                              a.litresIssued.toStringAsFixed(1),
                            ],
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _sectionHeader('Concrete / Quality Control'),
                  if (_concretePours.isEmpty)
                    _emptyCard('No concrete pour or slump-test records')
                  else
                    _buildDataTable(
                      columns: ['Element', 'Grade', 'Vol.', 'Slump', 'Cubes'],
                      rows: _concretePours
                          .map(
                            (c) => [
                              c.elementName,
                              c.concreteGrade,
                              '${c.volumeM3.toStringAsFixed(2)} m³',
                              c.slumpMm == null
                                  ? '-'
                                  : '${c.slumpMm!.toStringAsFixed(0)} mm',
                              c.cubesCast.toString(),
                            ],
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 24),
                  _sectionHeader('Itemized Expenses'),
                  if (_expenses.isEmpty)
                    _emptyCard('No expenses recorded')
                  else
                    Column(
                      children: [
                        ..._expenses.map(
                          (e) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text('${e.serialNo ?? 0}'),
                              ),
                              title: Text(e.displayDescription),
                              subtitle: Text(e.category.label),
                              trailing: Text(
                                CurrencyFormatter.format(e.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade900,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                CurrencyFormatter.format(
                                  _expenses.fold(0.0, (s, e) => s + e.amount),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (_cashFloat != null) ...[
                    const SizedBox(height: 24),
                    _sectionHeader('Cash Float Reconciliation'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _detailRow(
                              'Opening',
                              CurrencyFormatter.format(
                                _cashFloat!.openingBalance,
                              ),
                            ),
                            _detailRow(
                              'Float Received',
                              CurrencyFormatter.format(
                                _cashFloat!.floatReceived,
                              ),
                            ),
                            _detailRow(
                              'Expected Closing',
                              CurrencyFormatter.format(
                                _cashFloat!.expectedClosingBalance,
                              ),
                            ),
                            _detailRow(
                              'Reported Closing',
                              CurrencyFormatter.format(
                                _cashFloat!.reportedClosingBalance,
                              ),
                            ),
                            _detailRow(
                              'Variance',
                              CurrencyFormatter.format(_cashFloat!.variance),
                            ),
                            _detailRow('Status', _cashFloat!.status.label),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _generatingPdf ? null : _generatePdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      _generatingPdf
                          ? 'Generating Report…'
                          : 'Generate Professional Daily Report',
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  bool get _hasAnySignature {
    final paths = [
      _reportMeta?.preparedSignaturePath,
      _reportMeta?.reviewedSignaturePath,
      _reportMeta?.approvedSignaturePath,
    ];
    return paths.any(
      (path) => path != null && path.isNotEmpty && File(path).existsSync(),
    );
  }

  Widget _signaturePreview({
    required String label,
    required String? name,
    required String? path,
  }) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_metaText(name), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Container(
            height: 72,
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.blueGrey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: path != null &&
                    path.isNotEmpty &&
                    File(path).existsSync()
                ? Image.file(File(path), fit: BoxFit.contain)
                : const Center(
                    child: Text(
                      'Not signed',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.blue.shade900,
        ),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }

  Widget _buildDataTable({
    required List<String> columns,
    required List<List<String>> rows,
  }) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
          columns: columns
              .map(
                (c) => DataColumn(
                  label: Text(
                    c,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
              .toList(),
          rows: rows.map((r) {
            return DataRow(
              cells: r.map((cell) => DataCell(Text(cell))).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}
