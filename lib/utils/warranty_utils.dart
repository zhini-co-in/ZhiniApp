import 'package:flutter/material.dart';

/// Shared warranty-parsing logic used across the Home tab, Room detail
/// screen, and Scan tab. Consolidates three previously-duplicated
/// implementations (`_warrantyExpiry`, `_parseExpiry`, `_parseWarrantyExpiry`)
/// into a single source of truth.
class WarrantyUtils {
  WarrantyUtils._();

  /// Parses a warranty string (e.g. "2 Years", "12/2027", "06/2026", "2026")
  /// into an expiry [DateTime].
  ///
  /// [referenceDate] anchors "X Year(s)" style values — pass the item's
  /// `createdAt` for already-saved appliances, or leave it null (defaults to
  /// now) for an appliance that's still being scanned/added and has no
  /// `createdAt` yet.
  static DateTime? parseExpiry(String? warranty, {DateTime? referenceDate}) {
    if (warranty == null) return null;
    final w = warranty.trim();
    if (w.isEmpty || w.toUpperCase() == 'N/A') return null;

    final anchor = referenceDate ?? DateTime.now();

    // Case 1: "2 Years" / "5 Year"
    final yearMatch = RegExp(r'(\d+)\s*Year', caseSensitive: false).firstMatch(w);
    if (yearMatch != null) {
      final years = int.tryParse(yearMatch.group(1) ?? '') ?? 0;
      if (years <= 0) return null;
      return DateTime(anchor.year + years, anchor.month, anchor.day);
    }

    // Case 2: DD/MM/YYYY (or similar) direct date
    final dateSlashMatch =
        RegExp(r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})').firstMatch(w);
    if (dateSlashMatch != null) {
      var year = int.tryParse(dateSlashMatch.group(3) ?? '');
      if (year != null) {
        if (year < 100) year += 2000; // 2-digit year
        final month = int.tryParse(dateSlashMatch.group(2) ?? '') ?? 12;
        final day = int.tryParse(dateSlashMatch.group(1) ?? '') ?? 1;
        return DateTime(year, month, day);
      }
    }

    // Case 3: MM/YYYY only, e.g. "06/2026" — expiry is the last day of that month.
    final monthYearMatch = RegExp(r'^(\d{1,2})\/(\d{4})$').firstMatch(w);
    if (monthYearMatch != null) {
      final month = int.tryParse(monthYearMatch.group(1) ?? '') ?? 12;
      final year = int.tryParse(monthYearMatch.group(2) ?? '') ?? anchor.year;
      final nextMonth = DateTime(year, month + 1, 1);
      return nextMonth.subtract(const Duration(days: 1));
    }

    // Case 4: just a year, e.g. "2026"
    final yearOnlyMatch = RegExp(r'^(\d{4})$').firstMatch(w);
    if (yearOnlyMatch != null) {
      final year = int.tryParse(yearOnlyMatch.group(1) ?? '');
      if (year != null) return DateTime(year, 12, 31);
    }

    return null;
  }

  /// True if [warranty] is still active as of [referenceDate] (default: now).
  static bool isActive(String? warranty, {DateTime? referenceDate}) {
    final expiry = parseExpiry(warranty, referenceDate: referenceDate);
    return expiry != null && expiry.isAfter(referenceDate ?? DateTime.now());
  }

  /// Days remaining until expiry (negative = already expired).
  /// [createdAt] anchors "X Year(s)" values for saved items; omit for
  /// not-yet-saved items being scanned.
  static int? daysLeft(String? warranty, {DateTime? createdAt, DateTime? now}) {
    final expiry = parseExpiry(warranty, referenceDate: createdAt);
    if (expiry == null) return null;
    return expiry.difference(now ?? DateTime.now()).inDays;
  }

  /// (label, color, icon) status pill — used by the Room detail screen's
  /// appliance cards. Replaces `_RoomDetailScreenState._warrantyStatus`.
  static (String, Color, IconData) statusPill(String? warranty, {DateTime? createdAt}) {
    final days = daysLeft(warranty, createdAt: createdAt);
    if (days == null) {
      return ('No warranty info', Colors.white38, Icons.help_outline_rounded);
    }
    if (days < 0) return ('Expired', Colors.redAccent, Icons.error_outline_rounded);
    if (days <= 30) return ('Expiring soon', Colors.orangeAccent, Icons.access_time_rounded);
    return ('Active', Colors.greenAccent, Icons.verified_rounded);
  }
}