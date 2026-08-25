// lib/billing_screen.dart
//
// Shown right after the provider confirms "Mark as complete?" on a job.
// Two steps:
//   1) Raise bill  — product name, parts used (with price), labour, GST
//   2) Collect payment — Cash / UPI, then "Amount collected" finalizes
//
// On success this calls TicketService.addTicketBilling() to save the
// bill on the ticket (POST /service/billing/:mongoId), then
// TicketService.updateTicketStatus(COMPLETED), and pops back with
// 'COMPLETED'.

import 'package:flutter/material.dart';
import 'services/ticket_service.dart';

enum _BillStep { items, payment }

enum PaymentMethod { cash, upi }

class BillLineItem {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController priceController = TextEditingController();

  double get price => double.tryParse(priceController.text.trim()) ?? 0;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}

class BillingScreen extends StatefulWidget {
  final String ticketId; // TICK-xxxx, used for the status-update call
  final String ticketMongoId; // Mongo _id, required by /service/billing/:id
  final String customerName;
  final String appliance;

  const BillingScreen({
    super.key,
    required this.ticketId,
    required this.ticketMongoId,
    required this.customerName,
    required this.appliance,
  });

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  static const _bg = Color(0xFF0A1628);
  static const _card = Color(0xFF0F2038);
  static const _accent = Color(0xFF2E7DFF);
  static const _green = Color(0xFF35D48A);

  _BillStep _step = _BillStep.items;

  late final TextEditingController _productNameController =
      TextEditingController(text: widget.appliance);
  final List<BillLineItem> _items = [BillLineItem()];
  final TextEditingController _labourController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _warrantyDaysController = TextEditingController(text: '0');
  double _gstPercent = 18;

  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _submitting = false;

  double get _partsTotal => _items.fold(0.0, (sum, it) => sum + it.price);
  double get _labour => double.tryParse(_labourController.text.trim()) ?? 0;
  double get _subtotal => _partsTotal + _labour;
  double get _gstAmount => _subtotal * _gstPercent / 100;
  double get _grandTotal => _subtotal + _gstAmount;

  @override
  void dispose() {
    _productNameController.dispose();
    for (final it in _items) {
      it.dispose();
    }
    _labourController.dispose();
    _notesController.dispose();
    _warrantyDaysController.dispose();
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(BillLineItem()));

  void _removeItem(int index) {
    if (_items.length == 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  bool _validateItems() {
    if (_productNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the product name')),
      );
      return false;
    }
    final hasAtLeastOneNamedItem =
        _items.any((it) => it.nameController.text.trim().isNotEmpty);
    if (!hasAtLeastOneNamedItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product/part')),
      );
      return false;
    }
    return true;
  }

  void _goToPayment() {
    if (!_validateItems()) return;
    setState(() => _step = _BillStep.payment);
  }

  Future<void> _submitBillingAndComplete() async {
    if (_submitting) return;

    if (widget.ticketMongoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing ticket reference — cannot save bill')),
      );
      return;
    }

    setState(() => _submitting = true);

    final namedItems =
        _items.where((it) => it.nameController.text.trim().isNotEmpty).toList();
    final warrantyDays = int.tryParse(_warrantyDaysController.text.trim()) ?? 0;

    final billingPayload = {
      // Matches the existing backend schema (productName / partsUsed /
      // laborCharge / partsCost / totalAmount / notes / warrantyDays)
      'productName': _productNameController.text.trim(),
      'partsUsed': namedItems.map((it) => it.nameController.text.trim()).toList(),
      'laborCharge': _labour,
      'partsCost': _partsTotal,
      'totalAmount': _grandTotal,
      'notes': _notesController.text.trim(),
      'warrantyDays': warrantyDays,
      // Extra detail on top of the base schema — safe to add since the
      // backend stores billing as a free-form object.
      'partsDetailed': namedItems
          .map((it) => {
                'name': it.nameController.text.trim(),
                'price': it.price,
              })
          .toList(),
      'subtotal': _subtotal,
      'gstPercent': _gstPercent,
      'gstAmount': _gstAmount,
      'paymentMethod': _paymentMethod == PaymentMethod.cash ? 'CASH' : 'UPI',
      'amountCollected': _grandTotal,
      'paidAt': DateTime.now().toIso8601String(),
    };

