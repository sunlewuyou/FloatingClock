import 'package:flutter/material.dart';
import 'package:floating_clock/pages/home_page.dart';
import 'package:floating_clock/services/time_sync_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.timeSyncService = const TimeSyncService(),
  });

  final TimeSyncService timeSyncService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '悬浮时间',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(timeSyncService: timeSyncService),
    );
  }
}
