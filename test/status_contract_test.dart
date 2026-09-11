import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';

/// Ghim các chuỗi đi qua ranh giới Swift↔Dart.
///
/// `ArMeasureStatus` bên Swift là một `enum ... : String`, nên `rawValue` của
/// mỗi case ĐÚNG BẰNG tên case. Bên Dart, `ArMeasure.parseSample` so từng chuỗi
/// ấy bằng tay. Hai danh sách khớp nhau hôm nay là chuyện tình cờ có người canh:
/// đổi một chữ ở một bên mà quên bên kia thì `parseSample` trả `null`, cả mẫu
/// bị bỏ, và **không có lỗi nào nổ** — màn đo đứng im ở khung hình cuối.
///
/// Ca kiểm này chạy trong `flutter test`, không cần iPhone: nó đọc thẳng tệp
/// Swift từ đĩa, y như `version_test.dart` đọc podspec.
void main() {
  final swift = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/ArMeasureSession.swift',
  ).readAsStringSync();

  test('tám chuỗi trạng thái khớp từng chữ giữa Swift và Dart', () {
    expect(
      _swiftStringEnumCases(swift, 'ArMeasureStatus'),
      ArMeasureStatus.values.map((e) => e.name).toList(),
      reason:
          'enum ArMeasureStatus bên Swift và bên Dart đã lệch — sửa CẢ HAI bên '
          'trong cùng một lượt, nếu không mọi mẫu sẽ bị parseSample bỏ im lặng',
    );
  });

  test('hai chuỗi lý do bám hạn chế khớp từng chữ giữa Swift và Dart', () {
    expect(
      _swiftStringEnumCases(swift, 'ArMeasureLimitedReason'),
      ArMeasureLimitedReason.values.map((e) => e.name).toList(),
      reason:
          'enum ArMeasureLimitedReason bên Swift và bên Dart đã lệch — lý do lạ '
          'bị parseSample bỏ về null, và màn mất cách nói đúng câu',
    );
  });

  // Cùng một cái bẫy: `placePoint` trả `rawValue` của enum Swift, và Dart so
  // chuỗi bằng tay. Lệch một chữ thì MỌI cú chấm — kể cả cú chấm thành công —
  // về `notReady`, và không có lỗi nào nổ: nút vẫn bấm được, điểm vẫn rơi
  // xuống, chỉ có câu trên màn là sai.
  test('bốn chuỗi kết quả chấm điểm khớp từng chữ giữa Swift và Dart', () {
    expect(
      _swiftStringEnumCases(swift, 'ArMeasurePlaceResult'),
      ArMeasurePlaceResult.values.map((e) => e.name).toList(),
      reason:
          'enum ArMeasurePlaceResult bên Swift và bên Dart đã lệch — mọi kết '
          'quả chấm điểm rơi về notReady, kể cả lúc điểm đã đặt xong',
    );
  });

  // Cùng cái bẫy lần nữa, và lần này hỏng theo chiều NGƯỢC lại mới là chiều
  // đắt: `movePoint` dời một điểm THẬT rồi trả một chuỗi lệch, Dart đọc ra
  // `notReady`, và app nói "chưa dời được" trong khi điểm vừa nhảy chỗ trên
  // màn. Con số và hình lại nói hai chuyện khác nhau — đúng dạng lỗi mà cả lệnh
  // này sinh ra để đóng.
  test('bốn chuỗi kết quả dời điểm khớp từng chữ giữa Swift và Dart', () {
    expect(
      _swiftStringEnumCases(swift, 'ArMeasureMoveResult'),
      ArMeasureMoveResult.values.map((e) => e.name).toList(),
      reason:
          'enum ArMeasureMoveResult bên Swift và bên Dart đã lệch — mọi kết quả '
          'dời rơi về notReady, kể cả lúc điểm đã đổi chỗ xong',
    );
  });

  // Ba enum của tầng chẩn đoán đi qua đúng cái ranh giới ấy, và hỏng theo cùng
  // một kiểu câm: một chuỗi lệch bị `parseSample` bỏ về `null`, dải chẩn đoán
  // in ra "?" ở đúng ô mà nó có dữ liệu, và không lỗi nào nổ. Tệ hơn nữa vì
  // chẩn đoán tồn tại để CHỨNG MINH một giả thuyết — một trường câm ở đây làm
  // hỏng đúng lượt điều tra mà nó sinh ra để phục vụ.

  test('ba chuỗi tầng mục tiêu của tia khớp từng chữ giữa Swift và Dart', () {
    expect(
      _swiftStringEnumCases(swift, 'ArRaycastTarget'),
      ArRaycastTarget.values.map((e) => e.name).toList(),
      reason:
          'enum ArRaycastTarget bên Swift và bên Dart đã lệch — tầng trúng của '
          'mỗi điểm đọc ra null, đúng thứ phân biệt "mặt phẳng đã xác nhận" với '
          '"mặt phẳng đoán ra"',
    );
  });

  test('sáu chuỗi trạng thái bám khớp từng chữ giữa Swift và Dart', () {
    expect(
      _swiftStringEnumCases(swift, 'ArTrackingSnapshot'),
      ArTrackingSnapshot.values.map((e) => e.name).toList(),
      reason:
          'enum ArTrackingSnapshot bên Swift và bên Dart đã lệch — trạng thái '
          'bám lúc bấm đọc ra null, và giả thuyết "máy chưa ấm" mất chỗ dựa',
    );
  });

  // Lệnh `setLabel` đi đúng cái ranh giới ấy, và nó hỏng theo chiều CÂM NHẤT
  // trong cả tệp này: một chuỗi lệch làm mọi lượt dán ảnh đọc ra `notReady`
  // trong khi tấm ảnh đã nằm trên đoạn thẳng rồi. App tin lời ấy sẽ gửi lại,
  // mỗi khung hình, mãi mãi — và thứ duy nhất lộ ra là hoá đơn pin.
  test('ba chuỗi kết quả dán ảnh khớp từng chữ giữa Swift và Dart', () {
    expect(
      _swiftStringEnumCases(swift, 'ArMeasureLabelResult'),
      ArMeasureLabelResult.values.map((e) => e.name).toList(),
      reason:
          'enum ArMeasureLabelResult bên Swift và bên Dart đã lệch — mọi lượt '
          'dán ảnh rơi về notReady, kể cả lúc ảnh đã nằm trên đoạn',
    );
  });

  test('hai chuỗi phương của mặt phẳng khớp từng chữ giữa Swift và Dart', () {
    expect(
      _swiftStringEnumCases(swift, 'ArPlaneAlignment'),
      ArPlaneAlignment.values.map((e) => e.name).toList(),
      reason:
          'enum ArPlaneAlignment bên Swift và bên Dart đã lệch — mặt phẳng trúng '
          'đọc ra "không có mặt phẳng", đúng cái nhầm mà chẩn đoán đi phân biệt',
    );
  });
}

/// Trích tên các `case` của một `enum <tên>: String` trong mã Swift.
///
/// Chỉ nhận dòng `case <tên>` trần. Một case có `rawValue` viết tay
/// (`case foo = "bar"`) KHÔNG khớp, nên nó rơi ra khỏi danh sách và ca kiểm đỏ
/// — đúng điều mong muốn: lúc ấy tên case không còn là chuỗi đi trên kênh nữa.
List<String> _swiftStringEnumCases(String source, String enumName) {
  final body = RegExp(
    'enum $enumName: String \\{([^}]*)\\}',
  ).firstMatch(source);
  expect(
    body,
    isNotNull,
    reason:
        'không tìm thấy `enum $enumName: String` trong ArMeasureSession.swift',
  );

  return RegExp(
    r'^\s*case\s+(\w+)\s*$',
    multiLine: true,
  ).allMatches(body!.group(1)!).map((m) => m.group(1)!).toList();
}
