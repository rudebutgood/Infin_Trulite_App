import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import '../models/index_data.dart';
import 'nav_repository.dart';
import 'index_service.dart';

class WidgetService {
  static const String _groupId = 'group.com.infin.trulite'; // For iOS App Group
  static const String _androidWidgetName = 'IndexWidgetProvider';
  static const String _iosWidgetName = 'IndexWidget';

  static Future<void> updateWidgetData() async {
    try {
      final repo = NavRepository();
      final service = IndexService();
      
      // 1. Get bookmarked names
      final bookmarks = await repo.getIndexBookmarks();
      if (bookmarks.isEmpty) {
        await HomeWidget.saveWidgetData('indices_json', '');
        await _refreshWidget();
        return;
      }

      // 2. Fetch latest data for indices
      final allIndices = await service.fetchIndices();
      final bookmarkedData = allIndices.where((e) => bookmarks.contains(e.name)).toList();

      // 3. Prepare data for widget
      final data = bookmarkedData.map((e) => {
        'name': e.name,
        'last': e.last.toStringAsFixed(2),
        'change': e.percentChange.toStringAsFixed(2),
        'isPositive': e.percentChange >= 0,
        'chartPath': e.rawData['chartTodayPath'] ?? '',
      }).toList();

      // 4. Save to shared storage
      await HomeWidget.saveWidgetData('indices_json', jsonEncode(data));
      
      // 5. Refresh widget
      await _refreshWidget();
    } catch (e) {
      print('Error updating widget data: $e');
    }
  }

  static Future<void> _refreshWidget() async {
    await HomeWidget.updateWidget(
      name: _androidWidgetName,
      iOSName: _iosWidgetName,
    );
  }
}
