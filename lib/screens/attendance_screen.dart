import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/worker.dart';
import '../models/attendance.dart';
import '../models/daily_log.dart';
import '../services/google_sheets_service.dart';

/// Daily crew attendance for a site. Auto-creates a [DailyLog] for today
/// if one does not yet exist so attendance always has a log to attach to.
class AttendanceScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const AttendanceScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _db = DatabaseHelper.instance;
  List<Worker> _workers = [];
  Map<String, AttendanceStatus> _attendanceStatus = {};
  Map<String, String> _attendanceId = {};
  String? _dailyLogId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
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

    final activeWorkers = await _db.getWorkersForSite(widget.siteId);
    final existingAttendance = await _db.getAttendanceForLog(_dailyLogId!);

    setState(() {
      _workers = activeWorkers;
      for (final att in existingAttendance) {
        _attendanceStatus[att.workerId] = att.status;
        _attendanceId[att.workerId] = att.id;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveAttendance() async {
    if (_dailyLogId == null) return;

    final records = <Attendance>[];
    for (final worker in _workers) {
      final status = _attendanceStatus[worker.id] ?? AttendanceStatus.present;
      records.add(
        Attendance(
          id: _attendanceId[worker.id] ?? const Uuid().v4(),
          dailyLogId: _dailyLogId!,
          workerId: worker.id,
          status: status,
        ),
      );
    }

    await _db.bulkUpsertAttendance(records);
    GoogleSheetsService.autoSyncSite(widget.siteId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance saved successfully')),
      );
    }
  }

  Future<void> _addCasualArtisan() async {
    final nameController = TextEditingController();
    String role = kCommonWorkerRoles.first;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Casual Artisan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: kCommonWorkerRoles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setDialogState(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final worker = Worker(
        id: const Uuid().v4(),
        siteId: widget.siteId,
        name: nameController.text.trim(),
        role: role,
      );
      await _db.insertWorker(worker);
      setState(() => _workers.add(worker));
    }
  }

  Color _statusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green;
      case AttendanceStatus.halfDay:
        return Colors.orange;
      case AttendanceStatus.absent:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Crew Attendance — ${widget.siteName}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _addCasualArtisan,
            tooltip: 'Add Casual Artisan',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAttendance,
            tooltip: 'Save Attendance',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _workers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No workers on roster'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _addCasualArtisan,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add First Worker'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _workers.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final worker = _workers[index];
                final status =
                    _attendanceStatus[worker.id] ?? AttendanceStatus.present;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: _statusColor(status)
                                  .withOpacity(0.2),
                              child: Text(worker.name[0]),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    worker.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    worker.role,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _statusColor(status)),
                              ),
                              child: Text(
                                status.label,
                                style: TextStyle(
                                  color: _statusColor(status),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: AttendanceStatus.values.map((s) {
                            final isSelected = status == s;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: isSelected
                                        ? _statusColor(s)
                                        : Colors.grey.shade200,
                                    foregroundColor: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  onPressed: () => setState(
                                    () => _attendanceStatus[worker.id] = s,
                                  ),
                                  child: Text(s.label),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
