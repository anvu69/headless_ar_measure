import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';

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
  final pluginSource = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/HeadlessArMeasurePlugin.swift',
  ).readAsStringSync();
  final overshootSource = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/PlaneOvershoot.swift',
  ).readAsStringSync();
  final dartSource = File('lib/headless_ar_measure.dart').readAsStringSync();

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
      // Lượt dò đã dời từ `refreshAimTarget` sang `probeReticle` khi đoạn thẳng
      // sống vào: nay có HAI thứ đọc cùng một lượt dò — một tầng và một vị trí
      // — nên lượt raycast phải nằm ở một chỗ cả hai cùng gọi. Luật thì không
      // đổi một chữ, chỉ đổi chỗ canh.
      expect(
        _swiftMethodBody(sessionSource, 'private func probeReticle('),
        contains('raycastFromReticle()'),
        reason:
            'Cờ ngắm là một lời hứa về cú bấm SẮP TỚI. Dò bằng một tia khác — '
            'khác tầng mục tiêu, khác alignment, khác điểm bắn — là hứa một '
            'đằng làm một nẻo: tâm ngắm khoá lại, người dùng bấm, và không có '
            'gì xảy ra. Đúng cái hỏng máy thật báo về.',
      );
    });

    // Cùng lời hứa, một bậc mạnh hơn: đoạn thẳng sống và cờ ngắm phải đọc CHUNG
    // một lượt dò. Hai lượt raycast riêng trong cùng một khung hình không chỉ
    // tốn gấp đôi — chúng bắn ở hai khoảnh khắc khác nhau, nên có những khung mà
    // tâm ngắm nói "chưa bám" trong khi đoạn thẳng đang nối tới một điểm.
    test('cờ ngắm và đoạn sống đọc CHUNG một lượt dò mỗi khung hình', () {
      final body = _swiftMethodBody(
        sessionSource,
        'func session(_ session: ARSession, didUpdate frame: ARFrame)',
      );

      expect(body, contains('let probe = probeReticle(now: now)'));
      // `frame:` vào từ 0.5.0: lượt lấy mẫu ngắm nay đọc thêm đám mây điểm thô
      // của ĐÚNG khung hình đã sinh ra lượt dò này. Xem nhóm "đếm điểm đặc
      // trưng quanh tia".
      expect(
        body,
        contains('refreshAimTarget(now: now, frame: frame, probe: probe)'),
      );
      expect(
        'raycastFromReticle()'.allMatches(body).length,
        0,
        reason:
            'Khung hình không được tự bắn thêm một tia nào ngoài lượt dò chung.',
      );
    });

    test('khung hình chạy lượt dò TRƯỚC lối rẽ hai điểm', () {
      final body = _swiftMethodBody(
        sessionSource,
        'func session(_ session: ARSession, didUpdate frame: ARFrame)',
      );

      expect(
        body,
        contains('refreshAimTarget('),
        reason:
            'Đây là nguồn khung hình duy nhất của lớp. Bản trước chặn sớm bằng '
            '`guard anchors.count == 2` — tức là ở đúng quãng người dùng còn '
            'đang ngắm điểm ĐẦU TIÊN thì không có lượt dò nào chạy, và tâm '
            'ngắm không bao giờ nói được gì.',
      );
      expect(
        body.indexOf('refreshAimTarget('),
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
        // Cố ý KHÔNG ghim dấu `{` đóng điều kiện: ca này canh chuyện `aimTarget`
        // CÓ MẶT trong điều kiện gộp, không canh rằng nó là khoá cuối cùng.
        // Ghim cả dấu đóng thì mỗi khoá thêm vào sau đều làm ca này đỏ vì một
        // lý do chẳng liên quan gì tới thứ nó bảo vệ. Hình dạng ĐẦY ĐỦ của
        // điều kiện có ca riêng ở nhóm "đếm điểm đặc trưng quanh tia".
        contains(
          'if !force, status == lastStatus, '
          'limitedReason == lastLimitedReason, aimTarget == lastAimTarget',
        ),
        reason:
            'Bộ giãn nhịp neo vào "số đo đổi quá 0,5 mm". Tầng ngắm đổi KHÔNG '
            'đổi số đo nào — phần lớn thời gian chưa có điểm nào để đo — nên '
            'nếu nó không nằm trong điều kiện gộp này thì lượt bắt được bề mặt '
            'đầu tiên bị nuốt trọn, và tâm ngắm câm đúng lúc nó cần nói nhất. '
            'So theo `aimTarget` chứ không theo `aimLocked`: cờ suy ra từ tầng, '
            'nên đổi từ `estimatedPlane` sang `existingPlaneGeometry` không đổi '
            'cờ một chút nào — mà đó là đúng lượt tâm ngắm phải đổi hình.',
      );
    });

    /// Việc A: quãng ân hạn của cờ ngắm đã BỎ HẲN.
    ///
    /// Bản trước giữ cờ "đã khoá" thêm 0,3 s sau lượt dò trượt đầu tiên, và
    /// mỗi lượt TRÚNG lại nạp lại quãng ấy từ đầu. Hệ quả đo được trên máy
    /// thật (iPhone 16 Plus, mép bàn, tấm lót chuột đen): một bề mặt chỉ trúng
    /// một lần trong mỗi 0,3 s vẫn giữ tâm ngắm ở hình "đã khoá" LIÊN TỤC,
    /// trong khi bốn trên năm cú bấm trượt. Người dùng thấy dấu khoá nên bấm,
    /// bấm thì trượt, rồi lặp lại — 130 giây cho điểm thứ nhất.
    test('cờ ngắm KHÔNG có quãng ân hạn nào', () {
      expect(
        sessionSource,
        isNot(contains('aimUnlockGraceSeconds')),
        reason:
            'Một quãng ân hạn NẠP LẠI ở mỗi lượt trúng không phải một bộ lọc '
            'chống nhấp nháy — nó là một phép HOẶC trên cả cửa sổ: một lượt '
            'trúng lẻ trong cửa sổ đủ để tâm ngắm nói "khoá" suốt cửa sổ ấy. '
            'Đó là lời hứa hão mà chính chú thích của hằng số này tự phá.',
      );
      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func refreshAimTarget('),
        ),
        isNot(contains('lastAimHitAt')),
        reason:
            'Mốc "lần dò gần nhất TRÚNG" chỉ có một công dụng: kéo dài một lời '
            'hứa đã hết hạn. Còn nó là còn đường quay lại quãng ân hạn.',
      );
    });

    test('cờ ngắm lấy mẫu theo LƯỚI nhịp dò, không theo 60 Hz của đoạn sống', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func refreshAimTarget('),
      );

      expect(
        body,
        contains('aimProbeIntervalSeconds'),
        reason:
            'Đang có đoạn thẳng sống thì [probeReticle] dò MỖI khung hình — 60 '
            'lượt/giây. Cho cờ đi thẳng theo đó là một tâm ngắm nhấp nháy 60 '
            'lần/giây, thứ mắt không đọc ra được trạng thái nào cả. Cửa sổ duy '
            'nhất còn lại là nhịp dò 10 Hz, và nó KHÔNG nạp lại theo lượt '
            'trúng: cờ luôn bằng kết quả của một lượt raycast thật, cũ nhiều '
            'nhất một nhịp.',
      );
      expect(
        body,
        contains('lastAimSampleAt'),
        reason:
            'Lưới lấy mẫu phải có mốc RIÊNG. Mượn `lastAimProbeAt` thì ở nhánh '
            'đoạn sống (dò mỗi khung) mốc ấy nhích theo từng khung hình và cửa '
            'sổ không bao giờ đóng — tức là quay về đúng 60 Hz.',
      );
    });

    /// Việc B: tầng của tia HIỆN TẠI, không phải tầng của một điểm đã chấm.
    test('tầng tia đọc từ MỘT chỗ, dùng chung cho chẩn đoán và tâm ngắm', () {
      expect(
        sessionSource,
        contains(
          'private static func raycastTarget(of hit: ARRaycastResult) -> ArRaycastTarget?',
        ),
        reason:
            'Hai chỗ cần đúng một phép dịch `ARRaycastResult.target` sang '
            '`ArRaycastTarget`: chẩn đoán của một điểm ĐÃ chấm, và tầng của tia '
            'ĐANG ngắm. Chép nó ra chỗ thứ hai là mở đường cho dải chẩn đoán và '
            'tâm ngắm nói hai chuyện khác nhau về cùng một lượt raycast.',
      );
      for (final signature in [
        'private func makeDiagnostics(',
        'private func probeReticle(',
      ]) {
        expect(
          _withoutComments(_swiftMethodBody(sessionSource, signature)),
          contains('Self.raycastTarget(of:'),
          reason: '`$signature` phải đi qua bản dịch dùng chung.',
        );
      }
    });

    test('tầng tia đang ngắm đi lên Dart, không chỉ có cờ trúng/trượt', () {
      expect(
        sessionSource,
        contains('sample["aimTarget"]'),
        reason:
            'Một cờ boolean gộp "trúng mặt phẳng đã xác nhận" với "trúng mặt '
            'phẳng ARKit đoán ra" thành cùng một hình tâm ngắm. Đó là hai mức '
            'tin cậy khác hẳn nhau, và người dùng cần thấy khác nhau TRƯỚC cú '
            'bấm chứ không phải sau nó.',
      );
      expect(
        dartSource,
        contains("raw['aimTarget']"),
        reason:
            'Cùng cái hỏng câm, ngược chiều: Swift vẫn gửi, và không ai nhận.',
      );
    });
  });

  /// Đoạn thẳng SỐNG và kênh lớp phủ.
  ///
  /// Cả nhóm này canh những chỗ mà hỏng thì lớp phủ **vẫn vẽ ra một hình** —
  /// chỉ là sai chỗ, sai đơn vị, hoặc sai thời điểm. Không cái nào ném, không
  /// cái nào lộ ra ở `flutter test` nếu không có ca ở đây, và mỗi cái đều đọc
  /// được như một giới hạn của ARKit chứ không như một lỗi của mình.
  group('đoạn thẳng sống và lớp phủ', () {
    test('sáu khoá của khung lớp phủ khớp từng chữ giữa Swift và Dart', () {
      for (final key in ['ax', 'ay', 'bx', 'by', 'bIsLive', 'distanceMm']) {
        expect(
          sessionSource,
          contains('frame["$key"]'),
          reason:
              'Khoá `$key` không còn được tầng Swift ghi vào khung lớp phủ. '
              'Dart đọc bằng chuỗi, nên lệch một chữ là trường ấy về `null` — '
              'nhãn mất số, hoặc đoạn thẳng mất một đầu, và không lỗi nào nổ.',
        );
        expect(
          dartSource,
          contains("raw['$key']"),
          reason:
              'Khoá `$key` không còn được Dart đọc. Cùng cái hỏng câm, ngược '
              'chiều: Swift vẫn gửi, và không ai nhận.',
        );
      }
    });

    test('lớp phủ đi kênh RIÊNG, và tên kênh khớp hai bên', () {
      expect(
        pluginSource,
        contains('"${ArMeasure.eventChannelName}"'),
        reason: 'Kênh trạng thái phải còn nguyên chỗ cũ.',
      );
      expect(
        pluginSource,
        contains('"${ArMeasure.overlayChannelName}"'),
        reason:
            'Tên kênh lớp phủ bên Swift và bên Dart đã lệch — `overlay` không '
            'nhận được khung nào, và một kênh im lặng trông y hệt một phiên '
            'chưa chấm điểm nào.',
      );
      expect(
        ArMeasure.overlayChannelName,
        isNot(ArMeasure.eventChannelName),
        reason:
            'Gộp hai kênh là bắt mọi người nghe TRẠNG THÁI lọc ba mươi khung '
            'mỗi giây để tìm một thay đổi mỗi vài giây.',
      );
    });

    // Hai ca dưới đây đọc thân hàm ĐÃ BÓC CHÚ THÍCH, và đó không phải chuyện
    // gọn gàng: cả hai chữ được canh — `contentScaleFactor` và `projected.z` —
    // đều xuất hiện trong chú thích giải thích chính chúng. Không bóc thì xoá
    // sạch phép chia mà ca kiểm vẫn xanh, vì lời giải thích còn nằm đó.
    test('phép chiếu đổi PIXEL sang POINT bằng contentScaleFactor', () {
      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func projectToScreen('),
        ),
        contains('/ scale'),
        reason:
            '`SCNSceneRenderer.projectPoint` trả toạ độ theo PIXEL của lớp vẽ, '
            'Flutter thì làm việc bằng point. Bỏ phép chia là trên máy @3x mọi '
            'toạ độ lớn gấp ba: nhãn bay ra ngoài màn trong khi đoạn thẳng '
            'SceneKit vẫn nằm đúng chỗ — hai thứ cùng một dữ liệu, lệch nhau '
            'đúng một hệ số nguyên, và không có gì nói ra vì sao.',
      );
    });

    test('phép chiếu kiểm z, không trả toạ độ của điểm sau lưng camera', () {
      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func projectToScreen('),
        ),
        contains('projected.z'),
        reason:
            'Điểm sau lưng camera vẫn chiếu ra một toạ độ x, y trông hoàn toàn '
            'hợp lệ — phép chiếu đi qua gốc, nên nó rơi xuống một chỗ đối xứng '
            'phía trước. Hai con số ấy không nói ra điều đó; chỉ z nói. Không '
            'kiểm z là vẽ một đoạn thẳng chạy tới một điểm ở phía sau gáy.',
      );
    });

    test('lớp phủ có trần nhịp RIÊNG 30 Hz, không mượn nhịp của samples', () {
      expect(
        sessionSource,
        contains('overlayMinIntervalSeconds = 1.0 / 30.0'),
        reason:
            'Bắn mỗi khung hình của ARKit là 60 Hz qua một kênh nền tảng cho '
            'một lớp vẽ mà mắt không đọc nổi quá 30 lần/giây.',
      );
      expect(
        sessionSource,
        contains('minIntervalSeconds = 1.0 / 15.0'),
        reason:
            'Nhịp của `samples` phải đứng nguyên 15 Hz. Kéo nó lên theo lớp '
            'phủ là đúng cái lý do kênh này được tách ra.',
      );
    });

    test('tia trượt thì XOÁ điểm sống, không giữ lại điểm của khung trước', () {
      final body = _swiftMethodBody(
        sessionSource,
        'private func probeReticle(',
      );
      // Cắt từ lượt raycast trở đi: `liveHitPoint = nil` cũng nằm ở nhánh
      // "trạng thái không cho chấm" phía trên, nên tìm trong cả thân hàm thì
      // xoá sạch nhánh TRƯỢT mà ca kiểm vẫn xanh.
      final afterRaycast = body.substring(body.indexOf('raycastFromReticle()'));

      expect(
        afterRaycast,
        contains('liveHitPoint = nil'),
        reason:
            'Giữ điểm cũ là để một đoạn thẳng ĐỨNG YÊN trên màn giữa lúc người '
            'dùng vẫn đang rê máy — và một đoạn đứng yên đọc ra "đã chấm xong". '
            'Ở đây khác tầng tâm ngắm: tầng lấy mẫu trên lưới 10 Hz để mắt đọc '
            'kịp, còn đoạn thẳng thì đi theo từng khung hình, vì nó nói ra một '
            'VỊ TRÍ chứ không phải một trạng thái.',
      );
    });

    test('đang có đoạn sống thì dò MỖI khung hình, không theo nhịp 10 Hz', () {
      final body = _swiftMethodBody(
        sessionSource,
        'private func probeReticle(',
      );

      expect(
        body,
        contains('anchors.count == 1'),
        reason:
            'Nhịp 10 Hz chọn cho một giá trị BOOLEAN. Đầu kia của đoạn thẳng '
            'sống là chính kết quả tia này, và ở 10 Hz nó giật sáu khung một '
            'bước — thấy rõ trên máy, không ca kiểm nào bắt được.',
      );
      expect(
        body.indexOf('anchors.count == 1'),
        lessThan(body.indexOf('aimProbeIntervalSeconds')),
        reason:
            'Lối rẽ "đang có đoạn sống" phải đứng TRƯỚC lượt giãn nhịp. Đặt sau '
            'thì nó nằm trong nhánh đã bị 10 Hz cắt, và không đổi được gì.',
      );
    });

    test('đoạn sống cũng vẽ ở SceneKit, không chỉ bắn lên Dart', () {
      expect(
        sessionSource,
        contains('func update(points: [ArMeasureMark], live: SIMD3<Float>?)'),
        reason:
            'Flutter chỉ vẽ NHÃN. Đoạn thẳng vẫn phải do SceneKit vẽ, vì chỉ nó '
            'chiếu được trong cùng lượt vẽ với nền camera — vẽ đoạn ở Flutter '
            'là để nó trôi lệch khỏi vật mỗi lần máy xoay.',
      );
    });

    test('lớp phủ và hình vẽ 3D dùng CHUNG một cổng tin cậy', () {
      final body = _swiftMethodBody(
        sessionSource,
        'private func refreshOverlay(',
      );

      expect(
        body,
        contains('coordinatesAreTrustworthy()'),
        reason:
            'Mất bám hay đang gián đoạn thì hai điểm vẫn còn đó, nhưng chúng '
            'chỉ vào sai vật. Đó là lý do hình 3D bị ẩn ở ba trạng thái ấy.',
      );
      expect(
        body,
        contains('measureNodes.update('),
        reason:
            'Hai cổng rời nhau là lúc hình 3D biến mất mà nhãn Flutter vẫn nằm '
            'lơ lửng giữa màn với một con số — hoặc ngược lại. Cùng một hàm thì '
            'không có chỗ cho hai cổng lệch nhau.',
      );
    });

    test('số đang chạy và số đã chốt dùng CHUNG một công thức', () {
      expect(
        _swiftMethodBody(
          sessionSource,
          'private func currentDistanceMm() -> Double?',
        ),
        contains('distanceMm(from:'),
        reason:
            'Chép công thức ra chỗ thứ hai là mở đường cho nhãn nổi và số đã '
            'chốt nói hai con số khác nhau về cùng một đoạn thẳng, trên cùng '
            'một màn.',
      );
      expect(
        _swiftMethodBody(sessionSource, 'private func refreshOverlay('),
        contains('distanceMm(from:'),
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
        contains('private func raycastFromReticle() -> ArSurfaceHit?'),
        reason:
            'Trả `simd_float4x4?` là vứt mất `target` và `anchor` của kết quả '
            'ngay tại chỗ sinh ra chúng — tức là mất đúng hai trường phân biệt '
            '"mặt phẳng ARKit đã xác nhận" với "mặt phẳng nó đoán ra". Không '
            'lỗi nào nổ: chẩn đoán vẫn in, chỉ thiếu đúng hai ô.',
      );
      expect(
        sessionSource,
        contains('struct ArSurfaceHit'),
        reason:
            'Từ 0.6.0 lượt trúng còn chở thêm quãng vượt biên, và nó phải đi '
            'CÙNG kết quả raycast: quãng ấy tính được đúng một lần, tại đúng '
            'lượt bắn đã sinh ra nó, từ mặt phẳng mà chính lượt ấy trúng. Trả '
            'riêng `ARRaycastResult` rồi đi tìm lại mặt phẳng sau là đi tìm một '
            'thứ có thể đã đổi.',
      );
    });

    test('tầng trúng đọc THẲNG từ kết quả, không suy từ vòng lặp', () {
      // Phép dịch đã dời sang [raycastTarget(of:)] khi tâm ngắm cần cùng một
      // tầng cho tia ĐANG ngắm. Luật không đổi một chữ, chỉ đổi chỗ canh.
      expect(
        _swiftMethodBody(
          sessionSource,
          'private static func raycastTarget(of hit: ARRaycastResult)',
        ),
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

    /// Việc C: chọn khuôn hình phân giải cao nhất máy hỗ trợ.
    ///
    /// PHÉP THỬ, chưa nghiệm thu trên máy. Giả thuyết: ảnh phân giải cao hơn
    /// cho ARKit nhiều điểm đặc trưng hơn, nên mặt phẳng mọc nhanh hơn trên bề
    /// mặt nghèo vân — đúng cảnh đã làm người dùng chờ 130 giây. Cái giá có thể
    /// là nhịp khung tụt (4K@30 thay cho 1440p@60), nên nhịp ấy phải in ra
    /// được ở dải chẩn đoán, và tụt thì bỏ.
    test('đặt videoFormat tường minh, không lấy mặc định', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func makeConfiguration('),
      );

      expect(
        body,
        contains('ARWorldTrackingConfiguration.supportedVideoFormats'),
        reason:
            'Không đặt gì là lấy khuôn mặc định của Apple, và mặc định ấy chọn '
            'theo cân bằng chung chứ không theo cái việc gói này làm — rút điểm '
            'đặc trưng từ một bề mặt nghèo vân ở cự ly 0,3–3 m.',
      );
      expect(
        body,
        contains('config.videoFormat ='),
        reason: 'Đọc danh sách mà không gán thì không có gì đổi.',
      );
      expect(
        body,
        contains('.max(by:'),
        reason:
            'Danh sách RỖNG là một khả năng thật (máy ảo, một bản iOS sau). '
            '`max(by:)` trả `nil` ở đó và `if let` bỏ qua — phòng hờ nằm ngay '
            'trong phép chọn, không phải một nhánh riêng ai đó quên.',
      );
    });

    test('khuôn hình đang dùng đi lên chẩn đoán, kèm nhịp khung', () {
      expect(
        _withoutComments(
          _swiftMethodBody(
            sessionSource,
            'private func runSession(options: ARSession.RunOptions)',
          ),
        ),
        contains('config.videoFormat'),
        reason:
            'Số phải đọc TỪ cấu hình sau khi đã gán, không phải từ khuôn mình '
            'vừa chọn: hai thứ ấy khác nhau đúng ở cái ca đáng quan tâm nhất — '
            'danh sách rỗng, phép gán không xảy ra, và máy đang chạy khuôn mặc '
            'định. Báo cáo khuôn mình MUỐN thay vì khuôn đang CHẠY là bịa ra '
            'bằng chứng cho chính phép thử này.',
      );
      for (final key in ['width', 'height', 'fps']) {
        expect(
          sessionSource,
          contains('"$key"'),
          reason:
              'Thiếu `$key` thì lượt thử máy thật không nói được nó có tác dụng '
              'gì — nhất là `fps`, con số quyết định giữ hay bỏ phép thử.',
        );
      }
      expect(
        dartSource,
        contains("raw['video']"),
        reason: 'Swift gửi mà Dart không đọc thì dải chẩn đoán vẫn trống.',
      );
    });

  });

  /// Tầng tia thứ BA — ngoại suy có nhãn. Vào từ 0.6.0.
  ///
  /// **Đây là lượt LẬT một quyết định mà chính tệp này từng ghim.** Bản trước
  /// có một ca tên *"hai tầng tia, đúng thứ tự, và KHÔNG có tầng mặt phẳng vô
  /// hạn"*, với lý do nguyên văn:
  ///
  /// > `.existingPlaneInfinite` sẽ "cứu" được cảnh trong ảnh máy thật — nó kéo
  /// > dài mặt bàn xuyên qua cái iPad và trả về một điểm. Nhưng điểm ấy nằm ở
  /// > CAO ĐỘ MẶT BÀN chứ không phải mặt iPad, và chĩa vào tường xa thì nó trả
  /// > một điểm đâu đó dọc mặt sàn kéo dài. Một con số trông bình thường mà sai
  /// > là dạng hỏng tệ nhất của gói này.
  ///
  /// **Lý lẽ ấy vẫn đúng, và nhóm này không bác một chữ nào của nó.** Thứ đổi
  /// là ba chữ *"trông bình thường"*: tầng ba nay không được phép đi một mình.
  /// Nó chỉ được nhận khi tính được quãng từ điểm chạm tới đa giác biên của
  /// chính mặt phẳng ấy, và quãng ấy đi lên Dart cùng tầng tia. Cảnh hỏng mà ca
  /// cũ mô tả — mặt bàn kéo dài xuyên qua cái iPad — nay tự lộ ra bằng một con
  /// số hàng trăm milimét thay vì im lặng.
  ///
  /// Bỏ cái van đi là quay lại đúng chỗ ca cũ đã bác, nên phần lớn nhóm này
  /// canh cái van chứ không canh tầng ba.
  ///
  /// Dữ kiện ép phải lật, đo trên máy thật: đám mây `rawFeaturePoints` của CẢ
  /// khung hình chỉ có 26 điểm, có lúc 2; quanh tia có 1, có lúc 0 (phép đo của
  /// 0.5.0, nhóm ngay trên). Không đủ nguyên liệu cho bất kỳ phép khớp mặt
  /// phẳng nào — nên lựa chọn thật không phải "ngoại suy hay đo đúng", mà là
  /// "ngoại suy có nhãn hay không đo được".
  group('ngoại suy có nhãn', () {
    test('ba tầng tia, đúng thứ tự, và ngoại suy đứng CUỐI', () {
      final literal = RegExp(
        r'let targets: \[ARRaycastQuery\.Target\] = \[([^\]]*)\]',
      ).firstMatch(sessionSource);
      expect(
        literal,
        isNotNull,
        reason: 'không tìm thấy danh sách tầng mục tiêu trong raycastFromReticle',
      );

      final tiers = RegExp(r'\.(\w+)')
          .allMatches(literal!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();

      expect(
        tiers,
        const [
          'existingPlaneGeometry',
          'estimatedPlane',
          'existingPlaneInfinite',
        ],
        reason:
            'Ngoại suy phải là tầng CUỐI CÙNG được thử, và ca này đỏ ở mọi lượt '
            'đảo thứ tự. Đưa nó lên trước là biến nó thành tầng MẶC ĐỊNH: một '
            'mặt phẳng đã dò kéo dài vô hạn thì trúng ở gần như mọi hướng, nên '
            'hai tầng đầu — hai tầng cho ra điểm QUAN SÁT được, và là hai tầng '
            'đang cho 4–8 mm trên sàn gạch — sẽ không bao giờ được thử tới nữa. '
            'Cả gói lặng lẽ chuyển sang đo bằng điểm suy ra, và mọi số đo vẫn '
            'hiện ra bình thường.',
      );
    });

    test('ngoại suy chỉ được NHẬN khi nó tự khai được quãng vượt biên', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func raycastFromReticle('),
      ).replaceAll(RegExp(r'\s+'), ' ');

      expect(
        body,
        contains('hit.anchor as? ARPlaneAnchor'),
        reason:
            'Không có `ARPlaneAnchor` thì không có biên nào để đo tới, tức là '
            'không có van. Lời chặn này CŨNG là chỗ luật "không ngoại suy khi '
            'chưa dò được mặt phẳng nào" được thi hành: không mặt phẳng thì '
            'không anchor, không anchor thì không nhận — không cần một lời '
            'chặn thứ hai đi đếm mặt phẳng của phiên.',
      );
      expect(
        body,
        contains('PlaneOvershoot.millimetres('),
        reason: 'Van phải tính NGAY tại lượt trúng, không hoãn lại sau.',
      );
      expect(
        body,
        contains('else { return nil }'),
        reason:
            'Tính không ra van thì lượt trúng ấy phải bị BỎ — trả về như một '
            'lượt trượt. Nhận nó với `overshootMm` bằng `nil` là dựng lại đúng '
            'cảnh mà bản trước cấm: một điểm suy ra, không nhãn, không ai biết '
            'nó suy ra xa tới đâu.',
      );
    });

    test('phép tính van nằm ở MỘT chỗ, và chỗ ấy chạy được không cần ARKit', () {
      for (final khung in ['ARKit', 'UIKit', 'SceneKit', 'AVFoundation']) {
        expect(
          overshootSource,
          isNot(contains('import $khung')),
          reason:
              'PlaneOvershoot.swift nhập `$khung` thì nó chỉ dịch được cho iOS, '
              'và `test/plane_overshoot_test.dart` — ca kiểm SỐ duy nhất của cả '
              'gói — không chạy nổi nữa. Mất nó là mất thứ duy nhất phân biệt '
              '"đo tới đoạn biên" với "đo tới đỉnh": hai cách đều để lại một '
              'tệp trông hợp lý và một con số milimét trông hợp lý.',
        );
      }

      expect(
        '.geometry.boundaryVertices'
            .allMatches(_withoutComments(sessionSource))
            .length,
        1,
        reason:
            '`ArMeasureSession` được ĐỌC đa giác biên đúng MỘT lần: lượt trao '
            'nó cho `PlaneOvershoot`. Lần thứ hai nghĩa là có một bản tính quãng '
            'thứ hai nằm trong tệp mà không ca kiểm SỐ nào chạm tới — và hai '
            'bản lệch nhau thì chúng vẫn cho ra hai con số milimét hợp lý.',
      );
    });

    test('hai đường van đi lên Dart, và Dart đọc cả hai', () {
      expect(
        sessionSource,
        contains('sample["aimOvershootMm"]'),
        reason: 'van của tia ĐANG ngắm — thứ tâm ngắm đọc trước cú bấm',
      );
      expect(
        dartSource,
        contains("raw['aimOvershootMm']"),
        reason: 'Swift vẫn gửi, và không ai nhận.',
      );
      expect(
        sessionSource,
        contains('map["overshootMm"]'),
        reason:
            'van của một điểm ĐÃ chấm. Thiếu nó thì một số đo lưu lại rồi đọc '
            'sau một tuần trông y hệt một số đo trên mặt phẳng đã xác nhận — '
            'đúng lỗi này, chỉ chậm hơn một tuần.',
      );
      expect(dartSource, contains("raw['overshootMm']"));
    });

    test('van của tia đang ngắm KHÔNG bị bộ giãn nhịp nuốt', () {
      expect(
        sessionSource.replaceAll(RegExp(r'\s+'), ' '),
        contains('aimOvershootMm == lastAimOvershootMm'),
        reason:
            'Tầng đứng im ở `existingPlaneInfinite` trong khi người dùng rê máy '
            'ra xa mép bàn: `status`, `limitedReason` và `aimTarget` đều không '
            'đổi một chút nào, và `mm` là `nil` khi chưa chấm điểm nào. Không '
            'đưa van vào điều kiện gộp thì con số đóng băng ở giá trị của lượt '
            'đầu — 30 mm — trong khi tia đã trôi ra hai mét. Đó là cái van báo '
            'AN TOÀN đúng lúc nó phải kêu, và nó tệ hơn hẳn không có van nào.',
      );
    });

    test('đầu mút ngoại suy vẽ KHÁC, và khác bằng HÌNH chứ không bằng màu', () {
      expect(
        sessionSource,
        contains('SCNTorus('),
        reason:
            'Đầu mút ngoại suy vẽ bằng một vòng RỖNG, đầu mút quan sát được vẽ '
            'bằng một chấm ĐẶC. Không có hình thứ hai thì hai mức tin cậy khác '
            'hẳn nhau hiện ra y hệt nhau trên màn.',
      );
      expect(
        sessionSource,
        contains('SCNBillboardConstraint()'),
        reason:
            'Vòng của `SCNTorus` nằm trong một mặt phẳng, nên nhìn nghiêng nó '
            'mỏng như sợi chỉ và nhìn dọc trục nó BIẾN MẤT. Không quay nó về '
            'phía camera thì cái nhãn hình học này im lặng vắng mặt ở đúng '
            'những góc ngắm mà người ta hay đứng.',
      );
      expect(
        'diffuse.contents'.allMatches(_withoutComments(sessionSource)).length,
        1,
        reason:
            'MỘT màu mực cho cả hai hình, và đó là một lựa chọn có lý do. Đổi '
            'màu là cách rẻ hơn, nhưng: cảnh không có đèn nào nên một màu thứ '
            'hai phải tự phát sáng và đọc ra như một BÁO LỖI chứ không như một '
            'mức tin cậy; màu là thứ đầu tiên mất đi với người mù màu và trong '
            'một tấm ảnh in đen trắng; và hai chấm đặc khác màu thì phải nhìn '
            'thấy CẢ HAI cạnh nhau mới so được, còn rỗng-hay-đặc thì đọc được '
            'trên từng đầu một.',
      );
      expect(
        sessionSource,
        contains('func update(points: [ArMeasureMark], live: SIMD3<Float>?)'),
        reason:
            'Vị trí và lai lịch đi CHUNG một giá trị, không phải hai mảng song '
            'song. Hai mảng lệch nhau một ô thì đầu tin được vẽ thành đầu suy '
            'ra và ngược lại — im lặng, và đúng chiều nguy hiểm.',
      );
    });

    test('lai lịch đầu mút đọc từ CHÍNH khối chẩn đoán đã ghi lúc bấm', () {
      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func currentMarks('),
        ),
        contains('pointDiagnostics['),
        reason:
            'Tầng của một điểm chỉ tồn tại trong `ARRaycastResult` của đúng cú '
            'bấm đã sinh ra nó, và nó đã được ghi lại ở đó. Dò lại tầng ấy bằng '
            'một tia mới lúc vẽ là hỏi một câu KHÁC — "chỗ này bây giờ là tầng '
            'gì" — rồi trả lời nó như thể đó là lai lịch của cú bấm cũ.',
      );
    });
  });

  /// PHÉP ĐO của 0.5.0, phục vụ một quyết định đang treo: có nên tự khớp mặt
  /// phẳng bằng RANSAC trên `rawFeaturePoints` thay cho raycast của ARKit hay
  /// không.
  ///
  /// Cả nhóm này canh một dạng hỏng câm rất riêng: phép đo VẪN chạy, hai con
  /// số VẪN hiện lên dải chẩn đoán, và chúng trả lời một câu hỏi KHÁC câu hỏi
  /// người đọc tưởng — rồi một quyết định kiến trúc được đóng dựa trên chúng.
  group('đếm điểm đặc trưng quanh tia', () {
    test('đếm trên đám mây THÔ, không đếm lại kết quả của ARKit', () {
      expect(
        sessionSource,
        contains('rawFeaturePoints'),
        reason:
            'Câu hỏi cần trả lời là "có NGUYÊN LIỆU không", và nguyên liệu ấy '
            'là đám mây điểm thô. Đếm bất cứ thứ gì ARKit đã lọc — mặt phẳng '
            'đã dò, kết quả raycast — là hỏi lại đúng cái câu mà `.estimatedPlane` '
            'đã trả lời rỗng, rồi ghi câu trả lời ấy ra hai lần.',
      );
    });

    test('một lượt LẤY MẪU nuôi cả tầng tia lẫn phép đếm', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func refreshAimTarget('),
      );

      expect(
        body,
        contains('makeFeatureCensus('),
        reason:
            'Hai con số này chỉ có nghĩa khi chúng nói về CÙNG một khung hình '
            'với `aimTarget`: cả phép đo là để đọc câu "tia trượt, mà quanh nó '
            'có 40 điểm". Lấy mẫu ở hai mốc riêng — kể cả cùng nhịp 10 Hz — là '
            'hai lưới lệch pha, và dải chẩn đoán ghép một lượt trượt của khung '
            'này với một phép đếm của khung khác. Không lỗi nào nổ, và con số '
            'đọc ra vẫn hợp lý.',
      );
      expect(
        body,
        contains('aimProbeIntervalSeconds'),
        reason:
            'Đếm cả đám mây là O(n) với n tới hàng nghìn. Nó phải đi trên lưới '
            'nhịp ĐÃ CÓ, không phải mỗi khung hình.',
      );
    });

    test('phép đếm KHÔNG tự bắn một tia nào', () {
      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func makeFeatureCensus('),
        ),
        isNot(contains('raycast')),
        reason:
            'Phép đếm là một lượt ĐỌC. Bắn thêm tia ở đây là đúng cái vòng lặp '
            'mà phép đo này sinh ra để phá.',
      );
    });

    test('hình nón có nửa góc và CỬA SỔ khoảng cách, không phải nón vô hạn', () {
      expect(
        sessionSource,
        contains('featureConeHalfAngleDegrees'),
        reason: 'Nửa góc phải là một hằng số đọc được, không phải một số trần.',
      );
      for (final name in [
        'featureRangeNearMeters',
        'featureRangeFarMeters',
      ]) {
        expect(
          sessionSource,
          contains(name),
          reason:
              'Nón dựng từ đỉnh camera là VÔ HẠN. Không cắt đầu xa thì "quanh '
              'tia" lặng lẽ thành "đâu đó theo hướng này", và trong một căn '
              'phòng thì bức tường phía sau chiếm trọn phép đếm — đúng con số '
              'nói "có nguyên liệu" trong khi nguyên liệu nằm cách mặt bàn ba '
              'mét.',
        );
      }
    });

    test('nón dựng quanh trục NHÌN của camera, không quanh một trục thế giới', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func makeFeatureCensus('),
      );

      expect(
        body,
        contains('columns.2'),
        reason:
            'Camera ARKit nhìn theo −Z của chính nó (cột 2 của transform, đảo '
            'dấu). Lấy nhầm cột là một cái nón chĩa sang ngang: nó vẫn đếm ra '
            'số, số ấy vẫn đổi khi rê máy, và không có gì trên màn nói rằng nó '
            'đang đếm ở một hướng khác hướng người dùng đang ngắm.',
      );
    });

    test('hai con số đi lên Dart trong khối chẩn đoán, và Dart đọc chúng', () {
      expect(sessionSource, contains('diagnostics["features"]'));
      for (final key in ['"total"', '"nearRay"']) {
        expect(
          sessionSource,
          contains(key),
          reason:
              'Thiếu $key thì phép đo mất đúng một nửa. Riêng một mình, "tổng '
              'khung" không phân biệt được "phòng trơn" với "chĩa nhầm chỗ".',
        );
      }
      expect(
        dartSource,
        contains("raw['features']"),
        reason: 'Swift gửi mà Dart không đọc thì dải chẩn đoán vẫn trống.',
      );
    });

    test('phép đếm đổi thì KHÔNG bị bộ giãn nhịp nuốt', () {
      expect(
        sessionSource.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'if !force, status == lastStatus, '
          'limitedReason == lastLimitedReason, aimTarget == lastAimTarget, '
          'featureCensus == lastFeatureCensus, '
          'aimOvershootMm == lastAimOvershootMm {',
        ),
        reason:
            'ĐÂY là ca quyết định của cả phép đo, và nó canh đúng cảnh hỏng '
            'đang điều tra: phòng trơn, tia trượt LIÊN TỤC. Ở đó `status` đứng '
            'im ở `ready`, `limitedReason` là `nil`, `aimTarget` là `nil` và '
            '`mm` là `nil` — nên nhánh nén ở dưới `return` thẳng, và `publish` '
            'KHÔNG BAO GIỜ chạy. Không đưa phép đếm vào điều kiện gộp này thì '
            'hai con số mới không bao giờ tới Dart ở đúng cái cảnh chúng sinh '
            'ra để đo, và dải chẩn đoán im lặng đọc y hệt "chưa dựng xong".',
      );
    });
  });

  group('chụp khung hình', () {
    // Cả năm ca dưới đây canh cùng một dạng hỏng: ảnh VẪN ra, tệp VẪN có, và
    // thứ sai chỉ lộ ra khi mở ảnh lên xem trên một máy khác.
    test('lệnh khớp từng chữ giữa Swift và Dart', () {
      expect(pluginSource, contains('case "captureFrame":'));
      expect(dartSource, contains("invokeMethod<String>('captureFrame'"));
    });

    test('đọc capturedImage, KHÔNG dùng snapshot() của SceneKit', () {
      final than = _swiftMethodBody(sessionSource, 'func captureFrame()');

      expect(
        _withoutComments(sessionSource),
        contains('CIImage(cvPixelBuffer: frame.capturedImage)'),
        reason:
            'khung phải THUẦN: hai chấm và đoạn thẳng là thứ SceneKit vẽ, và '
            'ảnh cuối dựng lại lớp phủ ấy ở Dart. Lấy cả hai là vẽ đè hai lần.',
      );
      expect(
        _withoutComments(than),
        isNot(contains('snapshot()')),
        reason:
            '`ARSCNView.snapshot()` trả về đúng thứ đang hiện — kể cả hình đo '
            'của SceneKit lẫn hướng dẫn quét bề mặt của Apple.',
      );
    });

    test('ghi ĐÚNG CHIỀU bằng displayTransform, không dựa cờ EXIF', () {
      final sach = _withoutComments(sessionSource);

      expect(
        sach,
        contains('displayTransform(for:'),
        reason:
            '`capturedImage` luôn nằm ngang theo cảm biến, bất kể máy đang cầm '
            'thế nào. Không nướng phép xoay vào điểm ảnh thì ảnh chỉ đúng chiều '
            'ở những trình xem chịu đọc cờ EXIF.',
      );
      expect(
        sach,
        isNot(contains('kCGImagePropertyOrientation')),
        reason:
            'ghi cờ hướng là nói "ảnh nằm nghiêng, người xem tự xoay hộ" — '
            'đúng thứ mà spec §5.1 cấm dựa vào.',
      );
    });

    test('ảnh nằm ở thư mục TẠM, không nằm trong Documents', () {
      final than = _swiftMethodBody(sessionSource, 'func captureFrame()');

      expect(
        _withoutComments(than),
        contains('temporaryDirectory'),
        reason:
            'gói không biết app muốn cất ảnh ở đâu. Nó trả một tệp tạm; chỗ '
            'lưu thật (và cái tên mang mốc thời gian) là việc của app.',
      );
      expect(
        _withoutComments(sessionSource),
        isNot(contains('.documentDirectory')),
      );
    });

    // §5.3 của spec app: một tấm ảnh xuất ra có GPS mâu thuẫn trực tiếp với
    // câu đã đăng trên trang riêng tư. Chặn từ gói là chặn ở chỗ RẺ nhất —
    // gói không hề nhập CoreLocation, nên không có gì để gắn vào.
    test('không có đường nào gắn vị trí vào ảnh', () {
      for (final src in [sessionSource, pluginSource, viewSource]) {
        expect(src, isNot(contains('CLLocation')));
        expect(src, isNot(contains('import CoreLocation')));
      }
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

/// Bỏ mọi chú thích `//` khỏi một đoạn mã Swift.
///
/// Cần thiết ở đúng những chỗ mà chữ được canh cũng là chữ dùng để GIẢI THÍCH
/// nó — `contentScaleFactor`, `projected.z`. Không bóc thì một ca kiểm có thể
/// xanh nhờ chính lời chú thích nói vì sao dòng mã ấy phải có mặt, sau khi dòng
/// mã ấy đã bị xoá.
String _withoutComments(String swift) {
  return swift.replaceAll(RegExp(r'//.*'), '');
}
