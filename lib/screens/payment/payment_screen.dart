// lib/screens/payment/payment_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/payment_calculator.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  DateTime _weekStart = DateHelpers.getWeekStart(DateTime.now());
  bool _loading = false;
  String? _error;
  List<WeeklyPaymentSummary> _summaries = [];

  @override
  void initState() {
    super.initState();
    // FIX: Use post-frame callback instead of didChangeDependencies
    // This prevents infinite reload loops caused by context.read triggering rebuilds
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // FIX: REMOVED didChangeDependencies — it was causing infinite loading loops
  // because every _load() -> setState() -> rebuild -> didChangeDependencies -> _load()

  Future<void> _load() async {
    if (!mounted || _loading) return; // FIX: guard against re-entry
    setState(() { _loading = true; _error = null; });

    try {
      final provider = context.read<AppProvider>();
      final summaries = await provider.calculateWeeklyPayments(_weekStart);
      if (mounted) setState(() { _summaries = summaries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _changeWeek(int direction) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * direction));
      _summaries = [];
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _summaries.fold<double>(0.0, (s, x) => s + x.netPayable);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Payment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export all PDF',
            onPressed: _summaries.isEmpty ? null : _exportAllPdf,
          ),
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Export Excel',
            onPressed: _summaries.isEmpty ? null : _exportExcel,
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: AppTheme.primary.withOpacity(0.06),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _loading ? null : () => _changeWeek(-1),
            ),
            Expanded(
              child: Column(children: [
                Text(DateHelpers.formatWeekRange(_weekStart),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    textAlign: TextAlign.center),
                Text('Total: ${DateHelpers.formatCurrency(total)}',
                    style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _loading || _weekStart.isAfter(DateTime.now().subtract(const Duration(days: 7)))
                  ? null
                  : () => _changeWeek(1),
            ),
          ]),
        ),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading payment data...', style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text('Failed to load payments',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    if (_summaries.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.payments_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No data for this week', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text('Add milkmen and milk entries first',
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: _summaries.length,
      itemBuilder: (_, i) => _PayCard(
        summary: _summaries[i],
        weekStart: _weekStart,
        onMarkPaid: () => _markPaid(i),
        onPrint: () => _printSlip(_summaries[i]),
      ),
    );
  }

  Future<void> _markPaid(int i) async {
    try {
      final db = context.read<AppProvider>().db;
      final s = _summaries[i];
      final payment = await db.getPaymentForWeek(s.milkmanId, _weekStart);
      if (payment != null) {
        await db.markPaymentPaid(payment.id);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printSlip(WeeklyPaymentSummary s) async {
    final bytes = await _buildPdf([s]);
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  Future<void> _exportAllPdf() async {
    final bytes = await _buildPdf(_summaries);
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  Future<Uint8List> _buildPdf(List<WeeklyPaymentSummary> list) async {
    final pdf = pw.Document();
    for (final s in list) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('DAIRY PAYMENT SLIP',
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text(DateHelpers.formatWeekRange(_weekStart),
                style: const pw.TextStyle(fontSize: 10)),
          ]),
          pw.Divider(thickness: 1.5),
          pw.SizedBox(height: 6),
          pw.Text(s.milkmanName,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 14),
          _pRow('Milk', '${s.totalMilkKg.toStringAsFixed(2)} kg x ${s.milkRate.toStringAsFixed(2)}/kg'),
          _pRow('Milk Earnings', DateHelpers.formatCurrency(s.milkEarnings)),
          if (s.totalKhoyaKg > 0) _pRow('Khoya', '${s.totalKhoyaKg.toStringAsFixed(2)} kg x ${s.khoyaRate.toStringAsFixed(2)}/kg'),
          if (s.totalKhoyaKg > 0) _pRow('Khoya Earnings', DateHelpers.formatCurrency(s.khoyaEarnings)),
          pw.Divider(),
          _pRow('Total Earnings', DateHelpers.formatCurrency(s.totalEarnings), bold: true),
          if (s.carriedOverLoan > 0) _pRow('Carried Over Loan', '- ${DateHelpers.formatCurrency(s.carriedOverLoan)}', valueColor: PdfColors.red),
          if (s.thisWeekLoans > 0) _pRow('This Week Loans', '- ${DateHelpers.formatCurrency(s.thisWeekLoans)}', valueColor: PdfColors.red),
          pw.Divider(thickness: 1.5),
          _pRow('NET PAYABLE', DateHelpers.formatCurrency(s.netPayable), bold: true, fontSize: 14, valueColor: PdfColors.green800),
          if (s.loanCarryForward > 0) _pRow('Loan Carry Forward', DateHelpers.formatCurrency(s.loanCarryForward), valueColor: PdfColors.orange),
          pw.SizedBox(height: 28),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            _signLine('Receiver Signature'),
            _signLine('Factory Signature'),
          ]),
        ]),
      ));
    }
    return pdf.save();
  }

  pw.Widget _pRow(String label, String value,
      {bool bold = false, double fontSize = 12, PdfColor? valueColor}) {
    final style = bold
        ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize)
        : pw.TextStyle(fontSize: fontSize);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: style),
        pw.Text(value,
            style: pw.TextStyle(
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                fontSize: fontSize,
                color: valueColor)),
      ]),
    );
  }

  pw.Widget _signLine(String label) => pw.Column(children: [
        pw.Container(width: 110, height: 1, color: PdfColors.black),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ]);

  Future<void> _exportExcel() async {
    final excelFile = xl.Excel.createExcel();
    final sheet = excelFile['Week ${DateFormat('dd-MM-yyyy').format(_weekStart)}'];

    final headers = [
      'Milkman', 'Milk kg', 'Milk Rate', 'Milk Earnings',
      'Khoya kg', 'Khoya Rate', 'Khoya Earnings',
      'Total Earnings', 'This Week Loans', 'Carried Over',
      'Total Deducted', 'Net Payable', 'Carry Forward',
    ];
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
          xl.TextCellValue(headers[i]);
    }
    for (var r = 0; r < _summaries.length; r++) {
      final s = _summaries[r];
      final row = [
        s.milkmanName, s.totalMilkKg, s.milkRate, s.milkEarnings,
        s.totalKhoyaKg, s.khoyaRate, s.khoyaEarnings,
        s.totalEarnings, s.thisWeekLoans, s.carriedOverLoan,
        s.totalLoanDeducted, s.netPayable, s.loanCarryForward,
      ];
      for (var c = 0; c < row.length; c++) {
        final v = row[c];
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value =
            v is String ? xl.TextCellValue(v) : xl.DoubleCellValue(v as double);
      }
    }

    final bytes = excelFile.save();
    if (bytes == null) return;

    final filename = 'payment_${DateFormat('dd-MM-yyyy').format(_weekStart)}.xlsx';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: filename);
    } else {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved: ${file.path}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

class _PayCard extends StatelessWidget {
  final WeeklyPaymentSummary summary;
  final DateTime weekStart;
  final VoidCallback onMarkPaid;
  final VoidCallback onPrint;

  const _PayCard({
    required this.summary,
    required this.weekStart,
    required this.onMarkPaid,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: AppTheme.primary.withOpacity(0.12),
              child: Text(s.milkmanName[0],
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(s.milkmanName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.primary),
              onPressed: onPrint,
            ),
          ]),
          const Divider(height: 20),
          _Row('Milk',
              '${s.totalMilkKg.toStringAsFixed(2)} kg x ${s.milkRate.toStringAsFixed(2)}',
              DateHelpers.formatCurrency(s.milkEarnings)),
          if (s.totalKhoyaKg > 0)
            _Row('Khoya',
                '${s.totalKhoyaKg.toStringAsFixed(2)} kg x ${s.khoyaRate.toStringAsFixed(2)}',
                DateHelpers.formatCurrency(s.khoyaEarnings)),
          const SizedBox(height: 4),
          _Row('Total Earnings', '', DateHelpers.formatCurrency(s.totalEarnings), bold: true),
          if (s.carriedOverLoan > 0)
            _DeductRow('Carried Over Loan', s.carriedOverLoan),
          if (s.thisWeekLoans > 0)
            _DeductRow('This Week Loans', s.thisWeekLoans),
          const Divider(),
          Row(children: [
            const Expanded(
                child: Text('NET PAYABLE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Text(DateHelpers.formatCurrency(s.netPayable),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.success)),
          ]),
          if (s.loanCarryForward > 0)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.arrow_forward, size: 14, color: AppTheme.warning),
                const SizedBox(width: 6),
                Text('Carry forward: ${DateHelpers.formatCurrency(s.loanCarryForward)}',
                    style: TextStyle(color: AppTheme.warning, fontSize: 12)),
              ]),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onMarkPaid,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark as Paid'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String sub;
  final String value;
  final bool bold;
  const _Row(this.label, this.sub, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label,
            style: TextStyle(
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: Colors.grey[800])),
        if (sub.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
        const Spacer(),
        Text(value,
            style:
                TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }
}

class _DeductRow extends StatelessWidget {
  final String label;
  final double amount;
  const _DeductRow(this.label, this.amount);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(Icons.remove_circle_outline, size: 14, color: Colors.red[400]),
        const SizedBox(width: 6),
        Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 13))),
        Text('- ${DateHelpers.formatCurrency(amount)}',
            style: TextStyle(color: Colors.red[500], fontSize: 13)),
      ]),
    );
  }
}
