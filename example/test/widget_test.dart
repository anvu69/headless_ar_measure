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
        // Tầng Swift trả `rawValue` của `ArMeasurePlaceResult`, không phải bool.
        'placePoint' => 'placed',
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

  // Đúng cái hỏng máy thật báo về, ở dạng nhỏ nhất kiểm được không cần máy:
  // bấm "Place" mà không đặt được điểm nào thì màn PHẢI nói ra một câu.
  //
  // Trong `flutter test` không có platform view nào dựng, nên
  // `onPlatformViewCreated` không bao giờ nổ và không có controller — tức là
  // lối "kênh không trả lời được", đúng `ArMeasurePlaceResult.notReady`.
  //
  // Và câu phải là câu của `notReady`. Bản trước gộp mọi thất bại vào một câu
  // duy nhất — "hit nothing, aim at a surface" — nên một kênh chết cũng mời
  // người dùng rê máy quanh phòng, mãi mãi.
  testWidgets('bấm Place mà không đặt được điểm thì màn nói ra lý do ĐÚNG', (
    tester,
  ) async {
    mockChannels(arSupported: true);

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('not ready'), findsNothing);

    await tester.tap(find.text('Place'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not ready'), findsOneWidget);
    expect(
      find.textContaining('until it locks'),
      findsNothing,
      reason:
          'đó là câu của `missed` — rê máy quanh vật. Nói nó ở đây là mời người '
          'dùng đi tìm một bề mặt trong khi thứ hỏng là cái kênh.',
    );
  });
}
