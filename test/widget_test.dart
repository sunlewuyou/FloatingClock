// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floating_clock/main.dart';
import 'package:floating_clock/models/time_source.dart';
import 'package:floating_clock/services/time_sync_service.dart';

class _NoNetworkTimeSyncService extends TimeSyncService {
  int ntpCalls = 0;
  int httpCalls = 0;

  @override
  Future<int?> queryNtpOffset(
    String host, {
    int port = 123,
    Duration timeout = const Duration(seconds: 2),
    int attempts = 5,
  }) async {
    ntpCalls++;
    return null;
  }

  @override
  Future<int?> queryHttpOffset(
    TimeSource source, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    httpCalls++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('home page renders clock controls', (WidgetTester tester) async {
    final timeSyncService = _NoNetworkTimeSyncService();
    await tester.pumpWidget(MyApp(timeSyncService: timeSyncService));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('悬浮时间'), findsOneWidget);
    expect(find.text('时间源'), findsOneWidget);
    expect(find.text('开始悬浮'), findsOneWidget);
    expect(find.text('画中画'), findsOneWidget);
    // Startup synchronization is exercised without real sockets or timers.
    expect(timeSyncService.ntpCalls, greaterThan(0));
    expect(timeSyncService.httpCalls, greaterThan(0));
  });
}
