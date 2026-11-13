import 'package:flutter/material.dart';

// Devices tab -> Home tab: "open the add dialog with this product".
final ValueNotifier<String?> applianceAddRequest = ValueNotifier<String?>(null);

const List<String> kApplianceCatalog = [
  'Air Conditioner', 'Air Cooler', 'Air Purifier', 'Chimney', 'Dishwasher',
  'Electric Kettle', 'Fan', 'Food Processor', 'Fridge', 'Gas Stove', 'Geyser',
  'Headphones', 'Home Theatre', 'Induction Stove', 'Inverter', 'Iron Box',
  'Juicer', 'Laptop', 'Microwave Oven', 'Mixer Grinder', 'Mobile Phone',
  'OTG Oven', 'Printer', 'Projector', 'Rice Cooker', 'Room Heater', 'Router',
  'Smart Watch', 'Speaker', 'Tablet', 'Toaster', 'TV', 'UPS',
  'Vacuum Cleaner', 'Washing Machine', 'Water Heater', 'Water Purifier',
  'Wet Grinder',
];

// How many group cards are shown on the Home tab.
const int kHomeGroupCount = 4;

const List<Map<String, dynamic>> kServiceGroups = [
  {
    'title': 'Smartphones & Tablets',
    'sub': 'Screen, battery & diagnostics',
    'icon': Icons.smartphone_rounded,
    'color': Color(0xFF2563EB),
    'items': ['Mobile Phone', 'Tablet', 'Smart Watch', 'Headphones', 'Speaker'],
  },
  {
    'title': 'Laptops & Computers',
    'sub': 'Hardware fix, OS & thermal',
    'icon': Icons.laptop_mac_rounded,
    'color': Color(0xFF6366F1),
    'items': ['Laptop', 'Printer', 'Router', 'Projector', 'UPS'],
  },
  {
    'title': 'Kitchen Appliances',
    'sub': 'Fridge, microwave, chimney',
    'icon': Icons.kitchen_rounded,
    'color': Color(0xFF0EA5E9),
    'items': [
      'Fridge', 'Microwave Oven', 'Chimney', 'Mixer Grinder', 'Gas Stove',
      'Induction Stove', 'Dishwasher', 'Rice Cooker', 'Electric Kettle',
      'Juicer', 'OTG Oven', 'Toaster', 'Wet Grinder', 'Food Processor',
    ],
  },
  {
    'title': 'TV & Entertainment',
    'sub': 'Panels, sound & setup',
    'icon': Icons.tv_rounded,
    'color': Color(0xFF1D4ED8),
    'items': ['TV', 'Home Theatre', 'Speaker', 'Projector'],
  },
  {
    'title': 'Home Comfort',
    'sub': 'AC, fan, cooler, geyser',
    'icon': Icons.ac_unit_rounded,
    'color': Color(0xFF0891B2),
    'items': [
      'Air Conditioner', 'Fan', 'Air Cooler', 'Geyser', 'Water Heater',
      'Room Heater', 'Air Purifier',
    ],
  },
  {
    'title': 'Cleaning & Utility',
    'sub': 'Washing machine, purifier, inverter',
    'icon': Icons.local_laundry_service_rounded,
    'color': Color(0xFF7C3AED),
    'items': [
      'Washing Machine', 'Water Purifier', 'Vacuum Cleaner', 'Iron Box',
      'Inverter', 'UPS',
    ],
  },
];