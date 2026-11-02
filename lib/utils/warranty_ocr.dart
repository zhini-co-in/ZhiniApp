// lib/utils/warranty_ocr.dart
//
// Reads a warranty card image on-device (ML Kit) and extracts the warranty
// period, e.g. "2 years", "24 months". Used by the scan screen and the
// device edit dialog so both behave the same.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class WarrantyOcr {
  WarrantyOcr._();

  static Future<String?> extractPeriod(File file) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFile(file));
      debugPrint('🧾 OCR text: ${result.text}');
      return parsePeriod(result.text);
    } catch (e) {
      debugPrint('❌ OCR error: $e');
      return null;
    } finally {
      recognizer.close();
    }
  }

  // Finds "2 years warranty", "warranty: 24 months", "1 yr guarantee" etc.
  static String? parsePeriod(String raw) {
    final text = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    const unit = r'(years?|yrs?|months?|mths?|days?)';

    final patterns = <RegExp>[
      RegExp(r'(?:warranty|guarantee)[^0-9]{0,40}(\d{1,3})\s*-?\s*' + unit),
      RegExp(r'(\d{1,3})\s*-?\s*' +
          unit +
          r'(?:\s+[a-z]+){0,3}\s+(?:warranty|guarantee)'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m == null) continue;
      final n = int.tryParse(m.group(1)!);
      if (n == null || n <= 0) continue;
      final u = m.group(2)!;
      final word = u.startsWith('y')
          ? 'year'
          : u.startsWith('m')
              ? 'month'
              : 'day';
      return '$n $word${n > 1 ? 's' : ''}';
    }
    return null;
  }
}