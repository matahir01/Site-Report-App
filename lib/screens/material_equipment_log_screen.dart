import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';
import '../models/diesel_activity_issuance.dart';
import '../models/concrete_pour.dart';
import '../services/google_sheets_service.dart';

/// One editable row for diesel issued to a non-dipped activity/machine
/// (generator, mixer, welding set, etc.).
class _ActivityDieselRow {
  String? id;
  final TextEditingController nameCtrl;
  final TextEditingController litresCtrl;

  _ActivityDieselRow({this.id, String name = '', String litres = ''})
    : nameCtrl = TextEditingController(text: name),
      litresCtrl = TextEditingController(text: litres);

  void dispose() {
    nameCtrl.dispose();
    litresCtrl.dispose();
  }
}

/// One editable row for a single concrete pour / slump-test QC record.
class _ConcretePourRow {
  String? id;
  final TextEditingController elementCtrl;
  final TextEditingController gradeCtrl;
  final TextEditingController volumeCtrl;
  final TextEditingController slumpCtrl;
  final TextEditingController cubesCtrl;
  final TextEditingController batchCtrl;

  _ConcretePourRow({
    this.id,
    String element = '',
    String grade = '',
    String volume = '',
    String slump = '',
    String cubes = '',
    String batch = '',
  }) : elementCtrl = TextEditingController(text: element),
       gradeCtrl = TextEditingController(text: grade),
       volumeCtrl = TextEditingController(text: volume),
       slumpCtrl = TextEditingController(text: slump),
       cubesCtrl = TextEditingController(text: cubes),
       batchCtrl = TextEditingController(text: batch);

  void dispose() {
    elementCtrl.dispose();
    gradeCtrl.dispose();
    volumeCtrl.dispose();
    slumpCtrl.dispose();
    cubesCtrl.dispose();
    batchCtrl.dispose();
  }
}

/// Tabbed screen for daily material stock ledger and equipment fuel dipping.
/// Auto-creates a [DailyLog] for today if none exists.
///
/// Closing balances are never typed in manually — they are always derived
/// as Opening + Received − Issued, so the ledger can't drift out of sync
/// with itself. Diesel additionally rolls per-machine dip-log issuance and
/// ad-hoc activity issuance into one sitewide reconciliation figure.
class MaterialEquipmentLogScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const MaterialEquipmentLogScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<MaterialEquipmentLogScreen> createState() =>
      _MaterialEquipmentLogScreenState();
}

