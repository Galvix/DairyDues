// lib/providers/app_provider.dart
import 'package:flutter/foundation.dart';
import '../database/firestore_service.dart';
import '../database/models.dart';
import '../utils/payment_calculator.dart';

class AppProvider extends ChangeNotifier {
  final FirestoreService db;

  AppProvider(this.db);

  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  double _yieldRatio = 0.18;
  double _toleranceKg = 0.5;

  double get yieldRatio => _yieldRatio;
  double get toleranceKg => _toleranceKg;

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  DateTime get currentWeekStart => DateHelpers.getWeekStart(DateTime.now());

  Future<void> loadSettings() async {
    _yieldRatio = await db.getYieldRatio();
    _toleranceKg = await db.getToleranceKg();
    notifyListeners();
  }

  Future<void> updateYieldRatio(double value) async {
    await db.setSetting('paneer_yield_ratio', value);
    _yieldRatio = value;
    notifyListeners();
  }

  Future<void> updateToleranceKg(double value) async {
    await db.setSetting('paneer_tolerance_kg', value);
    _toleranceKg = value;
    notifyListeners();
  }

  // ─── MILK ENTRY ───────────────────────────────────────────────────────────

  Future<void> addMilkDelivery({
    required String milkmanId,
    required DateTime deliveryDate,
    required double grossWeight,
    required double canWeight,
    String notes = '',
  }) async {
    final netMilk = grossWeight - canWeight;
    await db.addMilkDelivery(MilkDelivery(
      id: '',
      milkmanId: milkmanId,
      deliveryDate: deliveryDate,
      grossWeight: grossWeight,
      canWeight: canWeight,
      netMilk: netMilk,
      billableMilk: netMilk,
      notes: notes,
    ));
  }

  // ─── PANEER VALIDATION ────────────────────────────────────────────────────

  Future<PaneerValidation> validateAndSavePaneer({
    required DateTime date,
    required double actualPaneer,
  }) async {
    final deliveries = await db.getAllDeliveriesForDate(date);
    final totalMilk =
        deliveries.fold<double>(0.0, (s, d) => s + d.netMilk);

    final validation = PaneerValidation.validate(
      netMilkTotal: totalMilk,
      actualPaneer: actualPaneer,
      yieldRatio: _yieldRatio,
      toleranceKg: _toleranceKg,
    );

    await db.addPaneerEntry(PaneerEntry(
      id: '',
      entryDate: date,
      totalMilkUsed: totalMilk,
      expectedPaneer: validation.expectedPaneer,
      actualPaneer: actualPaneer,
      yieldRatio: _yieldRatio,
      toleranceKg: _toleranceKg,
      adjustmentApplied: validation.adjustmentNeeded,
      adjustedMilkTotal:
          validation.adjustmentNeeded ? validation.adjustedMilkTotal : null,
    ));

    if (validation.adjustmentNeeded) {
      await db.applyPaneerAdjustment(date, validation.adjustedMilkTotal);
    }

    return validation;
  }

  // ─── WEEKLY PAYMENT ───────────────────────────────────────────────────────

  Future<List<WeeklyPaymentSummary>> calculateWeeklyPayments(
      DateTime weekStart) async {
    final milkmen = await db.getActiveMilkmen();
    final summaries = <WeeklyPaymentSummary>[];

    for (final m in milkmen) {
      final deliveries = await db.getDeliveriesForWeek(m.id, weekStart);
      final totalMilk =
          deliveries.fold<double>(0.0, (s, d) => s + d.billableMilk);
      final totalKhoya = await db.getTotalKhoyaForWeek(m.id, weekStart);
      final thisWeekLoans = await db.getTotalLoansForWeek(m.id, weekStart);
      final carriedOver = await db.getCarriedOverLoan(m.id, weekStart);

      final summary = WeeklyPaymentSummary.calculate(
        milkmanId: m.id,
        milkmanName: m.name,
        milkRate: m.milkRate,
        khoyaRate: m.khoyaRate,
        totalMilkKg: totalMilk,
        totalKhoyaKg: totalKhoya,
        thisWeekLoans: thisWeekLoans,
        carriedOverLoan: carriedOver,
      );

      summaries.add(summary);

      final existing = await db.getPaymentForWeek(m.id, weekStart);
      if (existing == null || !existing.isPaid) {
        await db.upsertWeeklyPayment(WeeklyPayment(
          id: '',
          milkmanId: m.id,
          weekStartDate: weekStart,
          weekEndDate: DateHelpers.getWeekEnd(weekStart),
          totalMilkKg: totalMilk,
          milkEarnings: summary.milkEarnings,
          totalKhoyaKg: totalKhoya,
          khoyaEarnings: summary.khoyaEarnings,
          totalEarnings: summary.totalEarnings,
          loanDeducted: summary.totalLoanDeducted,
          carriedOverLoan: carriedOver,
          netPayable: summary.netPayable,
          loanCarryForward: summary.loanCarryForward,
        ));
      }
    }

    return summaries;
  }
}
