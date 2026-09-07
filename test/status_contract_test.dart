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
