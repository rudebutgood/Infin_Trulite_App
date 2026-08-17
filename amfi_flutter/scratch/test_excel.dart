import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final file = "C:\\Users\\manoz\\Downloads\\Holdings Statement_11-Aug-2026.xls";
  final bytes = File(file).readAsBytesSync();
  try {
    final excel = Excel.decodeBytes(bytes);
    print("Sheets: ${excel.tables.keys}");
    for (var table in excel.tables.keys) {
      print("Table: $table, Rows: ${excel.tables[table]!.maxRows}");
      if (excel.tables[table]!.maxRows > 0) {
        print("First row: ${excel.tables[table]!.rows[0].map((c) => c?.value).toList()}");
      }
    }
  } catch (e) {
    print("Error decoding: $e");
  }
}
