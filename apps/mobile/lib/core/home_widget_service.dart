import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HomeWidgetPageData {
  const HomeWidgetPageData({
    required this.title,
    required this.weekday,
    required this.day,
    required this.fullDate,
    required this.items,
    required this.moreCount,
  });

  final String title;
  final String weekday;
  final String day;
  final String fullDate;
  final List<HomeWidgetScheduleItem> items;
  final int moreCount;

  Map<String, Object> toMap() => {
    'title': title,
    'weekday': weekday,
    'day': day,
    'fullDate': fullDate,
    'items': items.map((item) => item.toMap()).toList(),
    'moreCount': moreCount,
  };
}

class HomeWidgetScheduleItem {
  const HomeWidgetScheduleItem({
    required this.startsAt,
    required this.endsAt,
    required this.title,
    required this.memberName,
    required this.memberColor,
  });

  final String startsAt;
  final String endsAt;
  final String title;
  final String memberName;
  final String memberColor;

  Map<String, String> toMap() => {
    'startsAt': startsAt,
    'endsAt': endsAt,
    'title': title,
    'memberName': memberName,
    'memberColor': memberColor,
  };
}

/// Shares the compact home briefing with the native Android/iOS widgets.
///
/// Widgets cannot render Flutter directly, so the native implementations read
/// these preformatted values from platform shared storage.
class HomeWidgetService {
  static const _channel = MethodChannel('checky/home_widget');

  static Future<void> update({required HomeWidgetPageData schedule}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('update', {
        'schedule': schedule.toMap(),
      });
    } on MissingPluginException {
      // Native widget support is unavailable on development-only platforms.
    } on PlatformException {
      // The in-app home remains available even if a widget refresh fails.
    }
  }
}
