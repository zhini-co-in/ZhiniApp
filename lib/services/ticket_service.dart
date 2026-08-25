import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../constants/api_config.dart';
import '../service_ticket_card.dart';

class TicketService {
static Future<List<ServiceTicket>> fetchProviderTickets(
    String providerMobile) async {
  final uri = Uri.parse(ApiConfig.providerTicketsUrl);
  debugPrint('🎫 Fetching tickets: $uri for $providerMobile');

  final response = await http.post(          // 🔄 GET -> POST
    uri,
    headers: {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    },
    body: jsonEncode({'providerMobile': providerMobile}),   // 🔄 body-la anupurom
  );
  debugPrint('🎫 Ticket response: ${response.statusCode} ${response.body}');

  if (response.statusCode != 200) {
    throw Exception('Failed to load tickets (${response.statusCode})');
  }

  final Map<String, dynamic> body = jsonDecode(response.body);
  if (body['success'] != true) {
    throw Exception(body['message']?.toString() ?? 'Failed to load tickets');
  }

  final List<dynamic> data = body['data'] ?? [];
  return data
      .whereType<Map<String, dynamic>>()
      .map((json) => _mapToTicket(json))
      .toList();
}

/// Manually create a ticket (walk-in / phone-in customer request).
/// The `source: 'MANUAL'` flag is what tells the backend to send WhatsApp
/// updates for this ticket's lifecycle — normal/automatic tickets never
/// set this, so they stay silent exactly as before.
static Future<String> createManualTicket({
  required String customerName,
  required String customerPhone,
  required String address,
  required String description,
  required String availableTime,
  required String providerMobile,
}) async {
  final uri = Uri.parse(ApiConfig.createServiceTicketUrl);
  final response = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    },
    body: jsonEncode({
      'customerName': customerName,
      'cust_number': customerPhone,
      'address': address,
      'description': description,
      'availableTime': availableTime,
      'providerMobile': providerMobile,
      'source': 'MANUAL',
    }),
  );

  final decoded = jsonDecode(response.body);
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(decoded['message']?.toString() ?? 'Failed to create ticket');
  }

  final data = decoded['data'] as Map<String, dynamic>?;
  return (data?['ticketId'] ?? data?['_id'] ?? '').toString();
}

 static Future<void> respondToTicket({
    required String ticketId,
    required bool accepted,
  }) async {
    final uri = Uri.parse(ApiConfig.ticketRespondUrl);
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({
        'ticketId': ticketId,
        'newStatus': accepted ? 'ACCEPTED' : 'REJECTED',   // 🔄 key + value maathirukkom
      }),
    );

    if (response.statusCode != 200) {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['message']?.toString() ?? 'Failed to update ticket');
    }
  }

  /// Attaches billing (product, parts, labour, GST, payment) to a ticket
  /// and marks it completed on the backend.
  ///
  /// Confirmed via Postman:
  ///   POST {ApiConfig.baseUrl}/service/billing/:ticketMongoId
  /// Body is a FLAT json object (not wrapped in {"billing": ...}), and
  /// `:ticketMongoId` is the ticket's MongoDB `_id` — NOT the human
  /// readable `ticketId` (e.g. TICK-1786021057532) used elsewhere in
  /// this file. Make sure `ticketMongoId` is the real `_id` value or
  /// the backend returns 404.
  static Future<void> addTicketBilling({
    required String ticketMongoId,
    required Map<String, dynamic> billing,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/service/billing/$ticketMongoId');
    debugPrint('🧾 Saving billing: $uri');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode(billing), // flat body — no "billing" wrapper key
    );
    debugPrint('🧾 Billing response: ${response.statusCode} ${response.body}');

    if (response.statusCode != 200 && response.statusCode != 201) {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['message']?.toString() ?? 'Failed to save billing');
    }
  }

static ServiceTicket _mapToTicket(Map<String, dynamic> json) {
    final customer = json['customerDetails'] as Map<String, dynamic>? ?? {};
    final service = json['serviceDetails'] as Map<String, dynamic>? ?? {};

    final description = (service['description'] ?? '').toString();
    // "Unknown Laptop — Out of warranty. Room: Hall." style-la irundhu
    // "Unknown Laptop" ah appliance-a, baaki-yah issue-a split pannurom.
    String appliance = 'Appliance';
    String issue = description;
    if (description.contains('—')) {
      final parts = description.split('—');
      appliance = parts.first.trim();
      issue = parts.sublist(1).join('—').trim();
    }

    return ServiceTicket(
  id: (json['ticketId'] ?? json['_id'] ?? '').toString(),
  mongoId: json['_id']?.toString(),
  customerName: (customer['name'] ?? 'Customer').toString(),
  customerPhone: (customer['phone'] ?? '').toString(),   // 👈 ADD
  appliance: appliance.isNotEmpty ? appliance : 'Appliance',
  issue: issue.isNotEmpty ? issue : description,
  address: (customer['address'] ?? '').toString(),
  distanceKm: _asDouble(json['distanceKm']),
  urgency: _mapUrgency(json['urgency'] ?? json['priority']),
  postedAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
  status: (json['status'] ?? 'NEW').toString().toUpperCase(),
  source: (json['source'] ?? 'APP').toString().toUpperCase(),   // 👈 ADD
);
  }

static Future<void> updateTicketStatus({
    required String ticketId,
    required String newStatus,
  }) async {
    final uri = Uri.parse(ApiConfig.ticketRespondUrl);
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({'ticketId': ticketId, 'newStatus': newStatus}),
    );
    if (response.statusCode != 200) {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['message']?.toString() ?? 'Failed to update status');
    }
  }
  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static TicketUrgency _mapUrgency(dynamic value) {
    final v = value?.toString().toLowerCase() ?? '';
    if (v.contains('high') || v.contains('urgent')) return TicketUrgency.high;
    if (v.contains('low')) return TicketUrgency.low;
    return TicketUrgency.medium;
  }
}