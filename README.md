# 🥛 Hisaab — Dairy Manager (Firebase Edition)

Complete dairy financial management app using **Firebase Firestore** as the database.
No SQLite, no build_runner, no code generation — just clean Flutter + Firebase.

---

## 🚀 Setup (3 steps)

### Step 1 — Install dependencies
```bash
cd dairy_app
flutter pub get
```

### Step 2 — Deploy Firestore indexes
```bash
firebase deploy --only firestore:indexes
```
> This sets up the compound query indexes Firestore needs.
> If you don't have Firebase CLI: `npm install -g firebase-tools`

### Step 3 — Run
```bash
flutter run -d chrome     # Web
flutter run               # Android tablet
flutter build apk         # Release APK
flutter build web         # Release web
```

**That's it. No build_runner. No generated files.**

---

## 🔥 Firestore Structure

```
/milkmen/{id}
  name, milkRate, khoyaRate, suppliesKhoya, isActive

/deliveries/{id}
  milkmanId, deliveryDate, grossWeight, canWeight,
  netMilk, billableMilk, paneerAdjusted, notes

/khoya/{id}
  milkmanId, deliveryDate, weight, notes

/paneer/{id}
  entryDate, totalMilkUsed, expectedPaneer, actualPaneer,
  yieldRatio, toleranceKg, adjustmentApplied, adjustedMilkTotal

/loans/{id}
  milkmanId, loanDate, amount, notes

/weeklyPayments/{id}
  milkmanId, weekStartDate, weekEndDate,
  totalMilkKg, milkEarnings, totalKhoyaKg, khoyaEarnings,
  totalEarnings, loanDeducted, carriedOverLoan,
  netPayable, loanCarryForward, isPaid, paidAt

/settings/{key}
  value  (keys: paneer_yield_ratio, paneer_tolerance_kg)
```

---

## ⚙️ Business Logic

### Net Milk
```
Net Milk = Gross Weight − Empty Can Weight
```

### Paneer Validation
```
Expected = Total Milk × Yield Ratio
Gap = Expected − Actual

Gap ≤ 0.5 kg  →  No change, full milk billable
Gap > 0.5 kg  →  Billable milk = Actual Paneer ÷ Yield Ratio
                  (applied proportionally to all milkmen that day)
```

### Weekly Payment (resets Monday)
```
Earnings = (Billable Milk × Rate) + (Khoya × Khoya Rate)
Net = Earnings − This Week Loans − Carried Over Loan
If Net < 0 → Pay ₹0, carry the difference to next week
```

---

## ⚠️ Firestore Indexes

The app uses compound queries (filter by milkmanId + date range).
Firestore requires indexes for these. Two ways to create them:

**Option A — Deploy from CLI (recommended):**
```bash
firebase deploy --only firestore:indexes
```

**Option B — Let Firestore auto-create:**
Run the app, and when a query fails, Firestore will show an error in the
console with a direct link to create the missing index. Click it.

---

## 📱 Platforms
- ✅ Android tablet
- ✅ Web (Chrome)
- ✅ Windows desktop
