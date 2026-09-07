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
      // Lượt dò đã dời từ `refreshAimLock` sang `probeReticle` khi đoạn thẳng
      // sống vào: nay có HAI thứ đọc cùng một lượt dò — một cờ và một vị trí —
      // nên lượt raycast phải nằm ở một chỗ cả hai cùng gọi. Luật thì không đổi
      // một chữ, chỉ đổi chỗ canh.
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
      expect(body, contains('refreshAimLock(now: now, probe: probe)'));
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
            'Ở đây khác cờ tâm ngắm: cờ có quãng ân hạn 0,3 s để khỏi nhấp nháy, '
            'còn đoạn thẳng thì không, vì nó nói ra một VỊ TRÍ chứ không phải '
            'một trạng thái.',
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
        contains('func update(points: [SIMD3<Float>], live: SIMD3<Float>?)'),
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

/// Bỏ mọi chú thích `//` khỏi một đoạn mã Swift.
///
/// Cần thiết ở đúng những chỗ mà chữ được canh cũng là chữ dùng để GIẢI THÍCH
/// nó — `contentScaleFactor`, `projected.z`. Không bóc thì một ca kiểm có thể
/// xanh nhờ chính lời chú thích nói vì sao dòng mã ấy phải có mặt, sau khi dòng
/// mã ấy đã bị xoá.
String _withoutComments(String swift) {
  return swift.replaceAll(RegExp(r'//.*'), '');
}
