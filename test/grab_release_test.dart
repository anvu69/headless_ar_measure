import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';

/// NẮM — KÉO — BUÔNG: mặt Dart của cặp lệnh, và các luật đi kèm nó.
///
/// Vì sao cặp lệnh này tồn tại, nguyên văn lượt máy thật: *"chiếu hồng tâm vào
/// đầu mút thì hiện lên chức năng Dời đầu này. Tuy nhiên cách dùng khó chịu, nó
/// không phải nắm lấy điểm đó và kéo cho đến khi buông ra, mà nhấn vào nút Dời
/// đầu này là chỉ nhích được một khoảng. Phải làm cho nó thực tế giống như
/// chỉnh 2 đầu của một chiếc thước dây vậy."*
///
/// `movePoint` vẫn còn và không đổi hành vi: nó là một nhát dời, còn cặp lệnh
/// này là một quãng nắm. Hai đường, một chỗ chốt điểm — xem
/// `native_surface_contract_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArMeasureGrabResult', () {
    // Bốn kết quả, và ba trong bốn là "không nắm được gì" vì ba lý do KHÁC
    // NHAU. Câu đi kèm chúng ngược nhau: đợi phiên bám lại, chọn lại một đầu,
    // hay buông cái đang cầm trước đã.
    test('grabPoint đọc được cả bốn kết quả tầng nền nói', () async {
      Future<ArMeasureGrabResult> grab(Object? reply) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              (call) async => reply,
            );
        return const ArMeasureController(1).grabPoint(0);
      }

      expect(await grab('grabbed'), ArMeasureGrabResult.grabbed);
      expect(await grab('notReady'), ArMeasureGrabResult.notReady);
      expect(await grab('noSuchPoint'), ArMeasureGrabResult.noSuchPoint);
      expect(await grab('alreadyGrabbing'), ArMeasureGrabResult.alreadyGrabbing);
    });

    // Giá trị canh gác là `notReady`, KHÔNG phải `noSuchPoint` — cùng một luật
    // với `movePoint`. Một kênh câm không biết app đang có mấy điểm, nên trả
    // lời thay nó là nói dối app về dữ liệu của chính app, và app tin thì cái
    // nút nắm biến mất vĩnh viễn cho một điểm nó đang vẽ trên màn.
    test('grabPoint không đọc được thì về notReady, không ném', () async {
      Future<ArMeasureGrabResult> grab(
        Future<Object?> Function(MethodCall) handler,
      ) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              handler,
            );
        return const ArMeasureController(1).grabPoint(0);
      }

      expect(await grab((_) async => null), ArMeasureGrabResult.notReady);
      expect(await grab((_) async => 'sao chổi'), ArMeasureGrabResult.notReady);
      expect(await grab((_) async => true), ArMeasureGrabResult.notReady);
      expect(
        await grab((_) async => throw MissingPluginException()),
        ArMeasureGrabResult.notReady,
      );
      expect(
        await grab((_) async => throw PlatformException(code: 'boom')),
        ArMeasureGrabResult.notReady,
      );
    });

    // Cùng luật với `movePoint`: khoảng chỉ số hợp lệ là chuyện của tầng Swift,
    // nơi DUY NHẤT biết đang có mấy điểm. Dart chặn thêm một lượt là một bản
    // chép của luật ấy, và bản chép lệch ngay lượt đầu ai đó đổi số điểm.
    test('grabPoint KHÔNG tự quyết chỉ số nào hợp lệ', () async {
      final sent = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async {
              sent.add(call);
              return 'noSuchPoint';
            },
          );

      const c = ArMeasureController(3);
      expect(await c.grabPoint(-1), ArMeasureGrabResult.noSuchPoint);
      expect(await c.grabPoint(99), ArMeasureGrabResult.noSuchPoint);

      expect(sent.map((c) => c.arguments), [
        {'viewId': 3, 'index': -1},
        {'viewId': 3, 'index': 99},
      ]);
    });
  });

  group('điểm ngắm của một quãng nắm', () {
    /// Khuôn dây CŨ không đổi một chữ.
    ///
    /// `grabPoint(0)` là lời gọi của mọi bản trước `0.14.0`, và nó phải gửi
    /// đúng hai khoá như cũ. Gửi kèm `x`/`y` bằng tâm màn "cho đủ bộ" là một
    /// lượt đổi hành vi câm: tầng Swift sẽ bắn TIA RIÊNG mỗi khung thay vì ăn
    /// theo lượt dò của tâm ngắm, và cái giá — một lượt raycast thứ hai mỗi
    /// khung hình — không ai xin.
    test('grabPoint không kèm điểm thì gửi đúng khuôn dây cũ', () async {
      final sent = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async {
              sent.add(call);
              return 'grabbed';
            },
          );

      expect(await const ArMeasureController(3).grabPoint(0),
          ArMeasureGrabResult.grabbed);
      expect(sent.single.arguments, {'viewId': 3, 'index': 0});
    });

    /// Điểm đi trên dây thành HAI số `x`/`y`, đơn vị **point**.
    ///
    /// Không nhân `devicePixelRatio` ở bất cứ đâu trên đường này: `bounds` của
    /// bề mặt AR là point, phép chiếu bắn lên `ArMeasureOverlay` là point, và
    /// con số này phải cùng hệ với chúng — nếu không thì app đọc toạ độ đầu mút
    /// từ lớp phủ rồi gửi trả lại một toạ độ ở hệ khác.
    test('grabPoint kèm điểm gửi x/y point, không nhân hệ số điểm ảnh',
        () async {
      final sent = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async {
              sent.add(call);
              return 'grabbed';
            },
          );

      expect(
        await const ArMeasureController(3)
            .grabPoint(1, at: const Offset(120.5, 200.25)),
        ArMeasureGrabResult.grabbed,
      );
      expect(sent.single.arguments, {
        'viewId': 3,
        'index': 1,
        'x': 120.5,
        'y': 200.25,
      });
    });

    test('dragTo gửi x/y và KHÔNG gửi chỉ số', () async {
      final sent = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async {
              sent.add(call);
              return 'aimed';
            },
          );

      expect(
        await const ArMeasureController(7).dragTo(const Offset(-3, 0.5)),
        ArMeasureDragResult.aimed,
      );
      expect(sent.single.method, 'dragTo');
      expect(sent.single.arguments, {'viewId': 7, 'x': -3.0, 'y': 0.5});
    });

    // Bốn kết quả, và `clamped` là giá trị đắt nhất của bộ: ngón tay trượt ra
    // ngoài mép màn giữa một quãng kéo là chuyện thường, và ở đó gói KẸP điểm
    // vào biên chứ không coi là trượt. App có quyền biết mình đang kéo một thứ
    // ghim ở mép.
    test('dragTo đọc được cả bốn kết quả tầng nền nói', () async {
      Future<ArMeasureDragResult> drag(Object? reply) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              (call) async => reply,
            );
        return const ArMeasureController(1).dragTo(Offset.zero);
      }

      expect(await drag('aimed'), ArMeasureDragResult.aimed);
      expect(await drag('clamped'), ArMeasureDragResult.clamped);
      expect(await drag('notGrabbing'), ArMeasureDragResult.notGrabbing);
      expect(await drag('notReady'), ArMeasureDragResult.notReady);
    });

    // Kênh câm về `notReady`, KHÔNG về `notGrabbing` — cùng một luật với
    // `releasePoint`: "không nắm gì" là một câu về TRẠNG THÁI của một phiên, và
    // một kênh chết không có phiên nào để nói về. Cũng là giá trị của một bản
    // Swift cũ hơn lệnh này, nơi `dragTo` rơi vào `FlutterMethodNotImplemented`.
    test('dragTo không đọc được thì về notReady, không ném', () async {
      Future<ArMeasureDragResult> drag(
        Future<Object?> Function(MethodCall) handler,
      ) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              handler,
            );
        return const ArMeasureController(1).dragTo(Offset.zero);
      }

      expect(await drag((_) async => null), ArMeasureDragResult.notReady);
      expect(await drag((_) async => 'sao chổi'), ArMeasureDragResult.notReady);
      expect(await drag((_) async => true), ArMeasureDragResult.notReady);
      expect(
        await drag((_) async => throw MissingPluginException()),
        ArMeasureDragResult.notReady,
      );
      expect(
        await drag((_) async => throw PlatformException(code: 'boom')),
        ArMeasureDragResult.notReady,
      );
    });

    // Vì sao trường này phải tồn tại RIÊNG, không đọc nhờ `aimLocked`: từ
    // `0.14.0` hai thứ ấy nói về HAI TIA khác nhau. `aimLocked` nói về tâm màn
    // — nơi cú bấm `placePoint` tới — còn cái này nói về tia mà đầu mút đang bị
    // kéo đi theo. Ngón tay không ở tâm màn thì hai câu ấy khác nhau, và đọc
    // nhầm là app tô xám cái nút chấm vì một chỗ nó không định chấm.
    test('grabAimLocked đọc được từ mẫu', () {
      final sample = ArMeasure.parseSample({
        'status': 'measured',
        'grabbedPointIndex': 1,
        'grabAimLocked': true,
      });

      expect(sample!.grabAimLocked, isTrue);
    });

    // Thiếu khoá là "tia của quãng kéo không trúng gì", đúng mặc định an toàn:
    // một bản Swift cũ hơn trường này không gửi khoá, và ở đó nó cũng không có
    // đường nào để nắm theo một điểm ngắm riêng.
    test('thiếu khoá thì grabAimLocked là false', () {
      final sample = ArMeasure.parseSample({'status': 'measured'});

      expect(sample!.grabAimLocked, isFalse);
    });

    test('kiểu lạ thì về false, và KHÔNG giết mẫu', () {
      final sample = ArMeasure.parseSample({
        'status': 'measured',
        'grabAimLocked': 'có',
      });

      expect(sample, isNotNull);
      expect(sample!.grabAimLocked, isFalse);
    });
  });

  group('ArMeasureReleaseResult', () {
    // Bốn kết quả, và `unmoved` là giá trị ĐẮT nhất của bộ: người dùng vừa nắm,
    // vừa rê máy một quãng, rồi buông — và điểm vẫn nằm nguyên chỗ cũ vì KHÔNG
    // khung nào trong cả quãng ấy bắt được bề mặt. Gộp nó vào `released` là để
    // màn báo "đã dời" cho một cú dời chưa hề xảy ra.
    test('releasePoint đọc được cả bốn kết quả tầng nền nói', () async {
      Future<ArMeasureReleaseResult> release(Object? reply) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              (call) async => reply,
            );
        return const ArMeasureController(1).releasePoint();
      }

      expect(await release('released'), ArMeasureReleaseResult.released);
      expect(await release('unmoved'), ArMeasureReleaseResult.unmoved);
      expect(await release('notGrabbing'), ArMeasureReleaseResult.notGrabbing);
      expect(await release('notReady'), ArMeasureReleaseResult.notReady);
    });

    // Kênh câm về `notReady`, KHÔNG về `notGrabbing`. Hai giá trị ấy nói hai
    // chuyện khác nhau, y hệt cặp `notReady`/`noSuchPoint` của `movePoint`:
    // `notGrabbing` là một câu về TRẠNG THÁI của phiên ("không có gì trong
    // tay"), mà một kênh chết không biết gì về trạng thái ấy.
    test('releasePoint không đọc được thì về notReady, không ném', () async {
      Future<ArMeasureReleaseResult> release(
        Future<Object?> Function(MethodCall) handler,
      ) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              handler,
            );
        return const ArMeasureController(1).releasePoint();
      }

      expect(await release((_) async => null), ArMeasureReleaseResult.notReady);
      expect(
        await release((_) async => 'sao chổi'),
        ArMeasureReleaseResult.notReady,
      );
      expect(
        await release((_) async => throw MissingPluginException()),
        ArMeasureReleaseResult.notReady,
      );
      expect(
        await release((_) async => throw PlatformException(code: 'boom')),
        ArMeasureReleaseResult.notReady,
      );
    });
  });

  group('đầu mút đang nắm đi trên kênh TRẠNG THÁI', () {
    // Vì sao nó phải đi ra ngoài chứ không để app tự nhớ từ giá trị trả về của
    // `grabPoint`: gói tự BUÔNG ở những đường app không gây ra — phiên gián
    // đoạn, mất bám, `pause`, `reset`, `dispose`, hay ARKit bỏ chính cái anchor
    // đang nắm. App nhớ lấy một mình thì sau những lượt ấy nó còn vẽ "đang nắm
    // đầu A" cho một quãng nắm đã kết thúc, và cái nút buông không buông gì cả.
    test('grabbedPointIndex đọc được từ mẫu', () {
      final sample = ArMeasure.parseSample({
        'status': 'measured',
        'grabbedPointIndex': 1,
      });

      expect(sample!.grabbedPointIndex, 1);
    });

    // Thiếu khoá là "không nắm gì", đúng mặc định của mọi bản trước cặp lệnh
    // này. Một bản Swift cũ hơn trường này không gửi khoá, và ở đó `null` là
    // sự thật: bản ấy không có đường nào để nắm.
    test('thiếu khoá thì grabbedPointIndex là null', () {
      final sample = ArMeasure.parseSample({'status': 'measured'});

      expect(sample!.grabbedPointIndex, isNull);
    });

    // Sai kiểu bị coi như thiếu — cùng một lối rẽ với mọi khoá phụ khác của
    // mẫu, và KHÔNG giết cả mẫu: mất một mẫu vì một trường trang trí là để màn
    // đo đứng im ở khung hình cuối.
    test('kiểu lạ thì về null, và KHÔNG giết mẫu', () {
      final sample = ArMeasure.parseSample({
        'status': 'measured',
        'grabbedPointIndex': 'đầu A',
      });

      expect(sample, isNotNull);
      expect(sample!.grabbedPointIndex, isNull);
    });
  });

  group('hai chuỗi mới khớp từng chữ giữa Swift và Dart', () {
    final swift = File(
      'ios/headless_ar_measure/Sources/headless_ar_measure/ArMeasureSession.swift',
    ).readAsStringSync();

    // Cùng cái bẫy với `ArMeasureMoveResult`, và ở đây chiều hỏng còn câm hơn:
    // một chuỗi lệch làm `grabPoint` trả `notReady` trong khi tầng Swift ĐÃ
    // nắm — app không vẽ trạng thái nắm, người dùng rê máy và thấy đầu mút chạy
    // theo mà không có cách nào buông.
    test('bốn chuỗi kết quả NẮM', () {
      expect(
        _swiftStringEnumCases(swift, 'ArMeasureGrabResult'),
        ArMeasureGrabResult.values.map((e) => e.name).toList(),
      );
    });

    test('bốn chuỗi kết quả BUÔNG', () {
      expect(
        _swiftStringEnumCases(swift, 'ArMeasureReleaseResult'),
        ArMeasureReleaseResult.values.map((e) => e.name).toList(),
      );
    });

    // Cùng cái bẫy, và ở đây chiều hỏng câm nhất là `clamped`: một chuỗi lệch
    // làm mọi lượt kéo ra mép màn trả `notReady`, app tưởng kênh chết và bỏ
    // luôn quãng kéo — trong khi tầng Swift vẫn đang nắm và vẫn đang kéo.
    test('bốn chuỗi kết quả ĐIỂM NGẮM', () {
      expect(
        _swiftStringEnumCases(swift, 'ArMeasureDragResult'),
        ArMeasureDragResult.values.map((e) => e.name).toList(),
      );
    });
  });
}

/// Trích tên các `case` của một `enum <tên>: String` trong mã Swift — bản chép
/// của `status_contract_test.dart`, xem lời chú ở đó.
List<String> _swiftStringEnumCases(String source, String enumName) {
  final body = RegExp(
    'enum $enumName: String \\{([^}]*)\\}',
  ).firstMatch(source);
  expect(body, isNotNull, reason: 'không tìm thấy `enum $enumName: String`');

  return RegExp(
    r'^\s*case\s+(\w+)\s*$',
    multiLine: true,
  ).allMatches(body!.group(1)!).map((m) => m.group(1)!).toList();
}
