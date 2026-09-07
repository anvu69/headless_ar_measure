import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';
import 'package:headless_ar_measure_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Cả hai kênh PHẢI được giả, kể cả kênh mình tưởng là không dùng tới.
  //
  // Trong `flutter test`, một kênh không có tay xử lý giả KHÔNG ném
  // `MissingPluginException` — tin nhắn đi vào chỗ trống và `invokeMethod`
  // treo mãi mãi. Màn hình đứng ở vòng quay chờ, và ca kiểm chết bằng
  // "pumpAndSettle timed out", một thông báo không nói gì về nguyên nhân.
  void mockChannels({required bool arSupported}) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel(ArMeasure.methodChannelName),
      (call) async => switch (call.method) {
        'isAvailable' => {'arSupported': arSupported, 'hasSceneDepth': false},
        'placePoint' => false,
        _ => null,
      },
    );
    messenger.setMockStreamHandler(
      const EventChannel(ArMeasure.eventChannelName),
      MockStreamHandler.inline(onListen: (arguments, sink) {}),
    );
  }

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(ArMeasure.methodChannelName),
      null,
    );
    messenger.setMockStreamHandler(
      const EventChannel(ArMeasure.eventChannelName),
      null,
    );
  });

  testWidgets('máy không chạy được ARKit thì báo, chứ không treo màn', (
    tester,
  ) async {
    mockChannels(arSupported: false);

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('not supported'), findsOneWidget);
  });

  testWidgets('máy chạy được thì hiện mặt đo kèm đủ năm nút', (tester) async {
    mockChannels(arSupported: true);

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('not supported'), findsNothing);
    for (final label in ['Place', 'Undo', 'Reset', 'Pause', 'Resume']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
