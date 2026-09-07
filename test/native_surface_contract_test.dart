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

  group('tâm ngắm tự nói', () {
    test('lượt dò dùng ĐÚNG tia mà placePoint dùng', () {
      expect(
        _swiftMethodBody(sessionSource, 'private func refreshAimLock('),
        contains('raycastFromReticle()'),
        reason:
            'Cờ ngắm là một lời hứa về cú bấm SẮP TỚI. Dò bằng một tia khác — '
            'khác tầng mục tiêu, khác alignment, khác điểm bắn — là hứa một '
            'đằng làm một nẻo: tâm ngắm khoá lại, người dùng bấm, và không có '
            'gì xảy ra. Đúng cái hỏng máy thật báo về.',
      );
    });

    test('khung hình chạy lượt dò TRƯỚC lối rẽ hai điểm', () {
      final body = _swiftMethodBody(
        sessionSource,
        'func session(_ session: ARSession, didUpdate frame: ARFrame)',
      );

      expect(
        body,
        contains('refreshAimLock('),
        reason:
            'Đây là nguồn khung hình duy nhất của lớp. Bản trước chặn sớm bằng '
            '`guard anchors.count == 2` — tức là ở đúng quãng người dùng còn '
            'đang ngắm điểm ĐẦU TIÊN thì không có lượt dò nào chạy, và tâm '
            'ngắm không bao giờ nói được gì.',
      );
      expect(
        body.indexOf('refreshAimLock('),
        lessThan(body.indexOf('anchors.count == 2')),
        reason:
            'Lượt dò phải chạy trước lối rẽ hai điểm. Đặt sau thì nó nằm trong '
            'nhánh chỉ tới khi đã đo xong — đúng lúc cờ này hết nghĩa.',
      );
    });

    test('lượt dò có nhịp RIÊNG, không đi theo nhịp bắn', () {
      expect(
        sessionSource,
        contains('aimProbeIntervalSeconds'),
        reason:
            'Raycast là việc thật, không phải đọc một biến. Để nó chạy mỗi '
            'khung hình là gánh 60 lượt/giây cho một giá trị BOOLEAN mà mắt '
            'người không đọc nổi quá 10 lần/giây.',
      );
    });

    test('cờ ngắm đổi thì KHÔNG bị bộ giãn nhịp nuốt', () {
      expect(
        // Gộp khoảng trắng: điều kiện này dài quá một dòng, và chỗ trình định
        // dạng Swift ngắt dòng không phải thứ ca kiểm này canh.
        sessionSource.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'if !force, status == lastStatus, '
          'limitedReason == lastLimitedReason, aimLocked == lastAimLocked {',
        ),
        reason:
            'Bộ giãn nhịp neo vào "số đo đổi quá 0,5 mm". Cờ ngắm đổi từ false '
            'sang true KHÔNG đổi số đo nào — chưa có điểm nào để đo — nên nếu '
            'nó không nằm trong điều kiện gộp này thì lượt khoá đầu tiên bị '
            'nuốt trọn, và tâm ngắm câm đúng lúc nó cần nói nhất.',
      );
    });
  });

  group('cấu hình ARKit', () {
    test('lấy nét tự động đặt tường minh, không trông vào mặc định', () {
      expect(
        sessionSource,
        contains('config.isAutoFocusEnabled = true'),
        reason:
            'Tầm đo gần (0,3–1 m) là đúng chỗ một tiêu cự cố định làm ảnh nhoè '
            'và ARKit mất sạch điểm đặc trưng. Mặc định của Apple hôm nay là '
            'true, nhưng mặc định không phải hợp đồng.',
      );
    });

    test('KHÔNG bật environmentTexturing', () {
      expect(
        sessionSource,
        isNot(contains('config.environmentTexturing =')),
        reason:
            'Nó dựng probe ánh sáng cho phản chiếu trên vật ảo. Gói vẽ hai quả '
            'cầu `.constant` không nhận đèn — không có gì để phản chiếu, và nó '
            'không đụng gì tới dò mặt phẳng hay raycast. Bật là trả tiền GPU '
            'cho không.',
      );
    });

    test('KHÔNG bật frameSemantics', () {
      expect(
        sessionSource,
        isNot(contains('config.frameSemantics =')),
        reason:
            '`.sceneDepth` chỉ mở `ARFrame.sceneDepth` cho app tự đọc — raycast '
            'của ARKit đã ăn lưới qua `sceneReconstruction`. `.personSegmentation` '
            'là che khuất người, mà gói không có gì để che. Không cái nào làm '
            'tia trúng thêm một lần nào.',
      );
    });

    test('hai tầng tia, đúng thứ tự, và KHÔNG có tầng mặt phẳng vô hạn', () {
      expect(
        sessionSource,
        contains(
          'let targets: [ARRaycastQuery.Target] = [.existingPlaneGeometry, .estimatedPlane]',
        ),
        reason:
            '`.existingPlaneInfinite` sẽ "cứu" được cảnh trong ảnh máy thật — '
            'nó kéo dài mặt bàn xuyên qua cái iPad và trả về một điểm. Nhưng '
            'điểm ấy nằm ở CAO ĐỘ MẶT BÀN chứ không phải mặt iPad, và chĩa vào '
            'tường xa thì nó trả một điểm đâu đó dọc mặt sàn kéo dài. Một con '
            'số trông bình thường mà sai là dạng hỏng tệ nhất của gói này.',
      );
    });
  });
}

/// Thân một phương thức Swift, từ chữ ký tới dấu đóng ở cột 2.
///
/// Mọi phương thức trong `ArMeasureSession.swift` thụt hai mức, nên `\n  }` là
/// dấu đóng của chính nó và không thể là dấu đóng của một khối lồng bên trong.
String _swiftMethodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: 'không tìm thấy `$signature` trong ArMeasureSession.swift',
  );

  final end = source.indexOf('\n  }', start);
  expect(
    end,
    greaterThan(start),
    reason: 'không tìm được dấu đóng của `$signature`',
  );

  return source.substring(start, end);
}
