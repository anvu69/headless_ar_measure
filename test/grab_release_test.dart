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
