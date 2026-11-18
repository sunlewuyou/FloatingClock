import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:floating_clock/pages/scheduled_task_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('floating_clock');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isGestureApiSupported':
          return true;
        case 'isAccessibilityEnabled':
          return false;
        case 'isExactAlarmAllowed':
          return true;
        case 'hasPermission':
          return true;
        case 'getScheduledTaskState':
          return <String, Object>{
            'active': false,
            'targetSystemEpochMs': 0,
            'targetLabel': '',
            'sourceOffsetMillis': 0,
            'status': '尚未创建任务',
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows selected time source, millisecond fields and permission guidance',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ScheduledTaskPage(
        sourceLabel: '腾讯时间',
        offsetMillis: 125,
        refreshOffset: () async => 125,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('定时点击任务'), findsOneWidget);
    expect(find.textContaining('腾讯时间'), findsOneWidget);
    expect(find.text('秒（00–59）'), findsOneWidget);
    expect(find.text('毫秒（000–999）'), findsOneWidget);
    expect(find.textContaining('无障碍点击服务'), findsOneWidget);
    expect(find.text('开始任务'), findsOneWidget);
  });

  testWidgets('shows accessibility service as unsupported on older Android',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isGestureApiSupported':
          return false;
        case 'isAccessibilityEnabled':
        case 'isExactAlarmAllowed':
        case 'hasPermission':
          return false;
        case 'getScheduledTaskState':
          return <String, Object>{
            'active': false,
            'targetSystemEpochMs': 0,
            'targetLabel': '',
            'sourceOffsetMillis': 0,
            'status': '尚未创建任务',
          };
        default:
          return null;
      }
    });

    await tester.pumpWidget(MaterialApp(
      home: ScheduledTaskPage(
        sourceLabel: '系统时间',
        offsetMillis: 0,
        refreshOffset: () async => 0,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('无障碍点击服务：系统不支持'), findsOneWidget);
    expect(find.text('无障碍手势派发需要 Android 7.0 或更高版本。'),
        findsOneWidget);
  });

}
