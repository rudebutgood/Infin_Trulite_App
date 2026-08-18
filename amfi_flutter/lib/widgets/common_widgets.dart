import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CommonWidgets {
  static Widget txt(String text, {TextStyle? style, bool overflow = false, TextAlign? align, String selectedLanguage = 'English', Future<String> Function(String)? translate}) {
    if (selectedLanguage == 'English') {
      return Text(text, style: style, overflow: overflow ? TextOverflow.ellipsis : null, textAlign: align);
    }
    return FutureBuilder<String>(
      future: translate?.call(text),
      builder: (context, snapshot) => Text(
        snapshot.data ?? text,
        style: style,
        overflow: overflow ? TextOverflow.ellipsis : null,
        textAlign: align,
      ),
    );
  }

  static String formatCurrency(num value, {bool privacyMode = false}) {
    if (privacyMode) return '****';
    return NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 0).format(value).trim();
  }

  static String formatImportedAt(String iso) {
    try {
      DateTime dt;
      if (iso.endsWith('Z') && iso.length > 10) {
        dt = DateTime.parse(iso.substring(0, iso.length - 1));
      } else {
        dt = DateTime.parse(iso);
      }
      final local = dt.toLocal();
      return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return iso;
    }
  }

  static Widget detailRow(String label, String? value, {Color? color, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 13))),
          Expanded(flex: 3, child: SelectableText(value ?? '-', style: TextStyle(fontWeight: FontWeight.w400, color: color, fontSize: 13))),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
