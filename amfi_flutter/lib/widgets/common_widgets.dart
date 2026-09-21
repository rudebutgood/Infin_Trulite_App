import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

class CommonWidgets {
  static const Map<String, String> languageCodes = {
    'English': 'en',
    'Hindi': 'hi',
    'Marathi': 'mr',
    'Gujarati': 'gu',
    'Tamil': 'ta',
    'Telugu': 'te',
    'Kannada': 'kn',
    'Bengali': 'bn',
    'Malayalam': 'ml',
    'Punjabi': 'pa',
  };

  static String getLangCode(String lang) => languageCodes[lang] ?? 'en';

  static Widget txt(String text, {TextStyle? style, bool overflow = false, int? maxLines, TextAlign? align, String selectedLanguage = 'English', Future<String> Function(String)? translate}) {
    if (selectedLanguage == 'English') {
      return Text(text, style: style, overflow: overflow ? TextOverflow.ellipsis : null, maxLines: maxLines, textAlign: align);
    }
    return FutureBuilder<String>(
      future: translate?.call(text),
      builder: (context, snapshot) => Text(
        snapshot.data ?? text,
        style: style,
        overflow: overflow ? TextOverflow.ellipsis : null,
        maxLines: maxLines,
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

class CommonWebViewPopup extends StatefulWidget {
  final String url;
  final String title;
  final String selectedLanguage;
  final Future<String> Function(String) translate;

  const CommonWebViewPopup({
    super.key,
    required this.url,
    required this.title,
    required this.selectedLanguage,
    required this.translate,
  });

  @override
  State<CommonWebViewPopup> createState() => _CommonWebViewPopupState();
}

class _CommonWebViewPopupState extends State<CommonWebViewPopup> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _showTranslated = true;

  String _getTranslatedUrl(String originalUrl) {
    if (widget.selectedLanguage == 'English') return originalUrl;
    final code = CommonWidgets.getLangCode(widget.selectedLanguage);
    return 'https://translate.google.com/translate?sl=auto&tl=$code&u=${Uri.encodeComponent(originalUrl)}';
  }

  @override
  void initState() {
    super.initState();
    _showTranslated = widget.selectedLanguage != 'English';
    final initialUrl = _showTranslated ? _getTranslatedUrl(widget.url) : widget.url;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (error) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.indigo[900],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: CommonWidgets.txt(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: true,
                    selectedLanguage: widget.selectedLanguage,
                    translate: widget.translate,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
                      onPressed: () async {
                        final uri = Uri.parse(widget.url);
                        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                          await launchUrl(uri, mode: LaunchMode.platformDefault);
                        }
                      },
                      tooltip: 'Open in Browser',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: WebViewWidget(
              controller: _controller,
              gestureRecognizers: {
                Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
                Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
              },
            ),
          ),
        ],
      ),
    );
  }
}
