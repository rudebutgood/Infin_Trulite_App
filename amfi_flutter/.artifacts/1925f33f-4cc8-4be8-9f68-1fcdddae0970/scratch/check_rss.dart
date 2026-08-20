import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

void main() async {
  final url = 'https://economictimes.indiatimes.com/markets/stocks/rssfeeds/2146842.cms';
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final document = XmlDocument.parse(response.body);
      final items = document.findAllElements('item');
      print('Found ${items.length} items');
      for (var i = 0; i < 3 && i < items.length; i++) {
        final node = items.elementAt(i);
        print('Item $i:');
        print('  Title: ${node.findElements('title').first.innerText}');
        print('  Link: ${node.findElements('link').first.innerText}');
        try {
          print('  Guid: ${node.findElements('guid').first.innerText}');
        } catch (_) {}
      }
    } else {
      print('Status error: ${response.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
