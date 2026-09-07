import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // s.version của podspec KHÔNG tự lấy từ pubspec, và ở gói cùng nhà nó đã lệch.
  // Số lệch đi thẳng vào Podfile.lock của app rồi nằm đó.
  test('podspec và pubspec cùng một số phiên bản', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final podspec = File('ios/headless_ar_measure.podspec').readAsStringSync();

    final v = RegExp(
      r'^version:\s*(.+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!.trim();

    expect(podspec, contains("s.version = '$v'"));
  });
}
