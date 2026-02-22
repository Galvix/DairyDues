// lib/screens/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _yieldCtrl;
  late TextEditingController _toleranceCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppProvider>();
    _yieldCtrl = TextEditingController(text: p.yieldRatio.toString());
    _toleranceCtrl = TextEditingController(text: p.toleranceKg.toString());
  }

  @override
  void dispose() {
    _yieldCtrl.dispose();
    _toleranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Paneer Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Update when milk yield changes by season',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _yieldCtrl,
                  decoration: InputDecoration(
                    labelText: 'Yield Ratio',
                    helperText: 'Current: ${(provider.yieldRatio * 100).toStringAsFixed(1)}% — e.g. 0.18 = 180g paneer per kg milk',
                    suffixText: 'ratio',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}'))],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _toleranceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tolerance (kg)',
                    helperText: 'Max gap allowed before milk is reduced',
                    suffixText: 'kg',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Settings'),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.blue.withOpacity(0.04),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Text('Paneer Validation Logic',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ]),
                const SizedBox(height: 10),
                _Bullet('Expected paneer = Total milk × Yield ratio'),
                _Bullet('If gap ≤ tolerance → full milk billable, no change'),
                _Bullet('If gap > tolerance → billable milk = Actual paneer ÷ Ratio'),
                _Bullet('Reduction shared proportionally across all milkmen that day'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.water_drop, color: AppTheme.primary),
              title: const Text('Hisaab — Dairy Manager'),
              subtitle: const Text('Version 2.0 • Firebase Edition'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final ratio = double.tryParse(_yieldCtrl.text);
    final tolerance = double.tryParse(_toleranceCtrl.text);

    if (ratio == null || ratio <= 0 || ratio >= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yield ratio must be between 0 and 1 (e.g. 0.18)')),
      );
      return;
    }
    if (tolerance == null || tolerance < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tolerance must be 0 or more')),
      );
      return;
    }

    setState(() => _saving = true);
    final p = context.read<AppProvider>();
    await p.updateYieldRatio(ratio);
    await p.updateToleranceKg(tolerance);
    setState(() => _saving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved ✓'), backgroundColor: AppTheme.success),
      );
    }
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• ', style: TextStyle(color: Colors.blue)),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}
