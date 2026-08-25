// lib/manual_ticket_create_screen.dart
//
// Lets a service provider manually create a ticket for a customer
// (e.g. walk-in / phone-in requests that didn't come through the app).
// On submit -> POST to backend's createServiceTicket controller.
// The backend itself does NOT send WhatsApp on creation — per the agreed
// flow, the first WhatsApp (ticket details + accepted) goes out when the
// provider marks the ticket as ACCEPTED from the Jobs list.

import 'package:flutter/material.dart';
import 'services/ticket_service.dart';
import 'utils/manual_ticket_store.dart';

class ManualTicketCreateScreen extends StatefulWidget {
  final String providerMobile;

  const ManualTicketCreateScreen({super.key, required this.providerMobile});

  @override
  State<ManualTicketCreateScreen> createState() => _ManualTicketCreateScreenState();
}

class _ManualTicketCreateScreenState extends State<ManualTicketCreateScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _timeController = TextEditingController();

  bool _submitting = false;

  static const _fieldFill = Color(0xFF0F2038);
  static const _bg1 = Color(0xFF0A1628);
  static const _bg2 = Color(0xFF0F2038);

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _timeController.dispose();
    super.dispose();
  }

Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final ticketId = await TicketService.createManualTicket(   // 🔄 'await' முன்னாடி 'final ticketId =' சேர்த்தது
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        description: _descriptionController.text.trim(),
        availableTime: _timeController.text.trim(),
        providerMobile: widget.providerMobile,
      );

      if (ticketId.isNotEmpty) {                                 // 👈 இந்த 3 வரி புதுசா சேர்த்தது
        await ManualTicketStore.markAsManual(ticketId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF16294A),
          content: Text('Ticket created successfully', style: TextStyle(color: Colors.white)),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create ticket: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white54),
      hintStyle: const TextStyle(color: Colors.white24),
      filled: true,
      fillColor: _fieldFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg1,
      appBar: AppBar(
        backgroundColor: _bg1,
        elevation: 0,
        title: const Text('Create Ticket', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bg1, _bg2],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Enter the customer & job details below. This is for walk-in / phone-in requests.',
                  style: TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Customer name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Customer phone', hint: '10-digit mobile number'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final digits = v.replaceAll(RegExp(r'\D'), '');
                    if (digits.length < 10) return 'Enter a valid phone number';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: _decoration('Address'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: _decoration('Issue / appliance description',
                      hint: 'e.g. LG Fridge — Not cooling'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _timeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Available time', hint: 'e.g. Today evening 5-7 PM'),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Create Ticket',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}