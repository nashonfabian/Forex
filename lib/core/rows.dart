/// A database row. Rows are plain maps; these helpers read them safely.
typedef Rec = Map<String, Object?>;

extension RecX on Map<String, Object?> {
  String s(String key, [String fallback = '']) {
    final v = this[key];
    return v is String ? v : fallback;
  }

  /// A non-empty string, or null.
  String? sn(String key) {
    final v = this[key];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  int i(String key, [int fallback = 0]) {
    final v = this[key];
    return v is num ? v.toInt() : fallback;
  }

  int? iN(String key) {
    final v = this[key];
    return v is num ? v.toInt() : null;
  }

  double? d(String key) {
    final v = this[key];
    return v is num ? v.toDouble() : null;
  }

  bool b(String key) {
    final v = this[key];
    return v is num && v != 0;
  }
}
