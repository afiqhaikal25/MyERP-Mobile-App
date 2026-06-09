/// Odoo JSON-RPC uses `false` for empty values — not null. Use these helpers in UI.
String odooStr(dynamic value, [String fallback = '']) {
  if (value == null || value is bool) return fallback;
  final s = value.toString().trim();
  if (s.isEmpty || s.toLowerCase() == 'false') return fallback;
  return s;
}

Map<String, dynamic> normalizeOdooRecord(Map<String, dynamic> record) {
  final out = Map<String, dynamic>.from(record);
  for (final e in out.entries) {
    final v = e.value;
    if (v is bool) {
      out[e.key] = '';
    } else if (v == null) {
      out[e.key] = '';
    }
  }
  return out;
}
