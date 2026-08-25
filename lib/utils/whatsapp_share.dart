// lib/utils/whatsapp_share.dart
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> shareViaWhatsApp({
  required String phone,   // customer phone, e.g. "8754869149"
  required String message,
}) async {
  // Ensure phone is in international format without '+' or spaces
  String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
  if (cleanPhone.length == 10) cleanPhone = '91$cleanPhone';

  final encodedMessage = Uri.encodeComponent(message);
  final url = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');

  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } else {
    debugPrint('⚠️ Could not launch WhatsApp for $cleanPhone');
  }
}