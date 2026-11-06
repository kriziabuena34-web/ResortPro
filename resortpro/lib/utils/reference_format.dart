import 'package:flutter/services.dart';

/// Format ng reference number ng GCash at Maya.
///   GCash: 13 na numero, nakikita bilang "1012 345 678901" (4-3-6)
///   Maya:  12 na letra o numero, nakikita bilang "A1B2 C3D4 E5F6" (4-4-4)
class RefFormat {
  const RefFormat._(this.groups, this.digitsOnly, this.example);

  final List<int> groups;
  final bool digitsOnly;
  final String example;

  static const gcash = RefFormat._([4, 3, 6], true, '1012 345 678901');
  static const maya = RefFormat._([4, 4, 4], false, 'A1B2 C3D4 E5F6');

  static RefFormat of(String method) => method == 'maya' ? maya : gcash;

  int get length => groups.fold(0, (a, b) => a + b);

  /// Letra/numero lang, walang espasyo, malalaking letra.
  String clean(String input) {
    final up = input.toUpperCase();
    final kept = up.replaceAll(RegExp(digitsOnly ? r'[^0-9]' : r'[^A-Z0-9]'), '');
    return kept.length > length ? kept.substring(0, length) : kept;
  }

  /// May espasyo na ayon sa grupo.
  String format(String input) {
    final raw = clean(input);
    final out = StringBuffer();
    var i = 0;
    for (final g in groups) {
      if (i >= raw.length) break;
      if (out.isNotEmpty) out.write(' ');
      final end = (i + g).clamp(0, raw.length);
      out.write(raw.substring(i, end));
      i = end;
    }
    return out.toString();
  }

  /// Kumpleto ba ang bilang?
  bool isComplete(String input) => clean(input).length == length;

  TextInputFormatter get formatter => _RefFormatter(this);
}

class _RefFormatter extends TextInputFormatter {
  _RefFormatter(this.f);
  final RefFormat f;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Kapag binura ang espasyo, burahin din ang karakter bago nito.
    var text = newValue.text;
    if (text.length < oldValue.text.length &&
        oldValue.text.replaceAll(' ', '') == text.replaceAll(' ', '') &&
        text.isNotEmpty) {
      final cursor = newValue.selection.baseOffset.clamp(0, text.length);
      if (cursor > 0) text = text.substring(0, cursor - 1) + text.substring(cursor);
    }
    final formatted = f.format(text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
