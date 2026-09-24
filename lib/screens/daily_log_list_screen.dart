import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/site.dart';
import 'daily_log_detail_screen.dart';

/// Dedicated scrollable list of all daily logs for a single site.
class DailyLogListScreen extends StatefulWidget {
  final Site site;

  const DailyLogListScreen({super.key, required this.site});

  @override
  State<DailyLogListScreen> createState() => _DailyLogListScreenState();
}

class _DailyLogListScreenState extends State<DailyLogListScreen> {
  final _db = DatabaseHelper.instance;
  List<DailyLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _db.getLogsForSite(widget.site.id);
    setState(() => _logs = data);
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Daily Logs — ${widget.site.name}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _logs.isEmpty
          ? const Center(child: Text('No daily logs found'))
          : ListView.builder(
              itemCount: _logs.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final log = _logs[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade800,
                      child: const Icon(Icons.assignment, color: Colors.white),
                    ),
                    title: Text(
                      dateFmt.format(log.date),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      log.workCompleted?.isNotEmpty == true
                          ? log.workCompleted!.split('\n').first
                          : 'No work description',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            DailyLogDetailScreen(log: log, site: widget.site),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
