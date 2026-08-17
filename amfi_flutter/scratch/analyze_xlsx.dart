import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final path = "C:\\Users\\manoz\\Downloads\\407802c6-5a9e-4409-979d-2f5f481667e3.xlsx";
  final file = File(path);
  if (!file.existsSync()) {
    print("File not found: $path");
    return;
  }
  
  final bytes = file.readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  
  for (var table in excel.tables.keys) {
    print("\nSheet: $table");
    final sheet = excel.tables[table]!;
    if (sheet.maxRows >= 10) {
      final headerRow = sheet.rows[9];
      print("Header (Row 10): ${headerRow.map((c) => c?.value).toList()}");
      
      for (var i = 10; i < sheet.maxRows && i < 15; i++) {
        print("Row ${i + 1}: ${sheet.rows[i].map((c) => c?.value).toList()}");
      }
    } else {
      print("Sheet has less than 10 rows");
    }
  }
}