    try {
      await TicketService.addTicketBilling(
        ticketMongoId: widget.ticketMongoId,
        billing: billingPayload,
      );
      await TicketService.updateTicketStatus(
        ticketId: widget.ticketId,
        newStatus: 'COMPLETED',
      );
      if (!mounted) return;
      Navigator.pop(context, 'COMPLETED');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _card,
          content: Text('Could not save bill: $e',
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          _step == _BillStep.items ? 'Raise bill' : 'Collect payment',
          style: const TextStyle(color: Colors.white, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: _submitting
              ? null
              : () {
                  if (_step == _BillStep.payment) {
                    setState(() => _step = _BillStep.items);
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
      ),
      body: SafeArea(
        child: _step == _BillStep.items ? _buildItemsStep() : _buildPaymentStep(),
      ),
    );
  }

  // -------------------------------------------------------------------
  // STEP 1 — product / parts / labour / GST / notes / warranty
  // -------------------------------------------------------------------
  Widget _buildItemsStep() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Text(
                widget.customerName,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              const Text('Product',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _textField(_productNameController, hint: 'e.g. Dell XPS 15'),
              const SizedBox(height: 18),
              const Text('Parts used',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ...List.generate(_items.length, (index) => _itemRow(index)),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_circle_outline_rounded, color: _accent, size: 18),
                label: const Text('Add another part',
                    style: TextStyle(color: _accent, fontSize: 13)),
              ),
              const SizedBox(height: 18),
              const Text('Labour charge',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _amountField(_labourController, hint: 'e.g. 300', onChanged: () => setState(() {})),
              const SizedBox(height: 18),
              const Text('GST',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [0, 5, 12, 18, 28].map((pct) {
                  final selected = _gstPercent == pct;
                  return ChoiceChip(
                    label: Text('$pct%'),
                    selected: selected,
                    onSelected: (_) => setState(() => _gstPercent = pct.toDouble()),
                    backgroundColor: _card,
                    selectedColor: _accent,
                    labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.white60, fontSize: 12.5),
                    side: BorderSide(color: selected ? _accent : Colors.white10),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text('Warranty (days)',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _amountField(_warrantyDaysController, hint: 'e.g. 90', onChanged: () {}),
              const SizedBox(height: 18),
              const Text('Notes (optional)',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _notesController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'e.g. Replaced cracked screen and serviced cooling system',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 12.5),
                  filled: true,
                  fillColor: _card,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _accent, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _summaryCard(),
            ],
          ),
        ),
        _bottomBar(
          label: 'Continue to payment',
          icon: Icons.arrow_forward_rounded,
          onTap: _goToPayment,
        ),
      ],
    );
  }

  Widget _itemRow(int index) {
    final item = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _textField(item.nameController, hint: 'Part name'),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _amountField(item.priceController,
                hint: '₹', onChanged: () => setState(() {})),
          ),
          IconButton(
            onPressed: _items.length == 1 ? null : () => _removeItem(index),
            icon: Icon(Icons.remove_circle_outline_rounded,
                color: _items.length == 1 ? Colors.white12 : Colors.redAccent, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          _summaryRow('Parts total', _partsTotal),
          _summaryRow('Labour charge', _labour),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Colors.white10, height: 1),
          ),
          _summaryRow('Subtotal', _subtotal),
          _summaryRow('GST (${_gstPercent.toStringAsFixed(0)}%)', _gstAmount),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Colors.white10, height: 1),
          ),
          _summaryRow('Total', _grandTotal, bold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: bold ? Colors.white : Colors.white54,
                  fontSize: bold ? 14.5 : 12.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          Text('₹${value.toStringAsFixed(2)}',
              style: TextStyle(
                  color: bold ? _green : Colors.white70,
                  fontSize: bold ? 15 : 12.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // STEP 2 — payment collection
  // -------------------------------------------------------------------
  Widget _buildPaymentStep() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    const Text('Amount to collect',
                        style: TextStyle(color: Colors.white54, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    Text('₹${_grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text('Payment method',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _paymentOption(
                      label: 'Cash',
                      icon: Icons.payments_rounded,
                      selected: _paymentMethod == PaymentMethod.cash,
                      onTap: () => setState(() => _paymentMethod = PaymentMethod.cash),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _paymentOption(
                      label: 'UPI',
                      icon: Icons.qr_code_2_rounded,
                      selected: _paymentMethod == PaymentMethod.upi,
                      onTap: () => setState(() => _paymentMethod = PaymentMethod.upi),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _bottomBar(
          label: 'Amount collected',
          icon: Icons.check_circle_rounded,
          color: _green,
          loading: _submitting,
          onTap: _submitBillingAndComplete,
        ),
      ],
    );
  }

  Widget _paymentOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? _accent.withValues(alpha: 0.15) : _card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: selected ? _accent : Colors.white10, width: selected ? 1.4 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? _accent : Colors.white38, size: 26),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : Colors.white54,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Shared small widgets
  // -------------------------------------------------------------------
  Widget _textField(TextEditingController controller, {required String hint}) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: _card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent, width: 1.4),
        ),
      ),
    );
  }

  Widget _amountField(TextEditingController controller,
      {required String hint, required VoidCallback onChanged}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => onChanged(),
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: _card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent, width: 1.4),
        ),
      ),
    );
  }

  Widget _bottomBar({
    required String label,
    required IconData icon,
    Color color = _accent,
    bool loading = false,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: loading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Icon(icon, color: Colors.white, size: 18),
          label: Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}