// lib/utils/warranty_utils.dart
//
// Single source of truth for warranty parsing (Home, Devices, Scan, Profile,
// Room detail). Understands: "2 Years", "2 yrs", "1 year 6 months",
// "24 months", "90 days", "12/2027", "31/12/2027", "2027-12-31",
// "Dec 2027", "2027".  Returns null ONLY when there is really no warranty
// info (empty / N/A).

import 'package:flutter/material.dart';
import '../constants/app_strings.dart';
import '../theme/app_theme.dart';

class WarrantyUtils {
  WarrantyUtils._();

  static const Set<String> _noWarranty = {
    '', 'n/a', 'na', 'none', 'nil', 'null', 'unknown',
    'not available', 'not found', 'no warranty', '-', '--', '—',
  };

  static const Map<String, int> _monthNames = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// [referenceDate] anchors duration values ("2 Years"): pass the item's
  /// createdAt for saved appliances; null = today (appliance being scanned).
  static DateTime? parseExpiry(String? warranty, {DateTime? referenceDate}) {
    if (warranty == null) return null;
    final text = warranty.trim().toLowerCase();
    if (_noWarranty.contains(text)) return null;
    final base = referenceDate ?? DateTime.now();

    // yyyy-mm-dd
    var m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
    if (m != null) {
      return _safeDate(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }

    // dd/mm/yyyy (also - and .), 2 or 4 digit year
    m = RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})').firstMatch(text);
    if (m != null) {
      var year = int.parse(m.group(3)!);
      if (year < 100) year += 2000;
      return _safeDate(year, int.parse(m.group(2)!), int.parse(m.group(1)!));
    }

    // mm/yyyy -> last day of that month
    m = RegExp(r'(\d{1,2})[/.\-](\d{4})').firstMatch(text);
    if (m != null) {
      final month = int.parse(m.group(1)!);
      final year = int.parse(m.group(2)!);
      if (month >= 1 && month <= 12) return DateTime(year, month + 1, 0);
    }

    // "Dec 2027" / "15 Dec 2027"
    m = RegExp(r'(?:(\d{1,2})\s*)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s,.\-]*(\d{4})')
        .firstMatch(text);
    if (m != null) {
      final month = _monthNames[m.group(2)!]!;
      final year = int.parse(m.group(3)!);
      final day = m.group(1);
      return day != null ? _safeDate(year, month, int.parse(day)) : DateTime(year, month + 1, 0);
    }

    // durations: "2 years", "1 year 6 months", "24 months", "90 days"
    final durations = RegExp(
      r'(\d+(?:\.\d+)?)\s*(years?|yrs?|y|months?|mos?|mo|m|weeks?|wks?|w|days?|d)\b',
    ).allMatches(text);
    if (durations.isNotEmpty) {
      double years = 0, months = 0, days = 0;
      for (final d in durations) {
        final n = double.parse(d.group(1)!);
        final unit = d.group(2)!;
        if (unit.startsWith('y')) {
          years += n;
        } else if (unit.startsWith('mo') || unit == 'm') {
          months += n;
        } else if (unit.startsWith('w')) {
          days += n * 7;
        } else {
          days += n;
        }
      }
      final totalMonths = (years * 12 + months).round();
      if (totalMonths == 0 && days == 0) return null;
      return _addMonths(base, totalMonths).add(Duration(days: days.round()));
    }

    // only a year: "2027"
    m = RegExp(r'^\D*(\d{4})\D*$').firstMatch(text);
    if (m != null) {
      final year = int.parse(m.group(1)!);
      if (year >= 1990 && year <= 2100) return DateTime(year, 12, 31);
    }

    // only a small number: "2" -> 2 years
    m = RegExp(r'^(\d{1,2})$').firstMatch(text);
    if (m != null) {
      final years = int.parse(m.group(1)!);
      if (years > 0) return _addMonths(base, years * 12);
    }

    return null;
  }

  /// True if [warranty] is still active as of [referenceDate] (default: now).
  static bool isActive(String? warranty, {DateTime? referenceDate}) {
    final expiry = parseExpiry(warranty, referenceDate: referenceDate);
    return expiry != null && expiry.isAfter(referenceDate ?? DateTime.now());
  }

  /// Days remaining until expiry (negative = already expired).
  static int? daysLeft(String? warranty, {DateTime? createdAt, DateTime? now}) {
    final expiry = parseExpiry(warranty, referenceDate: createdAt);
    if (expiry == null) return null;
    return expiry.difference(now ?? DateTime.now()).inDays;
  }

  /// (label, color, icon) status pill — used by the Room detail screen.
  static (String, Color, IconData) statusPill(String? warranty, {DateTime? createdAt}) {
    final days = daysLeft(warranty, createdAt: createdAt);
    if (days == null) {
      return (AppStrings.noWarrantyInfo, AppColors.textFaint, Icons.help_outline_rounded);
    }
    if (days < 0) return (AppStrings.statusExpired, AppColors.danger, Icons.error_outline_rounded);
    if (days <= 30) return (AppStrings.statusExpiringSoon, AppColors.warning, Icons.access_time_rounded);
    return (AppStrings.statusActive, AppColors.success, Icons.verified_rounded);
  }

  // ---------------------------------------------------------------------
  static DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > lastDay ? lastDay : day);
  }

  static DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
  }
}