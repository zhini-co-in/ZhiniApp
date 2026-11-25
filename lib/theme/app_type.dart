// lib/theme/app_type.dart
// Single source of truth for font scale + 8px-grid spacing.
// Colors are NOT set here (they come from AppColors) -> use .copyWith(color: ...)
import 'package:flutter/material.dart';

class AppType {
  AppType._();

  // Section title  (e.g. "Appliance & Gadget Services")
  static const TextStyle sectionTitle =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3);

  // Header / card-group title (e.g. home name, "Members", "Devices")
  static const TextStyle headerTitle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3);

  // Card title (e.g. device name, service name, links)
  static const TextStyle cardTitle =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4);

  // Normal body text
  static const TextStyle body =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.4);

  // Subtitle / caption (grey)
  static const TextStyle caption =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4);

  // Bottom nav labels
  static const TextStyle navActive =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const TextStyle navInactive =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
}

class AppSpace {
  AppSpace._();

  static const double xs = 4; // half step (icon/text gaps only)
  static const double sm = 8;
  static const double gap = 12; // gap between cards (4px half step)
  static const double md = 16; // screen side padding, card inner padding
  static const double lg = 24; // gap between sections
  static const double xl = 32;

  static const double screenH = md;
  static const double cardPad = md;
  static const double section = lg;
}