import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ghim những luật của tầng Swift mà **không lỗi nào nổ** khi bị phá.
///
/// Mỗi ca dưới đây canh đúng một hỏng CÂM đã xảy ra thật một lần trên máy thật:
/// bề mặt AR vẫn dựng, kênh vẫn chạy, không có ngoại lệ nào, và thứ người dùng
/// thấy là một màn không có gì. Không có ca nào ở đây thay được một lượt cầm
/// iPhone — nhưng mỗi ca giữ được một lượt hồi quy mà `flutter test` bắt được
/// còn iPhone thì phải cầm mới biết.
///
/// Đọc thẳng tệp Swift từ đĩa, cùng lối với `status_contract_test.dart`.
void main() {
  final sessionSource = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/ArMeasureSession.swift',
  ).readAsStringSync();
  final viewSource = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/ArMeasurePlatformView.swift',
  ).readAsStringSync();

  group('quyền camera', () {
    test('xin quyền TRƯỚC khi chạy phiên, không để ARKit tự xin', () {
      expect(
        sessionSource,
        contains('AVCaptureDevice.requestAccess(for: .video)'),
        reason:
            'Lần chạy đầu trên máy thật đi qua `.notDetermined`. Gọi thẳng '
            '`session.run` ở đó là dựng đường ống camera phụ thuộc một lượt cấp '
            'quyền xảy ra SAU nó, và không callback nào của ARSession báo là nó '
            'đã không dựng — bề mặt AR trong suốt, người dùng thấy nền app.',
      );
    });

    test('`.notDetermined` KHÔNG đi chung nhánh với `.authorized`', () {
      expect(
        sessionSource,
        isNot(contains('case .notDetermined, .authorized:')),
        reason:
            'Gộp hai giá trị này là đúng cái lỗi đã làm màn đen: "chưa hỏi" bị '
            'đối xử y như "đã cho phép".',
      );
    });

    test('callback xin quyền bắt `self` YẾU', () {
      expect(
        sessionSource,
        contains('AVCaptureDevice.requestAccess(for: .video) { [weak self] '),
        reason:
            'Luật vòng đời số 2. Hộp thoại quyền có thể đứng lâu hơn màn AR, và '
            'bắt mạnh ở đây là giữ cả ARSCNView (kèm camera) sống qua lượt người '
            'dùng đã thoát ra.',
      );
    });
  });

  group('bề mặt chỉ để nhìn', () {
    test('ARSCNView không nhận cú chạm nào', () {
      expect(
        sessionSource,
        contains('sceneView.isUserInteractionEnabled = false'),
        reason:
            'Mọi thao tác của màn đo là nút Flutter nằm đè lên bề mặt này. Để '
            'bề mặt nhận chạm là để `hitTest` của UIKit dừng lại ở một view '
            'không có gì để làm với cú chạm ấy.',
      );
    });

    test('factory giữ plugin MẠNH', () {
      expect(
        viewSource,
        isNot(contains('weak var plugin')),
        reason:
            '`create` là chỗ DUY NHẤT nối view mới vào sổ đăng ký của plugin. '
            'Một `plugin?` bằng nil ở đó làm luồng trạng thái câm hoàn toàn mà '
            'không có lỗi nào nổ. Giữ mạnh không dựng nổi vòng: plugin không trỏ '
            'ngược về factory.',
      );
    });
  });

  group('thứ gói tự vẽ', () {
    test('vật liệu hình đo KHÔNG cần đèn', () {
      expect(
        sessionSource,
        contains('material.lightingModel = .constant'),
        reason:
            'Phiên đặt `automaticallyUpdatesLighting = false`, nên cảnh không có '
            'đèn nào. Vật liệu mặc định (`.blinn`) ra màu đen tuyền trên nền '
            'camera — vẽ rồi mà trông y hệt chưa vẽ.',
      );
    });

    test('hình đo không bị hình học của ARKit che', () {
      expect(
        sessionSource,
        contains('material.readsFromDepthBuffer = false'),
        reason:
            'Lưới LiDAR và mặt phẳng ARKit dò ra nằm giữa máy và điểm chấm. Đọc '
            'bộ đệm sâu là để chúng cắt mất hai chấm và đoạn nối.',
      );
    });

    test('đoạn nối chịu được hai đầu ngược chiều nhau', () {
      expect(
        sessionSource,
        contains('isNaN'),
        reason:
            'Đo chiều cao từ trên xuống cho ra hướng −Y, chỗ trục xoay không xác '
            'định. Một transform NaN thì SceneKit bỏ vẽ, im lặng.',
      );
    });
  });

  group('hướng dẫn quét bề mặt', () {
    test('dùng ARCoachingOverlayView của Apple, gắn vào đúng phiên', () {
      expect(sessionSource, contains('ARCoachingOverlayView()'));
      expect(
        sessionSource,
        contains('coachingOverlay.session = sceneView.session'),
        reason:
            'Không gắn phiên thì lớp phủ không có gì để theo dõi: nó không bao '
            'giờ bật, và cũng không bao giờ báo lỗi.',
      );
    });

    test('tự bật tự tắt, và nhắm mặt phẳng bất kỳ', () {
      expect(
        sessionSource,
        contains('coachingOverlay.activatesAutomatically = true'),
        reason:
            'Apple biết lúc nào phiên đủ dữ liệu để thôi nhắc; gói thì không.',
      );
      expect(
        sessionSource,
        contains('coachingOverlay.goal = .anyPlane'),
        reason:
            'Cấu hình bật dò cả mặt ngang lẫn mặt đứng. Nhắm riêng mặt ngang thì '
            'người đo tường bị nhắc mãi một thứ không bao giờ tới.',
      );
    });

    test('gỡ khỏi phiên khi dừng', () {
      expect(
        sessionSource,
        contains('coachingOverlay.session = nil'),
        reason:
            'Để nguyên thì lớp phủ còn theo dõi một phiên đã tắt và tự bật lên '
            'trên một bề mặt không còn ai nhìn.',
      );
    });
  });
}
