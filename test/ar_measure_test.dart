import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseSample', () {
    test('đủ trường', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
        'snappedToEdge': true,
      });

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement?.mm, 812);
    });

    test('trạng thái lạ trả null thay vì ném', () {
      expect(ArMeasure.parseSample({'status': 'vệ tinh'}), isNull);
    });

    test('trạng thái không kèm số đo vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'needsMotion'});

      expect(s?.status, ArMeasureStatus.needsMotion);
      expect(s?.measurement, isNull);
    });

    // Tầng nền (Swift) gửi sai kiểu không phải chuyện giả định — một khung
    // hình lỗi kiểu không được phép ném, vì nó sẽ giết cả Stream đang lắng
    // nghe EventChannel. Coi sai kiểu như thiếu trường: measurement về null,
    // status vẫn được giữ nguyên.
    test('mm sai kiểu (chuỗi) không ném, số đo về null', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 'not-a-number',
          'tolMm': 12.0,
          'snappedToEdge': true,
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement, isNull);
    });

    test('tolMm sai kiểu (chuỗi) không ném, số đo về null', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 812.0,
          'tolMm': 'not-a-number',
          'snappedToEdge': true,
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement, isNull);
    });

    test('snappedToEdge sai kiểu (chuỗi) không ném, mặc định false', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 812.0,
          'tolMm': 12.0,
          'snappedToEdge': 'not-a-bool',
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement?.mm, 812);
      expect(s?.measurement?.snappedToEdge, isFalse);
    });

    test('map rỗng trả null, không ném', () {
      expect(ArMeasure.parseSample(const {}), isNull);
    });

    // `.excessiveMotion` và `.insufficientFeatures` đổ chung vào `needsMotion`,
    // nhưng cách gỡ thì NGƯỢC nhau: một cái bảo người dùng chậm lại, cái kia
    // bảo rê máy quanh tìm bề mặt có vân. Không có trường này thì màn không có
    // cách nào nói đúng câu nào — nó phải chọn một câu và sai một nửa số lần.
    test('limitedReason đọc được cả hai lý do', () {
      final fast = ArMeasure.parseSample({
        'status': 'needsMotion',
        'limitedReason': 'excessiveMotion',
      });
      final bare = ArMeasure.parseSample({
        'status': 'needsMotion',
        'limitedReason': 'insufficientFeatures',
      });

      expect(fast?.limitedReason, ArMeasureLimitedReason.excessiveMotion);
      expect(bare?.limitedReason, ArMeasureLimitedReason.insufficientFeatures);
    });

    // Khoá mới KHÔNG được phá tương thích: một bản Swift cũ không gửi nó, và
    // mẫu ấy vẫn phải hợp lệ y như trước.
    test('thiếu limitedReason thì về null, mẫu vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'needsMotion'});

      expect(s?.status, ArMeasureStatus.needsMotion);
      expect(s?.limitedReason, isNull);
    });

    // ARKit có thể thêm lý do mới ở một bản iOS sau. Lý do lạ về `null` chứ
    // KHÔNG được giết cả mẫu — trạng thái vẫn là thứ màn cần nhất.
    test('limitedReason lạ không giết mẫu, chỉ về null', () {
      final s = ArMeasure.parseSample({
        'status': 'needsMotion',
        'limitedReason': 'sao chổi',
      });

      expect(s?.status, ArMeasureStatus.needsMotion);
      expect(s?.limitedReason, isNull);
    });

    // `unsupportedConfiguration` và `sensorUnavailable` là hỏng VĨNH VIỄN.
    // Gộp chúng vào `trackingLost` trần thì màn mời người dùng "rê máy chậm và
    // đều" mãi mãi, cho một phiên không bao giờ chạy lại được.
    test('recoverable false đi kèm lỗi vĩnh viễn', () {
      final s = ArMeasure.parseSample({
        'status': 'trackingLost',
        'recoverable': false,
      });

      expect(s?.status, ArMeasureStatus.trackingLost);
      expect(s?.recoverable, isFalse);
    });

    test('thiếu hoặc sai kiểu recoverable thì mặc định là true', () {
      expect(
        ArMeasure.parseSample({'status': 'trackingLost'})?.recoverable,
        isTrue,
      );
      expect(
        ArMeasure.parseSample({
          'status': 'trackingLost',
          'recoverable': 'not-a-bool',
        })?.recoverable,
        isTrue,
      );
    });

    // Cờ ngắm là thứ DUY NHẤT nói cho người dùng biết cú bấm sắp tới có trúng
    // gì không. Máy thật báo về: bấm "Chấm điểm" chĩa vào màn iPad đen bóng thì
    // KHÔNG có gì xảy ra — không điểm, không thông báo — vì tia trượt thật mà
    // nút thì không có cách nào nói ra trước.
    test('aimLocked đọc được khi tầng nền báo tâm ngắm đã bám', () {
      final s = ArMeasure.parseSample({'status': 'ready', 'aimLocked': true});

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimLocked, isTrue);
    });

    // Tầng nền chỉ gửi khoá này khi TRUE — thiếu nghĩa là chưa bám, đúng cái
    // mặc định an toàn: màn vẽ tâm ngắm rỗng và người dùng còn phải rê tiếp.
    test('thiếu aimLocked thì mặc định false, mẫu vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'ready'});

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimLocked, isFalse);
    });

    test('aimLocked sai kiểu không ném, về false', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'ready',
          'aimLocked': 'not-a-bool',
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimLocked, isFalse);
    });
  });

  group('isAvailable', () {
    // Thiếu plugin (chạy trên máy không phải iOS, hoặc gói chưa đăng ký) phải trả
    // false chứ KHÔNG ném: app gọi hàm này để quyết định ẩn hay hiện một nút.
    test('kênh ném thì trả false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => throw MissingPluginException(),
          );

      expect(await ArMeasure.isAvailable(), isA<ArAvailability>());
      expect((await ArMeasure.isAvailable()).arSupported, isFalse);
    });
  });

  group('ArMeasureController', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async {
              calls.add(call);
              return call.method == 'placePoint' ? 'placed' : null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            null,
          );
    });

    // Sáu lệnh, và MỖI lệnh phải chở theo viewId. Thiếu id thì tầng Swift
    // không tra được view nào trong sổ đăng ký, và lệnh rơi vào chỗ trống mà
    // không có gì nổ — đúng dạng lỗi câm mà ca kiểm này tồn tại để chặn.
    test('mọi lệnh gửi đúng tên và kèm viewId', () async {
      const c = ArMeasureController(7);

      await c.placePoint();
      await c.undoPoint();
      await c.reset();
      await c.pause();
      await c.resume();
      await c.dispose();

      expect(calls.map((c) => c.method), [
        'placePoint',
        'undoPoint',
        'reset',
        'pause',
        'resume',
        'dispose',
      ]);
      for (final call in calls) {
        expect(call.arguments, {'viewId': 7});
      }
    });

    // Bốn kết quả, và ba trong bốn là "không có điểm nào đặt" vì ba lý do KHÁC
    // NHAU. Một `bool` gộp cả ba lại thành một câu duy nhất, mà ba lời khuyên
    // đúng thì ngược nhau: rê máy tìm bề mặt, chờ phiên bám lại, hay bấm Chốt.
    test('placePoint đọc được cả bốn kết quả tầng nền nói', () async {
      Future<ArMeasurePlaceResult> place(Object? reply) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              (call) async => reply,
            );
        return const ArMeasureController(1).placePoint();
      }

      expect(await place('placed'), ArMeasurePlaceResult.placed);
      expect(await place('missed'), ArMeasurePlaceResult.missed);
      expect(await place('notReady'), ArMeasurePlaceResult.notReady);
      expect(
        await place('alreadyComplete'),
        ArMeasurePlaceResult.alreadyComplete,
      );
    });

    // Nền tảng trả null (vd. một bản Swift cũ chỉ biết trả `bool`), trả một
    // chuỗi lạ, hoặc không có plugin nào để trả: cả ba đều là KHÔNG có điểm nào
    // đặt, và lời khuyên duy nhất không sai ở đó là "chưa chấm được" — chứ
    // không phải "rê máy tìm bề mặt", vì rê cả ngày cũng không cứu một kênh
    // chết.
    test('placePoint không đọc được thì về notReady, không ném', () async {
      Future<ArMeasurePlaceResult> place(
        Future<Object?> Function(MethodCall) handler,
      ) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              handler,
            );
        return const ArMeasureController(1).placePoint();
      }

      expect(await place((_) async => null), ArMeasurePlaceResult.notReady);
      expect(
        await place((_) async => 'sao chổi'),
        ArMeasurePlaceResult.notReady,
      );
      expect(await place((_) async => true), ArMeasurePlaceResult.notReady);
      expect(
        await place((_) async => throw MissingPluginException()),
        ArMeasurePlaceResult.notReady,
      );
      expect(
        await place((_) async => throw PlatformException(code: 'boom')),
        ArMeasurePlaceResult.notReady,
      );
    });

    test('thiếu plugin: lệnh khác không ném', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => throw MissingPluginException(),
          );

      const c = ArMeasureController(1);
      await expectLater(c.undoPoint(), completes);
      await expectLater(c.reset(), completes);
      await expectLater(c.pause(), completes);
      await expectLater(c.resume(), completes);
      await expectLater(c.dispose(), completes);
    });

    test('nền tảng ném PlatformException thì cũng không ném ra', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => throw PlatformException(code: 'boom'),
          );

      await expectLater(const ArMeasureController(1).dispose(), completes);
    });
  });

  group('samples', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(ArMeasure.eventChannelName),
            null,
          );
    });

    test('khung hợp lệ thành ArMeasureSample', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(ArMeasure.eventChannelName),
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({
                  'status': 'measured',
                  'mm': 812.0,
                  'tolMm': 12.0,
                  'snappedToEdge': false,
                });
              },
            ),
          );

      final got = await ArMeasure.samples.first;

      expect(got.status, ArMeasureStatus.measured);
      expect(got.measurement?.mm, 812);
      expect(got.measurement?.tolMm, 12);
    });

    // Một khung hỏng KHÔNG được giết luồng. Luồng này nuôi màn hình đang đo:
    // nó chết thì màn đông cứng ở khung cuối, và không có gì trên màn nói ra.
    test('khung hỏng bị bỏ, khung sau vẫn tới', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(ArMeasure.eventChannelName),
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({'status': 'vệ tinh'});
                sink.success('không phải map');
                sink.error(code: 'boom');
                sink.success({'status': 'ready'});
              },
            ),
          );

      final got = <ArMeasureSample>[];
      final sub = ArMeasure.samples.listen(got.add);
      await pumpEventQueue();
      await sub.cancel();

      expect(got.map((s) => s.status), [ArMeasureStatus.ready]);
    });
  });
}
