// lib/screens/paneer/paneer_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../database/models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/payment_calculator.dart';

class PaneerScreen extends StatefulWidget {
  const PaneerScreen({super.key});

  @override
  State<PaneerScreen> createState() => _PaneerScreenState();
}

class _PaneerScreenState extends State<PaneerScreen> {
  final _actualCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _actualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final db = provider.db;
    final dateOnly = DateTime(_date.year, _date.month, _date.day);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paneer Entry'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final p = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now());
              if (p != null) setState(() => _date = p);
            },
            icon: const Icon(Icons.calendar_today, color: Colors.white, size: 16),
            label: Text(DateFormat('dd MMM').format(_date),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Milk summary for the day
          StreamBuilder<List<MilkDelivery>>(
            stream: db.watchDeliveriesForDate(dateOnly),
            builder: (context, snap) {
              final deliveries = snap.data ?? [];
              final totalMilk = deliveries.fold<double>(0.0, (s, d) => s + d.netMilk);
              final expectedPaneer = totalMilk * provider.yieldRatio;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Milk Summary — ${DateFormat('dd MMM yyyy').format(_date)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 12),
                    _InfoRow('Total milk received', '${totalMilk.toStringAsFixed(2)} kg'),
                    _InfoRow('Yield ratio', '${(provider.yieldRatio * 100).toStringAsFixed(1)}%'),
                    _InfoRow('Expected paneer', '${expectedPaneer.toStringAsFixed(2)} kg'),
                    _InfoRow('Tolerance', '±${provider.toleranceKg} kg'),
                    if (deliveries.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(children: [
                          Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 16),
                          SizedBox(width: 8),
                          Text('No milk entries for this date',
                              style: TextStyle(color: Colors.orange, fontSize: 13)),
                        ]),
                      ),
                    // Live preview
                    if (double.tryParse(_actualCtrl.text) != null && totalMilk > 0) ...[
                      const SizedBox(height: 12),
                      Builder(builder: (_) {
                        final v = PaneerValidation.validate(
                          netMilkTotal: totalMilk,
                          actualPaneer: double.parse(_actualCtrl.text),
                          yieldRatio: provider.yieldRatio,
                          toleranceKg: provider.toleranceKg,
                        );
                        return _ValidationBanner(v: v);
                      }),
                    ],
                  ]),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Entry or already-done
          FutureBuilder<PaneerEntry?>(
            future: db.getPaneerEntryForDate(dateOnly),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final existing = snap.data;
              if (existing != null) return _DoneCard(entry: existing);

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Enter Actual Paneer',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 12),
                    StatefulBuilder(
                      builder: (_, set) => TextFormField(
                        controller: _actualCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Actual Paneer Weight (kg)', suffixText: 'kg'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: _saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Confirm & Save'),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),

          const SizedBox(height: 16),
          const SectionHeader(title: 'RECENT HISTORY'),
          StreamBuilder<List<PaneerEntry>>(
            stream: db.watchRecentPaneerEntries(limit: 15),
            builder: (context, snap) {
              final entries = snap.data ?? [];
              return Column(
                children: entries
                    .map((e) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              e.adjustmentApplied ? Icons.warning_amber_outlined : Icons.check_circle_outline,
                              color: e.adjustmentApplied ? AppTheme.warning : AppTheme.success,
                            ),
                            title: Text(DateFormat('dd MMM yyyy').format(e.entryDate)),
                            subtitle: Text(
                                'Milk: ${e.totalMilkUsed.toStringAsFixed(1)} kg  •  Paneer: ${e.actualPaneer.toStringAsFixed(1)} kg'),
                            trailing: e.adjustmentApplied
                                ? Chip(
                                    label: Text('Adjusted',
                                        style: TextStyle(fontSize: 11, color: AppTheme.warning)),
                                    backgroundColor: AppTheme.warning.withOpacity(0.1),
                                  )
                                : null,
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    final actual = double.tryParse(_actualCtrl.text);
    if (actual == null) return;
    setState(() => _saving = true);

    final date = DateTime(_date.year, _date.month, _date.day);
    final v = await context.read<AppProvider>().validateAndSavePaneer(
        date: date, actualPaneer: actual);
    if (!mounted) return;
    setState(() => _saving = false);
    _actualCtrl.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(v.adjustmentNeeded ? Icons.warning_amber : Icons.check_circle,
              color: v.adjustmentNeeded ? AppTheme.warning : AppTheme.success),
          const SizedBox(width: 8),
          Text(v.adjustmentNeeded ? 'Adjustment Applied' : 'Within Tolerance'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _InfoRow('Expected', '${v.expectedPaneer.toStringAsFixed(2)} kg'),
          _InfoRow('Actual', '${v.actualPaneer.toStringAsFixed(2)} kg'),
          _InfoRow('Gap', '${v.gap.toStringAsFixed(2)} kg'),
          if (v.adjustmentNeeded) ...[
            const Divider(),
            Text('Milk reduced by ${v.milkReduction.toStringAsFixed(2)} kg',
                style: TextStyle(color: AppTheme.warning)),
          ],
        ]),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
        ],
      ),
    );
  }
}

class _ValidationBanner extends StatelessWidget {
  final PaneerValidation v;
  const _ValidationBanner({required this.v});

  @override
  Widget build(BuildContext context) {
    final ok = !v.adjustmentNeeded;
    final color = ok ? AppTheme.success : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
              color: color, size: 16),
          const SizedBox(width: 6),
          Text(ok ? 'Within tolerance' : 'Adjustment will be applied',
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        if (!ok) ...[
          const SizedBox(height: 4),
          Text('Gap: ${v.gap.toStringAsFixed(2)} kg  •  Milk reduces by ${v.milkReduction.toStringAsFixed(2)} kg',
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ]),
    );
  }
}

class _DoneCard extends StatelessWidget {
  final PaneerEntry entry;
  const _DoneCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.success.withOpacity(0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.success.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(entry.adjustmentApplied ? Icons.warning_amber : Icons.check_circle,
                color: entry.adjustmentApplied ? AppTheme.warning : AppTheme.success),
            const SizedBox(width: 8),
            const Text('Paneer recorded for this date',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          _InfoRow('Total milk', '${entry.totalMilkUsed.toStringAsFixed(2)} kg'),
          _InfoRow('Expected paneer', '${entry.expectedPaneer.toStringAsFixed(2)} kg'),
          _InfoRow('Actual paneer', '${entry.actualPaneer.toStringAsFixed(2)} kg'),
          if (entry.adjustmentApplied)
            _InfoRow('Adjusted milk', '${(entry.adjustedMilkTotal ?? 0).toStringAsFixed(2)} kg',
                valueColor: AppTheme.warning),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor ?? Colors.black87,
                fontSize: 13)),
      ]),
    );
  }
}
