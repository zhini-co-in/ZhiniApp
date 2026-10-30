// lib/utils/provider_sort.dart
//
// Providers with a valid phone number come first, then ones with a rating
// (higher rating first). Providers with no number go to the bottom.
class ProviderSort {
  ProviderSort._();

  static bool _hasPhone(Map<String, dynamic> p) {
    final v = p['phone']?.toString().trim() ?? '';
    return v.isNotEmpty && v.toUpperCase() != 'N/A' && RegExp(r'\d').hasMatch(v);
  }

  static double? _rating(Map<String, dynamic> p) {
    final raw = p['rating']?.toString().trim();
    if (raw == null || raw.isEmpty || raw.toUpperCase() == 'N/A') return null;
    return double.tryParse(raw);
  }

  static List<Map<String, dynamic>> sort(List<Map<String, dynamic>> list) {
    final indexed = list.asMap().entries.toList();
    indexed.sort((a, b) {
      // 1) phone irukkuravanga mela
      final pa = _hasPhone(a.value), pb = _hasPhone(b.value);
      if (pa != pb) return pa ? -1 : 1;

      // 2) rating irukkuravanga mela, athula high rating mudhala
      final ra = _rating(a.value), rb = _rating(b.value);
      if ((ra != null) != (rb != null)) return ra != null ? -1 : 1;
      if (ra != null && rb != null && ra != rb) return rb.compareTo(ra);

      // 3) mathadhu original order
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }
}