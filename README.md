# Civil Site Manager

Production-oriented, offline-first Flutter application for construction daily
site operations, itemized expenses, cash-float reconciliation, dashboards, and
auditable PDF/Excel reporting.

The local SQLite database is the system of record. Core field entry, analytics,
PDF generation, Excel generation, and file sharing work without a server.

## Delivered workflows

- Project and site setup with client, location, and GPS details.
- Home quick actions: **Add Expense**, **Log Daily Progress**,
  **Reconcile Float**, and **View Reports**.
- Multi-line expense entry with locked categories, quantity, unit, unit price,
  calculated line totals, receipt images, and one atomic save.
- Live cash card showing total expenses, expected closing balance, variance,
  match status, and out-of-pocket deficit warnings.
- Daily progress data for activities, manpower, material stocks, equipment dip
  readings, fuel/oil, concrete/QC, HSE, delays, next-day plans, photos, and
  document references.
- Real signature sign-off for Prepared By, Reviewed By, and Approved By. Each
  role can draw on the screen or import a PNG/JPG. The stored signature is
  previewed in the daily record and embedded in the corresponding DPR box.
- Executive dashboard with spend/float/balance KPIs, category donut, monthly
  spend bars, and monthly category trends.
- Date-range analytics with category multi-select, text/unit search, totals,
  item counts, percentages, and detailed export.
- Live category-by-month matrix.
- Fixed three-page A4 SWAS-style Daily Site Progress Report.
- Six-tab `.xlsx` audit workbook with formulas and native Excel charts.
- Share-sheet delivery to WhatsApp, email, Drive, or device storage.

## Reconciliation rules

All monetary comparisons are rounded to two decimal places.

```text
Line Total              = Quantity × Unit Price
Total Daily Expenses    = SUM(Line Totals for site and date)
Expected Closing        = Opening Balance + Float Received - Total Daily Expenses
Variance                = Reported Closing Balance - Expected Closing
Status                  = OK only when Variance == 0.00; otherwise CHECK / MISMATCH
Negative Expected       = Site Supervisor Deficit / Out-of-pocket Advance
```

For a lump-sum cost, enter quantity `1` and the lump sum as unit price.

## Locked expense categories

The database seeds these IDs and labels in this exact order:

1. Fuel & Lubricants
2. Materials
3. Wages, Allowances & Advances
4. Transport
5. Repairs & Maintenance
6. Tools & Equipment
7. Medical Expenses
8. Labour
9. Site Welfare & Safety
10. Other / Miscellaneous

## Reports

### Three-page DPR

The professional DPR uses explicit page allocation so every shared report has a
predictable audit structure:

- Page 1: identity/header, work progress, manpower, material stock, and
  equipment/fuel readings.
- Page 2: QC, HSE, expense ledger, float reconciliation, delays, and next-day
  plan.
- Page 3: photographs, document references, and real sign-off signatures.

Daily tables are bounded to protect the three-page contract. When a daily
ledger exceeds the printable detail limit, the PDF shows a continuation notice
and the complete data remains available in the Excel workbook.

### Six-tab Excel workbook

1. `Instructions`
2. `Daily Log`
3. `Monthly Summary`
4. `Overall Summary`
5. `Cash Flow`
6. `Charts`

The summary and cash-flow sheets contain spreadsheet formulas. The charts sheet
contains native column, doughnut, and multi-line charts backed by export-time
values so the visuals render immediately.

## Offline storage and signatures

- SQLite schema version: `7`.
- Foreign keys, indexes, category seeds, unique site/date float records, and
  expense total triggers are created by migrations.
- Signature images are copied into the app-private `signatures` directory; the
  database stores only their private local paths.
- Site photos are compressed and stored locally before they are referenced by a
  log.
- No signature is uploaded merely by capturing it. A signature leaves the
  device only when the user explicitly shares a DPR/file or uses a configured
  backup/sync action.
- The existing Drive backup feature protects the SQLite database. For a full
  cross-device record, separately retain shared DPRs and the app's local media;
  database-only restore cannot recreate local image bytes.

## Project structure

```text
lib/
├── db/                     SQLite schema, migrations, atomic repositories
├── models/                 Domain and reporting models
├── screens/                Field entry, dashboard, and report workflows
├── services/               Reconciliation, PDF, Excel, sync, and media engines
├── theme/                  Application theme
├── utils/                  Currency helpers
└── widgets/                Shared UI components
test/
├── reconciliation_service_test.dart
├── domain_models_test.dart
└── database_helper_test.dart
```

## Development setup

Requirements:

- Flutter stable with Dart `>=3.12.0`
- Android SDK 35
- Java 21
- Linux tests: `libsqlite3` and `libsqlite3-dev`

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
flutter run
```

The Gradle 8.10.2 wrapper is checked in. Its wrapper JAR and distribution are
protected by known SHA-256 values.

## Android builds

Debug APK:

```bash
flutter build apk --debug
```

Release app bundle:

```bash
cp android/key.properties.example android/key.properties
# Fill in local keystore values; never commit key.properties or the keystore.
flutter build appbundle --release
```

If no release keystore exists, local/CI release builds fall back to debug
signing for validation. A Play Store upload must use the organization's secure
release keystore.

## Continuous integration

`.github/workflows/flutter-ci.yml` validates the Gradle wrapper, resolves
packages, checks formatting, runs static analysis and tests, builds a debug APK,
and retains the APK as a short-lived workflow artifact.

## Data-safety notes

- Project/site deletion cascades through related relational records and is
  guarded by a confirmation dialog.
- Keep production signing keys and Google credentials outside source control.
- Treat signature images and reports as confidential project records; share
  them only with authorized recipients.

## License

MIT