class _MaterialEquipmentLogScreenState extends State<MaterialEquipmentLogScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseHelper.instance;
  late TabController _tabController;
  String? _dailyLogId;
  bool _isLoading = true;

  final List<Map<String, String>> _materialItems = const [
    {'name': 'Y25mm Rebar', 'unit': 'length'},
    {'name': 'Y20mm Rebar', 'unit': 'length'},
    {'name': 'Y16mm Rebar', 'unit': 'length'},
    {'name': 'Y12mm Rebar', 'unit': 'length'},
    {'name': 'Cement', 'unit': 'Bags'},
    {'name': 'Diesel', 'unit': 'Litres'},
  ];
  final Map<String, TextEditingController> _matOpen = {};
  final Map<String, TextEditingController> _matRecv = {};
  final Map<String, TextEditingController> _matIssue = {};

  final List<String> _equipmentNames = const [
    'Excavator',
    'Mixer',
    'Generator',
    'Compactor',
  ];
  final Map<String, TextEditingController> _eqOpen = {};
  final Map<String, TextEditingController> _eqClose = {};
  final Map<String, TextEditingController> _eqDiesel = {};
  final Map<String, TextEditingController> _eqOil = {};

  final List<_ActivityDieselRow> _activityRows = [];
  final List<_ConcretePourRow> _concreteRows = [];

  double _num(TextEditingController c) => double.tryParse(c.text) ?? 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initialize();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final logs = await _db.getLogsForSite(widget.siteId);
    final todayLog = logs.where((l) {
      final d = l.date;
      return d.year == todayStart.year &&
          d.month == todayStart.month &&
          d.day == todayStart.day;
    }).toList();

    if (todayLog.isNotEmpty) {
      _dailyLogId = todayLog.first.id;
    } else {
      final log = DailyLog(
        id: const Uuid().v4(),
        siteId: widget.siteId,
        date: todayStart,
        workCompleted: '',
        weather: '',
      );
      await _db.insertDailyLog(log);
      _dailyLogId = log.id;
    }

    for (final item in _materialItems) {
      final name = item['name']!;
      _matOpen[name] = TextEditingController()..addListener(_refresh);
      _matRecv[name] = TextEditingController()..addListener(_refresh);
      _matIssue[name] = TextEditingController()..addListener(_refresh);
    }
    for (final name in _equipmentNames) {
      _eqOpen[name] = TextEditingController();
      _eqClose[name] = TextEditingController();
      _eqDiesel[name] = TextEditingController()..addListener(_refresh);
      _eqOil[name] = TextEditingController();
    }

    final existingMat = await _db.getMaterialStockLogsForLog(_dailyLogId!);
    for (final log in existingMat) {
      _matOpen[log.itemName]?.text = log.openingBalance.toString();
      _matRecv[log.itemName]?.text = log.received.toString();
      // Diesel's "Issued" is derived from equipment + activity issuance
      // below and re-populated after those load, so skip it here.
      if (log.itemName != 'Diesel') {
        _matIssue[log.itemName]?.text = log.issued.toString();
      }
    }

    final existingEq = await _db.getEquipmentDippingLogsForLog(_dailyLogId!);
    for (final log in existingEq) {
      _eqOpen[log.equipmentName]?.text = log.openingDipCm?.toString() ?? '';
      _eqClose[log.equipmentName]?.text = log.closingDipCm?.toString() ?? '';
      _eqDiesel[log.equipmentName]?.text = log.dieselIssuedLitres.toString();
      _eqOil[log.equipmentName]?.text = log.engineOilIssuedLitres.toString();
    }

    final existingActivity = await _db.getDieselActivityForLog(_dailyLogId!);
    for (final a in existingActivity) {
      final row = _ActivityDieselRow(
        id: a.id,
        name: a.activityName,
        litres: a.litresIssued.toString(),
      );
      row.litresCtrl.addListener(_refresh);
      _activityRows.add(row);
    }

    final existingConcrete = await _db.getConcretePoursForLog(_dailyLogId!);
    for (final c in existingConcrete) {
      _concreteRows.add(
        _ConcretePourRow(
          id: c.id,
          element: c.elementName,
          grade: c.concreteGrade,
          volume: c.volumeM3.toString(),
          slump: c.slumpMm?.toString() ?? '',
          cubes: c.cubesCast.toString(),
          batch: c.batchTicketNo ?? '',
        ),
      );
    }

    for (final item in _materialItems) {
      final name = item['name']!;
      final lastBal = await _db.getLastClosingBalance(widget.siteId, name);
      if (lastBal != null && _matOpen[name]!.text.isEmpty) {
        _matOpen[name]!.text = lastBal.toString();
      }
    }

    // Diesel issued is always the sum of what left the tank via dipped
    // machines plus what went straight to non-dipped activities.
    _matIssue['Diesel']!.text = _dieselIssuedComputed().toString();

    setState(() => _isLoading = false);
  }

  double _dieselIssuedComputed() {
    final fromMachines = _eqDiesel.values.fold<double>(
      0.0,
      (s, c) => s + _num(c),
    );
    final fromActivities = _activityRows.fold<double>(
      0.0,
      (s, r) => s + _num(r.litresCtrl),
    );
    return fromMachines + fromActivities;
  }

  double _computedClosing(String name) {
    if (name == 'Diesel') {
      return _num(_matOpen[name]!) +
          _num(_matRecv[name]!) -
          _dieselIssuedComputed();
    }
    return _num(_matOpen[name]!) +
        _num(_matRecv[name]!) -
        _num(_matIssue[name]!);
  }

  void _addActivityRow() {
    setState(() {
      final row = _ActivityDieselRow();
      row.litresCtrl.addListener(_refresh);
      _activityRows.add(row);
    });
  }

  void _removeActivityRow(int index) {
    setState(() {
      _activityRows[index].dispose();
      _activityRows.removeAt(index);
    });
  }

  void _addConcreteRow() {
    setState(() => _concreteRows.add(_ConcretePourRow()));
  }

  void _removeConcreteRow(int index) {
    setState(() {
      _concreteRows[index].dispose();
      _concreteRows.removeAt(index);
    });
  }

  Future<void> _saveMaterialLogs() async {
    if (_dailyLogId == null) return;
    // Clear out any rows from a previous save for this daily log so
    // re-saving doesn't accumulate duplicate rows.
    await _db.deleteMaterialStockLogsForLog(_dailyLogId!);
    for (final item in _materialItems) {
      final name = item['name']!;
      final unit = item['unit']!;
      final opening = _num(_matOpen[name]!);
      final received = _num(_matRecv[name]!);
      final issued = name == 'Diesel'
          ? _dieselIssuedComputed()
          : _num(_matIssue[name]!);
      final log = MaterialStockLog(
        id: const Uuid().v4(),
        dailyLogId: _dailyLogId!,
        itemName: name,
        unit: unit,
        openingBalance: opening,
        received: received,
        issued: issued,
        closingBalance: opening + received - issued,
      );
      await _db.insertMaterialStockLog(log);
    }
  }

  Future<void> _saveEquipmentLogs() async {
    if (_dailyLogId == null) return;
    // Clear out any rows from a previous save for this daily log so
    // re-saving doesn't accumulate duplicate rows.
    await _db.deleteEquipmentDippingLogsForLog(_dailyLogId!);
    for (final name in _equipmentNames) {
      final log = EquipmentDippingLog(
        id: const Uuid().v4(),
        dailyLogId: _dailyLogId!,
        equipmentName: name,
        openingDipCm: double.tryParse(_eqOpen[name]!.text),
        closingDipCm: double.tryParse(_eqClose[name]!.text),
        dieselIssuedLitres: _num(_eqDiesel[name]!),
        engineOilIssuedLitres: _num(_eqOil[name]!),
      );
      await _db.insertEquipmentDippingLog(log);
    }
  }

  Future<void> _saveActivityDiesel() async {
    if (_dailyLogId == null) return;
    await _db.deleteDieselActivityForLog(_dailyLogId!);
    for (final row in _activityRows) {
      if (row.nameCtrl.text.trim().isEmpty) continue;
      final entry = DieselActivityIssuance(
        id: const Uuid().v4(),
        dailyLogId: _dailyLogId!,
        activityName: row.nameCtrl.text.trim(),
        litresIssued: _num(row.litresCtrl),
      );
      await _db.insertDieselActivityIssuance(entry);
    }
  }

  Future<void> _saveConcretePours() async {
    if (_dailyLogId == null) return;
    await _db.deleteConcretePoursForLog(_dailyLogId!);
    for (final row in _concreteRows) {
      if (row.elementCtrl.text.trim().isEmpty) continue;
      final pour = ConcretePour(
        id: const Uuid().v4(),
        dailyLogId: _dailyLogId!,
        elementName: row.elementCtrl.text.trim(),
        concreteGrade: row.gradeCtrl.text.trim(),
        volumeM3: double.tryParse(row.volumeCtrl.text) ?? 0.0,
        slumpMm: double.tryParse(row.slumpCtrl.text),
        cubesCast: int.tryParse(row.cubesCtrl.text) ?? 0,
        batchTicketNo: row.batchCtrl.text.trim().isEmpty
            ? null
            : row.batchCtrl.text.trim(),
      );
      await _db.insertConcretePour(pour);
    }
  }

  Future<void> _saveAll() async {
    await _saveMaterialLogs();
    await _saveEquipmentLogs();
    await _saveActivityDiesel();
    await _saveConcretePours();
    GoogleSheetsService.autoSyncSite(widget.siteId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All logs saved successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Material & Equipment — ${widget.siteName}',
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'Material Stock'),
            Tab(icon: Icon(Icons.local_gas_station), text: 'Equipment Dip'),
            Tab(icon: Icon(Icons.grain), text: 'Concrete Pour'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAll,
            tooltip: 'Save All',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMaterialTab(),
                _buildEquipmentTab(),
                _buildConcretePourTab(),
              ],
            ),
    );
  }

  Widget _buildMaterialTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildReinforcementSummaryCard(),
          const SizedBox(height: 4),
          ..._materialItems.map((item) {
            final name = item['name']!;
            final isDiesel = name == 'Diesel';
            final closing = _computedClosing(name);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: Colors.blue.shade800,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          item['unit']!,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumberField(_matOpen[name]!, 'Opening'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildNumberField(_matRecv[name]!, 'Received'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: isDiesel
                              ? _buildComputedField(
                                  'Issued (auto)',
                                  _dieselIssuedComputed(),
                                )
                              : _buildNumberField(_matIssue[name]!, 'Issued'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildComputedField('Closing', closing),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildReinforcementSummaryCard() {
    final rebarItems = _materialItems
        .where((i) => i['name']!.contains('Rebar'))
        .toList();
    double openTotal = 0, recvTotal = 0, issueTotal = 0, closeTotal = 0;
    for (final item in rebarItems) {
      final name = item['name']!;
      openTotal += _num(_matOpen[name]!);
      recvTotal += _num(_matRecv[name]!);
      issueTotal += _num(_matIssue[name]!);
      closeTotal += _computedClosing(name);
    }
    return Card(
      color: Colors.indigo.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.construction, color: Colors.indigo.shade800),
                const SizedBox(width: 8),
                const Text(
                  'Reinforcement Summary (All Rebar Sizes)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _summaryStat('Opening', openTotal),
                _summaryStat('Received', recvTotal),
                _summaryStat('Issued', issueTotal),
                _summaryStat('Closing', closeTotal, emphasize: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDieselSummaryCard() {
    final opening = _num(_matOpen['Diesel']!);
    final received = _num(_matRecv['Diesel']!);
    final issuedMachines = _eqDiesel.values.fold<double>(
      0.0,
      (s, c) => s + _num(c),
    );
    final issuedActivities = _activityRows.fold<double>(
      0.0,
      (s, r) => s + _num(r.litresCtrl),
    );
    final balance = opening + received - issuedMachines - issuedActivities;
    return Card(
      color: Colors.orange.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_gas_station, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                const Text(
                  'Diesel General Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _summaryStat('Opening', opening),
                _summaryStat('Received', received),
                _summaryStat('To Machines', issuedMachines),
                _summaryStat('To Activities', issuedActivities),
                _summaryStat('Balance', balance, emphasize: true),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Opening/Received are set on the Material Stock tab. Balance = Opening + Received − (Issued to Machines + Issued to Activities).',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(String label, double value, {bool emphasize = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 2),
        Text(
          value.toStringAsFixed(1),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: emphasize ? 16 : 14,
            color: emphasize ? Colors.indigo.shade900 : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildEquipmentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildDieselSummaryCard(),
          const SizedBox(height: 4),
          ..._equipmentNames.map((name) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumberField(
                            _eqOpen[name]!,
                            'Open Dip (cm)',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildNumberField(
                            _eqClose[name]!,
                            'Close Dip (cm)',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumberField(
                            _eqDiesel[name]!,
                            'Diesel Issued (L)',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildNumberField(
                            _eqOil[name]!,
                            'Engine Oil (L)',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.local_gas_station, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Diesel Issued to Activities (non-dipped)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addActivityRow,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          ..._activityRows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: row.nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Activity / Machine',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _buildNumberField(row.litresCtrl, 'Litres')),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeActivityRow(i),
                  ),
                ],
              ),
            );
          }),
          if (_activityRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No diesel issued directly to activities today.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConcretePourTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grain, color: Colors.brown.shade700),
              const SizedBox(width: 8),
              const Text(
                'Concrete Pour & Quality Control',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addConcreteRow,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Log each element poured today — e.g. Abutment Wall, Grade C30, 12.5m³.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          ..._concreteRows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: row.elementCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Element (e.g. Abutment Wall)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeConcreteRow(i),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: row.gradeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Grade (e.g. C25)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildNumberField(
                            row.volumeCtrl,
                            'Volume (m³)',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumberField(row.slumpCtrl, 'Slump (mm)'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildNumberField(row.cubesCtrl, 'Cubes Cast'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: row.batchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Batch Ticket No',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (_concreteRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No concrete pours logged for today yet.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNumberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }

  /// Read-only display for a value the app computes for the user — never
  /// a text field, so it can't be hand-edited out of sync with its inputs.
  Widget _buildComputedField(String label, double value) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: true,
        fillColor: Colors.grey.shade100,
      ),
      child: Text(
        value.toStringAsFixed(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _matOpen.values) c.dispose();
    for (final c in _matRecv.values) c.dispose();
    for (final c in _matIssue.values) c.dispose();
    for (final c in _eqOpen.values) c.dispose();
    for (final c in _eqClose.values) c.dispose();
    for (final c in _eqDiesel.values) c.dispose();
    for (final c in _eqOil.values) c.dispose();
    for (final row in _activityRows) row.dispose();
    for (final row in _concreteRows) row.dispose();
    super.dispose();
  }
}
