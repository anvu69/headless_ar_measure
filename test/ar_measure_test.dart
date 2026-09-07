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
              return call.method == 'placePoint' ? true : null;
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

    test('placePoint trả về đúng cái nền tảng nói', () async {
      expect(await const ArMeasureController(1).placePoint(), isTrue);
    });

    // Nền tảng trả null (vd. một bản Swift cũ chưa có giá trị trả về) không
    // được thành "đã chấm được": mặc định phải là KHÔNG có điểm nào đặt.
    test('placePoint trả null thì thành false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => null,
          );

      expect(await const ArMeasureController(1).placePoint(), isFalse);
    });

    test('thiếu plugin: placePoint trả false, lệnh khác không ném', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => throw MissingPluginException(),
          );

      const c = ArMeasureController(1);
      expect(await c.placePoint(), isFalse);
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

      expect(await const ArMeasureController(1).placePoint(), isFalse);
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
