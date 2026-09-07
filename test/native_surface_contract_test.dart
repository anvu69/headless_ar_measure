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

  /// Tầng chẩn đoán: mỗi điểm mang theo ĐIỀU KIỆN nó được chấm.
  ///
  /// Cả nhóm này canh những chỗ mà sai thì **dải chẩn đoán vẫn hiện đủ số, chỉ
  /// là số sai** — dạng hỏng tệ nhất có thể có ở một tầng sinh ra để làm bằng
  /// chứng. Một dải chẩn đoán nói dối còn tệ hơn không có dải nào: nó bác oan
  /// một giả thuyết đúng, và không ai soi lại được vì con số trông hợp lý.
  group('chẩn đoán từng điểm', () {
    test('tia trả về CẢ kết quả raycast, không phải mỗi transform', () {
      expect(
        sessionSource,
        contains('private func raycastFromReticle() -> ARRaycastResult?'),
        reason:
            'Trả `simd_float4x4?` là vứt mất `target` và `anchor` của kết quả '
            'ngay tại chỗ sinh ra chúng — tức là mất đúng hai trường phân biệt '
            '"mặt phẳng ARKit đã xác nhận" với "mặt phẳng nó đoán ra". Không '
            'lỗi nào nổ: chẩn đoán vẫn in, chỉ thiếu đúng hai ô.',
      );
    });

    test('tầng trúng đọc THẲNG từ kết quả, không suy từ vòng lặp', () {
      expect(
        _swiftMethodBody(sessionSource, 'private func makeDiagnostics('),
        contains('hit.target'),
        reason:
            'Suy từ thứ tự vòng lặp trong `raycastFromReticle` là chép lại một '
            'sự thật mà ARKit đã nói ra sẵn — và bản chép rời khỏi bản gốc ngay '
            'lượt đầu tiên ai đó đổi danh sách tầng mục tiêu.',
      );
    });

    test('chẩn đoán khoá theo identifier của anchor, không theo chỉ số', () {
      expect(
        _swiftMethodBody(
          sessionSource,
          'func placePoint() -> ArMeasurePlaceResult',
        ),
        contains('pointDiagnostics[anchor.identifier]'),
        reason:
            'Khoá theo chỉ số mảng thì `adoptUpdatedAnchors` (thay ĐỐI TƯỢNG '
            'anchor mỗi lượt ARKit chỉnh hệ toạ độ) và `didRemove` làm lệch '
            'ánh xạ, và chẩn đoán của điểm 1 gắn sang điểm 2 — im lặng.',
      );
    });

    test('thứ tự trong mẫu lấy từ anchors, KHÔNG lấy từ values của map', () {
      final body = _swiftMethodBody(
        sessionSource,
        'private func publish(force: Bool = false)',
      );

      expect(
        body,
        isNot(contains('pointDiagnostics.values')),
        reason:
            '`Dictionary.values` KHÔNG có thứ tự. Đọc từ đó thì hai điểm đổi '
            'chỗ cho nhau ngẫu nhiên giữa các lượt bắn, và dải chẩn đoán gán '
            'điều kiện của điểm này cho điểm kia — không lỗi nào nổ, và người '
            'đọc ảnh chụp màn hình không có cách nào biết.',
      );
      expect(
        body,
        contains('anchors.map'),
        reason:
            '`anchors` là danh sách theo ĐÚNG thứ tự chấm — nguồn thứ tự duy '
            'nhất trong cả lớp.',
      );
    });

    test('chẩn đoán bắn ra kể cả khi mới có MỘT điểm', () {
      final body = _swiftMethodBody(
        sessionSource,
        'private func publish(force: Bool = false)',
      );
      final iDiag = body.indexOf('sample["diagnostics"]');
      final iMm = body.indexOf('if let mm {');

      expect(iDiag, greaterThanOrEqualTo(0));
      expect(iMm, greaterThanOrEqualTo(0));
      expect(
        iDiag,
        lessThan(iMm),
        reason:
            'Nhét chẩn đoán vào trong `if let mm` là chỉ gửi khi đã đủ hai '
            'điểm — mà điểm ĐẦU mới là chỗ giả thuyết "chấm sai điểm đầu" phải '
            'kiểm. Mẫu vẫn hợp lệ, dải vẫn hiện lúc đo xong, và cái thiếu chỉ '
            'lộ ra ở đúng lượt cần nhìn.',
      );
    });

    test('tuổi phiên neo vào lời gọi run(), không neo vào lúc dựng lớp', () {
      expect(
        _swiftMethodBody(
          sessionSource,
          'private func runSession(options: ARSession.RunOptions)',
        ),
        contains('sessionStartedAt'),
        reason:
            'Đặt mốc ở `init` thì sau một lượt `reset()` (hay một lượt bỏ cuộc '
            'nối lại vị trí) tuổi phiên vẫn đếm từ lúc mở màn — và biến duy '
            'nhất dùng để bác hay giữ giả thuyết "máy chưa ấm" thành vô nghĩa, '
            'trong khi vẫn in ra một con số giây trông bình thường.',
      );
    });

    test('góc tia đo so với MẶT PHẲNG, không so với pháp tuyến', () {
      expect(
        _swiftMethodBody(sessionSource, 'private func makeDiagnostics('),
        contains('asin('),
        reason:
            'Pháp tuyến vuông góc với mặt, nên nhầm `acos` thành `asin` cho ra '
            'góc BÙ: 63° in thành 27°. Cả hai đều là một góc hợp lệ, cả hai đều '
            'nằm trong 0–90, và không có gì trên màn nói ra là mình đang đọc '
            'nhầm cái nào.',
      );
    });

    test('snappedToEdge vẫn là false CỨNG, và chú thích nói rõ chưa tính', () {
      expect(
        sessionSource,
        contains('sample["snappedToEdge"] = false'),
        reason:
            'Hít cạnh là một vé khác. Lượt này không đụng tới thuật toán đo.',
      );
      expect(
        sessionSource,
        contains('CHƯA ĐƯỢC TÍNH'),
        reason:
            'Một hằng số `false` không kèm lời cảnh báo đọc y hệt một phép đo '
            'trả về false. Ngay bên cạnh nó bây giờ là cả một tầng chẩn đoán '
            'toàn dữ liệu THẬT, nên nguy cơ đọc nhầm nó thành dữ liệu vừa tăng '
            'lên chứ không giảm.',
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
