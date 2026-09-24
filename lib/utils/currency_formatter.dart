import 'package:intl/intl.dart';

/// Naira currency formatting for all on-screen money display.
/// Use [format] for full precision and [formatCompact] for dashboard cards.
class CurrencyFormatter {
  static final NumberFormat _formatter = NumberFormat.currency(
    symbol: '₦',
    decimalDigits: 2,
  );

  static String format(double amount) {
    return _formatter.format(amount);
  }

  static String formatCompact(double amount) {
    if (amount >= 1000000) {
      return '₦${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '₦${(amount / 1000).toStringAsFixed(1)}K';
    }
    return format(amount);
  }
}
