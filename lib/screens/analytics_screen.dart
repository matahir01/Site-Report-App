import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/reporting_models.dart';
import '../services/reporting_service.dart';
import '../utils/currency_formatter.dart';

class AnalyticsScreen extends StatefulWidget {
  final String siteId;
  final String siteName;

  const AnalyticsScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static const _colors = <Color>[
    Color(0xFF123B64),
    Color(0xFF00897B),
    Color(0xFFE09F3E),
    Color(0xFFC44536),
    Color(0xFF6A4C93),
    Color(0xFF2A9D8F),
    Color(0xFFF77F00),
    Color(0xFF4361EE),
    Color(0xFFD45087),
    Color(0xFF4D908E),
  ];

  DashboardSnapshot? _snapshot;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await ReportingService.dashboard(widget.siteId);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Executive Dashboard — ${widget.siteName}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              setState(() {
                _snapshot = null;
                _error = null;
              });
              _load();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Could not load analytics: $_error'))
          : _snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : _DashboardBody(snapshot: _snapshot!, colors: _colors),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final DashboardSnapshot snapshot;
  final List<Color> colors;

  const _DashboardBody({required this.snapshot, required this.colors});

  @override
  Widget build(BuildContext context) {
    final highest = snapshot.highestCostCategory;
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 5
                  : constraints.maxWidth >= 560
                  ? 3
                  : 2;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 2 ? 1.35 : 1.25,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _KpiCard(
                    label: 'Total site spend',
                    value: CurrencyFormatter.formatCompact(snapshot.totalSpend),
                    icon: Icons.payments_outlined,
                    color: Colors.red.shade700,
                  ),
                  _KpiCard(
                    label: 'Float received',
                    value: CurrencyFormatter.formatCompact(
                      snapshot.totalFloatReceived,
                    ),
                    icon: Icons.account_balance_wallet_outlined,
                    color: Colors.green.shade700,
                  ),
                  _KpiCard(
                    label: 'Current cash balance',
                    value: CurrencyFormatter.formatCompact(
                      snapshot.currentCashBalance,
                    ),
                    icon: Icons.savings_outlined,
                    color: snapshot.currentCashBalance < 0
                        ? Colors.orange.shade800
                        : Colors.blue.shade800,
                  ),
                  _KpiCard(
                    label: 'Highest cost category',
                    value: highest == null
                        ? 'No spend yet'
                        : '${highest.label}\n${snapshot.highestCostCategoryPercentage.toStringAsFixed(1)}%',
                    icon: Icons.trending_up,
                    color: Colors.deepPurple,
                  ),
                  _KpiCard(
                    label: 'Average daily spend',
                    value:
                        '${CurrencyFormatter.formatCompact(snapshot.averageDailySpend)}/day',
                    icon: Icons.calendar_today_outlined,
                    color: Colors.teal.shade700,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _ChartCard(
            title: 'Expense breakdown by category',
            subtitle: 'Start-to-date share and total amount',
            child: _CategoryDonut(snapshot: snapshot, colors: colors),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Monthly spend',
            subtitle: 'Total expense by YYYY-MM',
            child: _MonthlyBar(snapshot: snapshot),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Category trends over time',
            subtitle: 'Monthly spend by expense category',
            child: _CategoryTrend(snapshot: snapshot, colors: colors),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const Spacer(),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _CategoryDonut extends StatelessWidget {
  final DashboardSnapshot snapshot;
  final List<Color> colors;

  const _CategoryDonut({required this.snapshot, required this.colors});

  @override
  Widget build(BuildContext context) {
    final entries = snapshot.categoryTotals.entries
        .where((entry) => entry.value > 0)
        .toList();
    if (entries.isEmpty) return const _NoData();
    return Column(
      children: [
        SizedBox(
          height: 250,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 56,
              sectionsSpace: 2,
              sections: entries.asMap().entries.map((indexed) {
                final percent = indexed.value.value / snapshot.totalSpend * 100;
                return PieChartSectionData(
                  value: indexed.value.value,
                  color: colors[indexed.key % colors.length],
                  radius: 72,
                  title: '${percent.toStringAsFixed(1)}%',
                  titleStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: entries.asMap().entries.map((indexed) {
            return _LegendItem(
              color: colors[indexed.key % colors.length],
              label:
                  '${indexed.value.key.label}: ${CurrencyFormatter.formatCompact(indexed.value.value)}',
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _MonthlyBar extends StatelessWidget {
  final DashboardSnapshot snapshot;

  const _MonthlyBar({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final entries = snapshot.monthlyTotals.entries.toList();
    if (entries.isEmpty) return const _NoData();
    return SizedBox(
      height: 280,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 54),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= entries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entries[index].key,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: entries.asMap().entries.map((indexed) {
            return BarChartGroupData(
              x: indexed.key,
              barRods: [
                BarChartRodData(
                  toY: indexed.value.value,
                  width: 22,
                  color: const Color(0xFF123B64),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _CategoryTrend extends StatelessWidget {
  final DashboardSnapshot snapshot;
  final List<Color> colors;

  const _CategoryTrend({required this.snapshot, required this.colors});

  @override
  Widget build(BuildContext context) {
    final months = snapshot.monthlyCategoryTotals.keys.toList();
    final categories = ExpenseCategory.values
        .where(
          (category) => months.any(
            (month) =>
                (snapshot.monthlyCategoryTotals[month]?[category] ?? 0) > 0,
          ),
        )
        .toList();
    if (months.isEmpty || categories.isEmpty) return const _NoData();
    return Column(
      children: [
        SizedBox(
          height: 300,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true),
              borderData: FlBorderData(show: true),
              titlesData: FlTitlesData(
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 54),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= months.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          months[index],
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: categories.asMap().entries.map((indexed) {
                return LineChartBarData(
                  color: colors[indexed.value.index % colors.length],
                  barWidth: 3,
                  isCurved: false,
                  dotData: FlDotData(show: true),
                  spots: months.asMap().entries.map((month) {
                    return FlSpot(
                      month.key.toDouble(),
                      snapshot.monthlyCategoryTotals[month.value]?[indexed
                              .value] ??
                          0,
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: categories
              .map(
                (category) => _LegendItem(
                  color: colors[category.index % colors.length],
                  label: category.label,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 180,
    child: Center(child: Text('No expense data for this site yet.')),
  );
}
