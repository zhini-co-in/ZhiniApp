// lib/utils/manual_ticket_store.dart
//
// Locally remembers which ticket IDs were created via the
// "Manual Ticket Create" screen — purely on-device, no backend needed.
// Used to decide whether to trigger the WhatsApp share on accept.

import 'package:shared_preferences/shared_preferences.dart';

class ManualTicketStore {
  static const _key = 'manual_ticket_ids';

  static Future<void> markAsManual(String ticketId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    if (!ids.contains(ticketId)) {
      ids.add(ticketId);
      await prefs.setStringList(_key, ids);
    }
  }

  static Future<bool> isManual(String ticketId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    return ids.contains(ticketId);
  }
}