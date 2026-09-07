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

  /// Chẩn đoán: ảnh chụp của ĐIỀU KIỆN mỗi điểm được chấm.
  ///
  /// Cả nhóm này neo vào một chuyện đã trả giá: một cuộc điều tra mười sáu tác
  /// nhân bác sạch mọi giả thuyết về sai lệch số đo, và bác vì cùng một lý do
  /// ở mọi giả thuyết — mẫu bắn lên Dart không mang một mẩu nào về việc phép đo
  /// ĐÃ diễn ra thế nào, nên mọi lời giải đều khớp mọi số đo và không lời nào
  /// kiểm được.
  ///
  /// Luật của cả nhóm: **không đường nào được ném, không đường nào được giết
  /// mẫu**. Chẩn đoán là thứ đi kèm; một khoá hỏng ở đây mà làm mất cả mẫu thì
  /// tầng chẩn đoán tự nó thành một lỗi sản phẩm.
  group('parseSample · chẩn đoán', () {
    Map<Object?, Object?> diemDay({String target = 'existingPlaneGeometry'}) =>
        {
          'target': target,
          'tracking': 'normal',
          'sessionAgeMs': 4210,
          'cameraDistanceMm': 612.5,
          'rayAngleDeg': 63.25,
          'planeAlignment': 'horizontal',
          'planeWidthMm': 1200.0,
          'planeHeightMm': 800.0,
        };

    test('hai điểm, đủ trường, đúng THỨ TỰ chấm', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
        'snappedToEdge': false,
        'diagnostics': {
          'points': [diemDay(), diemDay(target: 'estimatedPlane')],
        },
      });

      final points = s?.diagnostics?.points;
      expect(points, hasLength(2));
      expect(points?[0].target, ArRaycastTarget.existingPlaneGeometry);
      expect(points?[0].tracking, ArTrackingSnapshot.normal);
      expect(points?[0].sessionAgeMs, 4210);
      expect(points?[0].cameraDistanceMm, 612.5);
      expect(points?[0].rayAngleDeg, 63.25);
      expect(points?[0].planeAlignment, ArPlaneAlignment.horizontal);
      expect(points?[0].planeWidthMm, 1200.0);
      expect(points?[0].planeHeightMm, 800.0);
      // Điểm thứ hai KHÁC điểm đầu ở đúng tầng trúng. Hai điểm giống hệt nhau
      // thì ca kiểm không phân biệt được "đọc đúng thứ tự" với "đọc điểm đầu
      // hai lần".
      expect(points?[1].target, ArRaycastTarget.estimatedPlane);
    });

    test('mới một điểm thì chẩn đoán cũng chỉ có một', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [diemDay()],
        },
      });

      expect(s?.diagnostics?.points, hasLength(1));
    });

    // Bản Swift cũ hơn tầng chẩn đoán không gửi khoá này. `null` chứ không
    // phải một đối tượng rỗng: rỗng đọc ra "đã đo và không có gì", còn `null`
    // đọc đúng nghĩa "bản nền này không nói".
    test('thiếu khoá thì diagnostics về null, mẫu vẫn sống', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
      });

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement?.mm, 812);
      expect(s?.diagnostics, isNull);
    });

    test('danh sách rỗng cũng về null, không phải một danh sách rỗng', () {
      final s = ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {'points': <Object?>[]},
      });

      expect(s?.diagnostics, isNull);
    });

    test('mặt ước lượng: không có mặt phẳng nào, ba khoá mp về null', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [
            {
              'target': 'estimatedPlane',
              'tracking': 'limitedInsufficientFeatures',
              'sessionAgeMs': 900,
              'cameraDistanceMm': 310.0,
              'rayAngleDeg': 12.0,
            },
          ],
        },
      });

      final p = s?.diagnostics?.points.single;
      expect(p?.target, ArRaycastTarget.estimatedPlane);
      expect(p?.tracking, ArTrackingSnapshot.limitedInsufficientFeatures);
      expect(p?.planeAlignment, isNull);
      expect(p?.planeWidthMm, isNull);
      expect(p?.planeHeightMm, isNull);
    });

    // Sáu nhánh bám tách nhau ra vì mỗi nhánh là một giả thuyết KHÁC về vì sao
    // một số đo lệch. Gộp cả năm nhánh `.limited` thành một chữ "limited" là
    // xoá đúng phần phân biệt được chúng.
    test('sáu nhánh trạng thái bám đọc ra sáu giá trị khác nhau', () {
      ArTrackingSnapshot? doc(String raw) => ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {
          'points': [
            {'tracking': raw},
          ],
        },
      })?.diagnostics?.points.single.tracking;

      expect(doc('normal'), ArTrackingSnapshot.normal);
      expect(
        doc('limitedInitializing'),
        ArTrackingSnapshot.limitedInitializing,
      );
      expect(
        doc('limitedExcessiveMotion'),
        ArTrackingSnapshot.limitedExcessiveMotion,
      );
      expect(
        doc('limitedInsufficientFeatures'),
        ArTrackingSnapshot.limitedInsufficientFeatures,
      );
      expect(
        doc('limitedRelocalizing'),
        ArTrackingSnapshot.limitedRelocalizing,
      );
      expect(doc('notAvailable'), ArTrackingSnapshot.notAvailable);
    });

    test('chuỗi lạ ở target/tracking/planeAlignment về null, không ném', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 812.0,
          'tolMm': 12.0,
          'diagnostics': {
            'points': [
              {
                'target': 'vệ tinh',
                'tracking': 'vệ tinh',
                'planeAlignment': 'vệ tinh',
              },
            ],
          },
        });
      }, returnsNormally);

      final p = s?.diagnostics?.points.single;
      expect(s?.measurement?.mm, 812, reason: 'khoá lạ không được giết số đo');
      expect(p?.target, isNull);
      expect(p?.tracking, isNull);
      expect(p?.planeAlignment, isNull);
    });

    test('số sai kiểu (chuỗi) về null, không ném', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'ready',
          'diagnostics': {
            'points': [
              {
                'sessionAgeMs': 'not-a-number',
                'cameraDistanceMm': 'not-a-number',
                'rayAngleDeg': 'not-a-number',
                'planeWidthMm': 'not-a-number',
                'planeHeightMm': 'not-a-number',
              },
            ],
          },
        });
      }, returnsNormally);

      final p = s?.diagnostics?.points.single;
      expect(p?.sessionAgeMs, isNull);
      expect(p?.cameraDistanceMm, isNull);
      expect(p?.rayAngleDeg, isNull);
      expect(p?.planeWidthMm, isNull);
      expect(p?.planeHeightMm, isNull);
    });

    test('diagnostics sai kiểu (không phải map) về null, mẫu vẫn sống', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 400.0,
          'tolMm': 6.0,
          'diagnostics': 'not-a-map',
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement?.mm, 400);
      expect(s?.diagnostics, isNull);
    });

    test('points sai kiểu (không phải danh sách) về null, mẫu vẫn sống', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 400.0,
          'tolMm': 6.0,
          'diagnostics': {'points': 'not-a-list'},
        });
      }, returnsNormally);

      expect(s?.measurement?.mm, 400);
      expect(s?.diagnostics, isNull);
    });

    // Một phần tử hỏng KHÔNG được rơi ra khỏi danh sách: rơi ra là điểm thứ
    // hai trượt lên chỗ điểm thứ nhất, và cả dải chẩn đoán nói dối về việc
    // điểm nào được chấm trong điều kiện nào — im lặng, không lỗi nào nổ.
    test('phần tử hỏng giữ NGUYÊN CHỖ, thành một điểm trống', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 400.0,
        'tolMm': 6.0,
        'diagnostics': {
          'points': ['not-a-map', diemDay(target: 'estimatedPlane')],
        },
      });

      final points = s?.diagnostics?.points;
      expect(points, hasLength(2));
      expect(points?[0].target, isNull);
      expect(points?[0].tracking, isNull);
      expect(
        points?[1].target,
        ArRaycastTarget.estimatedPlane,
        reason:
            'điểm thứ hai phải còn ở CHỖ THỨ HAI, không được trượt lên chỗ đầu',
      );
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
