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
  final labelSource = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/LabelPlacement.swift',
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

    // Ca này ghi lại một lượt ĐIỀU TRA, không phải một lượt sửa: đi tìm nguyên
    // nhân nhấp nháy ở đầu mút (0.9.1), giả thuyết đầu tiên là đường vẽ dựng
    // lại node ở mỗi khung — gỡ rồi thêm, hoặc dựng lại `SCNGeometry`. Giả
    // thuyết ấy SAI: [ArMeasureNodes] dựng đủ năm node một lần ở `init` rồi chỉ
    // dời chỗ và ẩn/hiện, và [ArMeasureNodeSuppressor] trả `nil` cho mọi anchor
    // nên ARKit cũng không dựng node nào. Nguyên nhân thật nằm ở NGUỒN của toạ
    // độ, không ở chỗ vẽ — xem nhóm 'đoạn thẳng sống và lớp phủ'.
    //
    // Ghim lại vì hỏng theo hướng ấy thì CÂM: một node dựng lại mỗi khung vẫn
    // vẽ ra đúng hình ấy trên ảnh tĩnh, và thứ duy nhất nói ra là một cái nháy
    // mà chỉ máy thật thấy được.
    test('lượt cập nhật hình KHÔNG dựng lại node hay hình học nào', () {
      final body = _withoutComments(
        _swiftMethodBody(
          sessionSource,
          'func update(points: [ArMeasureMark], live: SIMD3<Float>?)',
        ),
      );
      for (final cam in [
        'SCNNode(',
        'SCNSphere(',
        'SCNTorus(',
        'SCNCylinder(',
        'addChildNode(',
        'removeFromParentNode(',
      ]) {
        expect(
          body,
          isNot(contains(cam)),
          reason:
              '`$cam` trong lượt cập nhật là một lượt cấp phát trên luồng vẽ, '
              'ở đúng nhịp đoạn thẳng đang trôi. Node phải dựng một lần ở '
              '`init` rồi chỉ đổi `simdPosition`/`isHidden`.',
        );
      }
    });
  });

  group('tấm ảnh dán trên đoạn', () {
    /// **Đây là ca canh chính của cả lượt 0.12.0.**
    ///
    /// Luật một câu: *tấm ảnh số đo phải được làm ra y như đường kẻ và hai chấm
    /// đầu mút được làm ra* — một node trong cảnh, đặt lại trong CÙNG lượt gọi
    /// mỗi khung hình. Tách nó ra một đường riêng (một hẹn giờ, một
    /// `SCNTransformConstraint`, hay tệ nhất là để app vẽ đè ở tầng Flutter) là
    /// dựng lại đúng cái lỗi kiến trúc mà lượt này đi bỏ: hai nhịp khác nhau,
    /// và con số GIẬT so với chính đoạn thẳng nó nằm trên.
    ///
    /// Ca này đọc thân `refreshOverlay` — cùng hàm đã đặt hai chấm và đoạn
    /// thẳng — và đòi lượt đặt nhãn nằm trong đó.
    test('nhãn đặt lại trong CÙNG lượt với đoạn thẳng, không đi nhịp riêng', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func refreshOverlay('),
      );
      expect(
        than,
        contains('measureNodes.update('),
        reason: 'hình đo phải còn cập nhật ở đây',
      );
      expect(
        than,
        contains('refreshLabel('),
        reason:
            'Nhãn phải đặt lại trong CÙNG lượt gọi với đoạn thẳng. Một đường '
            'riêng ở nhịp khác là đúng cái lỗi kiến trúc mà 0.12.0 đi bỏ — và '
            'triệu chứng của nó (nhãn giật so với đoạn) chỉ thấy được trên máy '
            'thật đang rê camera.',
      );
    });

    test('phép đặt nhãn nằm ở tệp KHÔNG nhập ARKit/SceneKit/UIKit', () {
      for (final khung in [
        'import ARKit',
        'import SceneKit',
        'import UIKit',
        'import Flutter',
      ]) {
        expect(
          labelSource,
          isNot(contains(khung)),
          reason:
              'LabelPlacement.swift phải dịch và chạy được bằng `swiftc` trên '
              'macOS — đó là điều kiện để ba luật số của nó (trễ của phép lật, '
              'luật cỡ, hệ trục) có ca kiểm. Nhập `$khung` là bỏ hết chúng.',
        );
      }
      expect(labelSource, contains('import Foundation'));
      expect(labelSource, contains('import simd'));
    });

    /// "Vẽ sau" một mình không đủ ở 3D — và hai vế của luật phải đi cùng nhau.
    test('nhãn tắt bộ đệm sâu VÀ đặt thứ tự vẽ tường minh', () {
      final than = _withoutComments(
        _swiftMethodBody(
          sessionSource,
          'private static func makeLabelMaterial(',
        ),
      );
      expect(than, contains('readsFromDepthBuffer = false'));
      expect(than, contains('writesToDepthBuffer = false'));
      expect(
        _withoutComments(sessionSource),
        contains('renderingOrder = labelRenderingOrder'),
        reason:
            'Tắt bộ đệm sâu thì thứ tự trên màn do `renderingOrder` quyết, nên '
            'nó phải đặt TƯỜNG MINH. Trông vào mặc định là đúng cho tới cái '
            'ngày nó không, và lúc ấy đường kẻ chạy xuyên qua con số.',
      );
    });

    /// Luật trễ phụ thuộc LỊCH SỬ, nên phải có đúng một chỗ nhớ.
    test('trạng thái lật nhớ ở phiên, hàm tính thì THUẦN', () {
      expect(
        labelSource,
        contains('wasFlipped: Bool'),
        reason:
            'Trạng thái lật phải đi vào rồi đi ra bằng THAM SỐ. Chôn một biến '
            'nhớ trong LabelPlacement là biến một hàm kiểm được bằng swiftc '
            'thành một hàm không kiểm được.',
      );
      expect(
        labelSource,
        isNot(RegExp(r'\bstatic var\b')),
        reason: 'không biến nhớ tĩnh nào trong tệp thuần',
      );
      expect(
        _withoutComments(sessionSource),
        contains('private var labelFlipped = false'),
        reason: 'chỗ nhớ DUY NHẤT của luật trễ nằm ở phiên',
      );
    });

    /// Gói không được chôn một cỡ chữ: cỡ đọc TỪ tấm ảnh app gửi xuống.
    test('cỡ danh định đọc từ tấm ảnh, không phải một hằng của gói', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func refreshLabel('),
      );
      expect(
        than,
        contains('measureNodes.labelPointSize.height'),
        reason:
            'Cỡ danh định của nhãn là cỡ POINT của chính tấm ảnh app gửi '
            'xuống. Một hằng trong gói là gói đang quyết cỡ chữ của app — và '
            'nó quyết sai ở mọi máy có tỉ lệ điểm ảnh khác.',
      );
    });

    /// Không có đoạn thì không có gì để chú thích.
    test('hết đoạn thẳng thì nhãn ẩn theo, cùng một lối ra', () {
      final than = _withoutComments(
        _swiftMethodBody(
          sessionSource,
          'func update(points: [ArMeasureMark], live: SIMD3<Float>?)',
        ),
      );
      expect(
        than,
        contains('hideLabel()'),
        reason:
            'Lối ra "không có cặp đầu mút nào" là chỗ DUY NHẤT mà "vừa còn '
            'đoạn, nay hết" đi qua. Không ẩn nhãn ở đó thì con số nằm lại giữa '
            'không trung sau một lượt Hoàn tác.',
      );
    });

    test('bốn khoá của chỗ đứng nhãn khớp từng chữ giữa Swift và Dart', () {
      for (final key in ['lx', 'ly', 'lrot', 'lscale']) {
        expect(
          sessionSource,
          contains('"$key":'),
          reason:
              'Khoá `$key` không còn được tầng Swift ghi vào khung lớp phủ. '
              'Ảnh chụp đọc bốn khoá này để dựng lại con số; thiếu một khoá là '
              'cả khối về `null` và tấm ảnh mất con số — trong khi trên màn nó '
              'vẫn nằm đó.',
        );
        expect(
          dartSource,
          contains("raw['$key']"),
          reason: 'Khoá `$key` không còn được Dart đọc.',
        );
      }
    });

    test('lệnh dán ảnh có mặt ở kênh, và KHÔNG bắt buộc phải có ảnh', () {
      expect(pluginSource, contains('case "setLabel":'));
      expect(
        pluginSource,
        contains('FlutterStandardTypedData'),
        reason:
            'Byte của tấm ảnh đi qua kênh chuẩn dưới dạng `FlutterStandardTypedData`; '
            'ép sang `Data` thẳng thì `png` luôn `nil` và nhãn không bao giờ hiện.',
      );
      expect(
        dartSource,
        contains("invokeMethod<String>('setLabel'"),
        reason: 'tên lệnh lệch một chữ là mọi lượt dán rơi vào hư không',
      );
    });

    /// Gói không biết trên ảnh viết gì — ranh giới của kho này.
    test('gói không dựng chữ, không biết trên ảnh viết gì', () {
      for (final src in [sessionSource, labelSource, pluginSource]) {
        expect(src, isNot(contains('SCNText')));
        expect(src, isNot(contains('NSAttributedString')));
        expect(src, isNot(contains('UIFont')));
      }
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

      // `frame:` vào từ 0.7.0: lượt dò nay còn đo GÓC của tia, và góc ấy đo so
      // với tư thế camera của ĐÚNG khung hình đã sinh ra lượt bắn. Đọc
      // `session.currentFrame` bên trong là dựa vào một giả định đúng nhưng
      // không ai canh — rằng ARKit đã đặt xong khung mới trước khi gọi vào đây.
      expect(
        body,
        contains('let probe = probeReticle(now: now, frame: frame)'),
      );
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

    // Ba ca dưới đây đọc thân hàm ĐÃ BÓC CHÚ THÍCH, và đó không phải chuyện
    // gọn gàng: cả hai chữ được canh — `contentScaleFactor` và `projected.z` —
    // đều xuất hiện trong chú thích giải thích chính chúng. Không bóc thì ca
    // kiểm xanh nhờ lời chú thích, kể cả sau khi dòng mã đã bị xoá — và, từ
    // 0.9.1, kể cả sau khi nó đã QUAY LẠI.
    //
    // **Ca đầu đã ĐỔI CHIỀU ở 0.9.1.** Chiều cũ ghi lại đây để không ai đi lại
    // vòng ấy: từ 0.2.0 tới 0.9.0 ca này canh chuỗi `/ scale`, với lý lẽ
    // "`projectPoint` trả PIXEL của lớp vẽ". Người viết lượt ấy tự khai là
    // KHÔNG chắc, và ghi sẵn triệu chứng nếu sai: *"nhãn lệch khỏi đoạn đúng
    // một hệ số nguyên (2 hoặc 3)"*. Triệu chứng ấy đã tới, trên hai máy, với
    // đúng hai hệ số ấy:
    //
    // * **iPhone 16 Plus (@3x)**, đo trên ảnh chụp màn hình: đường kẻ ở
    //   `y ≈ 480 pt`, hộp số ở `y ≈ 175 pt`. `480 / 3 ≈ 160`, cộng quãng nhãn
    //   đặt phía trên đường kẻ (~15 pt), ra đúng 175.
    // * **iPad Air M3 (@2x)**: nhãn nằm góc trên bên trái trong khi trung điểm
    //   đoạn ở giữa màn — chia đôi toạ độ giữa màn ra đúng góc phần tư ấy.
    //
    // Hai máy, hai hệ số, một công thức: `SCNSceneRenderer.projectPoint` trả
    // toạ độ theo hệ của **VIEW** (point), không phải điểm ảnh. `bounds` dùng
    // để bắn tia cũng là point, và [captureFrame] thì NHÂN hệ số ấy lên để ra
    // ảnh — nên sau lượt bỏ này cả ba chỗ cùng một hệ.
    test('phép chiếu KHÔNG đổi đơn vị — projectPoint đã trả point', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func projectToScreen('),
      );
      expect(
        body,
        isNot(contains('contentScaleFactor')),
        reason:
            'Phép chia này đã ship từ 0.2.0 và đã sai trên hai máy thật: nhãn '
            'Flutter rơi vào ô trên-trái của màn trong khi đoạn thẳng SceneKit '
            'nằm đúng chỗ — lệch đúng hệ số điểm ảnh của máy (3 trên iPhone 16 '
            'Plus, 2 trên iPad Air M3). `projectPoint` trả toạ độ theo hệ của '
            'view, và hệ ấy ĐÃ là point.',
      );
      expect(
        body,
        isNot(contains('/ scale')),
        reason:
            'Cùng một lỗi, viết bằng một cái tên biến khác. Chia cho bất cứ hệ '
            'số điểm ảnh nào ở đây là dựng lại đúng cảnh 0.2.0 đã ship.',
      );
      expect(
        body,
        contains('CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))'),
        reason:
            'Toạ độ phải đi thẳng ra, không nhân và không chia. Ca trên chỉ '
            'chặn phép CHIA; không có ca này thì một phép NHÂN — cùng hệ số, '
            'lệch ngược chiều — vẫn qua được cả hai.',
      );
    });

    // Ảnh xuất ra đo bằng ĐIỂM ẢNH, khung lớp phủ đo bằng POINT, và tỉ lệ giữa
    // hai hệ ấy là hệ số điểm ảnh của view. Từ 0.13.0 không còn phép nhân tay
    // nào — `snapshot()` dựng sẵn ở `contentScaleFactor` của view — nên thứ
    // phải canh đổi thành: ĐỪNG dựng lại cỡ ảnh ở bất cứ đâu.
    test('ảnh chụp KHÔNG tự đặt lại cỡ — snapshot() đã ở đúng hệ', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func captureSceneOnMain()'),
      );

      expect(
        than,
        isNot(contains('contentScaleFactor')),
        reason:
            'Nhân thêm một lượt nữa lên một tấm ảnh ĐÃ ở hệ điểm ảnh là ra ảnh '
            'to gấp hai hay gấp ba khung ngắm — và app quy toạ độ dải đáy sang '
            'toạ độ ảnh bằng đúng tỉ lệ ấy, nên dải đáy trượt khỏi mép.',
      );
      expect(
        than,
        isNot(contains('CGAffineTransform')),
        reason:
            'Cùng một lỗi viết bằng một phép biến đổi. Ảnh ra khỏi `snapshot()` '
            'đã đúng cỡ và đúng chiều; mọi phép biến đổi ở đây là một lượt '
            'thứ hai.',
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

    /// Ca này đã ĐỔI CHIỀU ở 0.9.1. Chiều cũ giữ lại đây vì lý lẽ của nó vẫn
    /// đúng ở chỗ nó nhắm tới, và người sau phải đọc được cả hai:
    ///
    /// * **Tới 0.9.0** ca canh `liveHitPoint = nil` ở nhánh trượt — "giữ điểm
    ///   cũ là để một đoạn thẳng ĐỨNG YÊN trên màn giữa lúc người dùng vẫn đang
    ///   rê máy, và một đoạn đứng yên đọc ra *đã chấm xong*".
    /// * **Từ 0.9.1** nhánh ấy đi qua quãng ôm 100 ms của [LivePointFilter].
    ///   Lý lẽ cũ nói về một quãng DÀI; một KHUNG không phải một quãng dài, và
    ///   cái giá của lời xoá-ngay ấy đã được người dùng gọi tên trên máy thật:
    ///   ở 60 khung/s, chuỗi trúng-trượt xen kẽ đọc ra một cái nháy liên tục ở
    ///   đầu mút.
    ///
    /// Nên ca này nay canh CẢ HAI phía: có ôm, và ôm CÓ HẠN.
    test('tia trượt thì ôm CÓ HẠN, không xoá ngay và không giữ mãi', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func probeReticle('),
      );
      // Cắt từ lượt raycast trở đi: nhánh "trạng thái không cho chấm" phía trên
      // cũng buông điểm sống, nên tìm trong cả thân hàm thì xoá sạch nhánh
      // TRƯỢT mà ca kiểm vẫn xanh.
      final afterRaycast = body.substring(body.indexOf('raycastFromReticle()'));

      expect(
        afterRaycast,
        contains('livePoint.miss('),
        reason:
            'Nhánh trượt phải BÁO cho bộ lọc. Bỏ qua nó là ôm vô thời hạn — '
            'đoạn thẳng đứng yên trên màn giữa lúc người dùng vẫn đang rê máy, '
            'và một đoạn đứng yên đọc ra "đã chấm xong".',
      );
      expect(
        afterRaycast,
        isNot(contains('livePoint.clear()')),
        reason:
            'Buông CỨNG ở nhánh trượt là quay về đúng bản 0.9.0: đoạn thẳng tắt '
            'hẳn một khung rồi bật lại. Quãng ôm nằm trong bộ lọc, và `clear()` '
            'đi vòng qua nó.',
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

    /// Nguyên nhân THẬT của lượt nhấp nháy ở đầu mút (0.9.1).
    ///
    /// Đường vẽ đã đúng từ trước — xem ca 'lượt cập nhật hình KHÔNG dựng lại
    /// node hay hình học nào'. Thứ nháy là NGUỒN của toạ độ: `probeReticle`
    /// bắn một tia mới mỗi khung hình khi đang có đoạn sống, và
    ///
    /// * một khung TRƯỢT xoá thẳng đầu sống → cả đoạn thẳng ẩn đi đúng một
    ///   khung rồi hiện lại. Ở 60 khung/s, một chuỗi trúng-trượt xen kẽ đọc ra
    ///   một cái nháy liên tục, đúng ở đầu mút;
    /// * ba tầng tia được thử theo thứ tự, nên hai khung liên tiếp có thể trả
    ///   về hai BỀ MẶT khác nhau — điểm nhảy hàng centimét mà vẫn "trúng".
    ///
    /// Cả hai đều là nhiễu THỜI GIAN, nên lời chữa cũng nằm ở trục thời gian:
    /// [LivePointFilter]. Ghim ở đây là ghim chỗ NỐI — phép lọc có ca kiểm số
    /// riêng (`test/live_point_test.dart`), còn ca này canh chuyện nó thật sự
    /// được gọi.
    test('đầu sống đi qua bộ lọc thời gian, không phải tia thô mỗi khung', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func probeReticle('),
      );
      expect(
        body,
        contains('livePoint.miss('),
        reason:
            'Một khung trượt phải đi qua quãng ôm của bộ lọc. Gán thẳng `nil` '
            'là đúng cái đã ship: đoạn thẳng tắt hẳn một khung rồi bật lại, và '
            'ở 60 khung/s mắt đọc ra một cái nháy chứ không đọc ra "tia trượt".',
      );
      expect(
        body,
        contains('livePoint.hit('),
        reason:
            'Lượt trúng cũng phải đi qua bộ lọc, không ghi thẳng vào chỗ vẽ. '
            'Chỉ lọc nhánh trượt là chữa cái nháy mà để nguyên cái giật.',
      );
      expect(
        body,
        isNot(contains('liveHitPoint = nil')),
        reason:
            'Lối cũ. Còn một dòng ấy là còn một đường vòng qua bộ lọc, và '
            'đường vòng ấy nháy y như trước.',
      );

      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func refreshOverlay('),
        ),
        contains('livePoint.point'),
        reason:
            'Chỗ vẽ phải đọc giá trị ĐÃ LỌC. Đọc một biến thô nào khác là dựng '
            'hai nguồn sự thật cho cùng một đầu mút.',
      );
    });

    test('bỏ hết điểm thì XOÁ CỨNG đầu sống, không ôm', () {
      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func clearAnchors()'),
        ),
        contains('livePoint.clear()'),
        reason:
            '`reset()` dựng lại cả hệ toạ độ, nên điểm của lượt dò trước nằm '
            'trong hệ CŨ. Ôm nó thêm 100 ms là vẽ một đoạn thẳng tới một toạ độ '
            'thuộc về một thế giới không còn nữa — và nó trông hoàn toàn bình '
            'thường.',
      );
    });

    test('quãng ôm ngắn hơn hẳn quãng đọc ra "đã chấm xong"', () {
      final filterSource = File(
        'ios/headless_ar_measure/Sources/headless_ar_measure/LivePoint.swift',
      ).readAsStringSync();
      expect(
        filterSource,
        contains('holdSeconds: TimeInterval = 0.10'),
        reason:
            'Quãng ôm là một lời đánh đổi có hai đầu, và cả hai đầu đều hỏng '
            'nhìn thấy được. Ngắn quá thì không nuốt nổi một khung trượt; dài '
            'quá thì đoạn thẳng ĐỨNG YÊN giữa lúc người dùng còn đang rê máy, '
            'và một đoạn đứng yên đọc ra "đã chấm xong". 100 ms nằm trên ngưỡng '
            'sáu khung ở 60 Hz và dưới ngưỡng mắt đọc ra một đoạn bị đóng băng.',
      );
      expect(
        filterSource,
        isNot(contains('import ARKit')),
        reason:
            'Nhập ARKit là mất cả ca kiểm số: `swiftc` trên macOS không dịch '
            'nổi tệp, và phép lọc quay về chỗ chỉ máy iOS thật kiểm được.',
      );
      expect(filterSource, isNot(contains('import UIKit')));
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

    // Phép tính đã dời khỏi `makeDiagnostics` ở 0.7.0: tia ĐANG ngắm cần đúng
    // con số ấy trước cú bấm, và hai bản chép của cùng một phép tính là đúng
    // lớp lỗi mà `raycastTarget(of:)` và `PlaneOvershoot` đã đóng. Luật thì
    // không đổi một chữ nào — xem nhóm "tiêu cự và góc tia sống".
    test('góc tia đo so với MẶT PHẲNG, không so với pháp tuyến', () {
      expect(
        _swiftMethodBody(sessionSource, 'private static func rayAngleDeg('),
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

    /// Việc C: chọn khuôn hình, theo **nhịp khung trước, điểm ảnh sau**.
    ///
    /// Tiêu chí đổi ở 0.9.0. Trước đó (0.4.0) nó xếp ngược lại — nhiều điểm ảnh
    /// nhất trước — và lượt đổi này **không phải** hoàn nguyên theo điều kiện
    /// mà 0.4.0 tự ghi trước ("nhịp tụt mà chờ không giảm thì bỏ"): quãng chờ
    /// ĐÃ co, từ 130 s xuống 7,8 s. Nó đổi vì một triệu chứng mới — đoạn thẳng
    /// giật khi rê máy, mà đoạn thẳng vẽ trong SceneKit nên nó chỉ mượt được
    /// bằng nhịp khung.
    ///
    /// Ca ở đây KHÔNG kiểm tiêu chí — `test/video_format_choice_test.dart` kiểm
    /// tiêu chí, bằng cách chạy phép chọn thật trên những danh sách khuôn giả.
    /// Ca này kiểm đúng một thứ mà ca kiểm số KHÔNG với tới được: rằng cấu hình
    /// đang chạy CÓ GỌI phép chọn ấy. Chép tiêu chí trở lại vào chỗ này để lại
    /// một ca kiểm số xanh canh một hàm không ai gọi, và một cái máy chạy tiêu
    /// chí khác — đúng lớp hỏng câm mà cả tệp này sinh ra để chặn.
    test('đặt videoFormat tường minh, và đi qua VideoFormatChoice', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func makeConfiguration('),
      );

      expect(
        body,
        contains('ARWorldTrackingConfiguration.supportedVideoFormats'),
        reason:
            'Không đặt gì là lấy khuôn mặc định của Apple, và mặc định ấy chọn '
            'theo cân bằng chung chứ không theo cái việc gói này làm — rút điểm '
            'đặc trưng từ một bề mặt nghèo vân ở cự ly 0,3–3 m, và vẽ một đoạn '
            'thẳng chạy theo tâm ngắm.',
      );
      expect(
        body,
        contains('config.videoFormat ='),
        reason: 'Đọc danh sách mà không gán thì không có gì đổi.',
      );
      expect(
        body,
        contains('VideoFormatChoice.indexOfBest('),
        reason:
            'Tiêu chí phải nằm ở `VideoFormatChoice` — tệp ấy không nhập ARKit '
            'nên nó CHẠY được trong ca kiểm. Một tiêu chí viết thẳng ở đây chỉ '
            'kiểm được bằng cách cầm đúng cái máy có đúng danh sách khuôn cần '
            'thử, tức là không kiểm được.',
      );
      expect(
        body,
        isNot(contains('framesPerSecond <')),
        reason:
            'So nhịp khung TẠI ĐÂY là chép tiêu chí ra chỗ thứ hai. Hai bản '
            'chép lệch nhau thì bản chạy trên máy là bản này, còn bản có ca '
            'kiểm là bản kia — và không có gì đỏ.',
      );
      expect(
        body,
        isNot(contains('imageResolution.width * ')),
        reason:
            'Cùng lẽ: nhân ra diện tích ở đây nghĩa là tiêu chí đã quay về nằm '
            'trong `makeConfiguration`.',
      );
    });

    test('VideoFormatChoice KHÔNG nhập ARKit', () {
      final choiceSource = File(
        'ios/headless_ar_measure/Sources/headless_ar_measure/VideoFormatChoice.swift',
      ).readAsStringSync();

      expect(
        choiceSource,
        isNot(contains('import ARKit')),
        reason:
            'Nhập ARKit là tệp này thôi dịch được trên macOS, và ca kiểm số của '
            'nó chết theo — im lặng chuyển thành "bỏ qua" nếu ai đó thêm một '
            'nhánh phòng hờ, hoặc đỏ với một lỗi trông như lỗi môi trường. Cả '
            'hai đều kết thúc bằng việc gỡ ca kiểm ra.',
      );
      expect(
        choiceSource,
        isNot(contains('import UIKit')),
        reason: 'Cùng lẽ với ARKit.',
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
        reason:
            'không tìm thấy danh sách tầng mục tiêu trong raycastFromReticle',
      );

      final tiers = RegExp(
        r'\.(\w+)',
      ).allMatches(literal!.group(1)!).map((m) => m.group(1)!).toList();

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
        'diffuse.contents = UIColor'
            .allMatches(_withoutComments(sessionSource))
            .length,
        1,
        reason:
            'MỘT màu mực cho cả hai hình, và đó là một lựa chọn có lý do. Đổi '
            'màu là cách rẻ hơn, nhưng: cảnh không có đèn nào nên một màu thứ '
            'hai phải tự phát sáng và đọc ra như một BÁO LỖI chứ không như một '
            'mức tin cậy; màu là thứ đầu tiên mất đi với người mù màu và trong '
            'một tấm ảnh in đen trắng; và hai chấm đặc khác màu thì phải nhìn '
            'thấy CẢ HAI cạnh nhau mới so được, còn rỗng-hay-đặc thì đọc được '
            'trên từng đầu một.\n\n'
            'Đếm theo `= UIColor` chứ không theo `diffuse.contents` trơn: từ '
            '0.12.0 tấm ảnh dán cũng ghi vào `diffuse.contents`, nhưng nó gán '
            'một TẤM ẢNH của app chứ không gán một màu mực — hai việc khác '
            'nhau, và luật "một màu mực" chỉ nói về vế sau.',
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

  /// Định danh mặt phẳng — vào từ 0.8.0.
  ///
  /// Nó tồn tại vì hai cảnh hỏng trên máy thật, và cả hai lọt qua SẠCH chín
  /// trường chẩn đoán đã có:
  ///
  /// 1. Điểm cuối lơ lửng trên tường nằm trên mặt phẳng MẶT BÀN kéo dài gần hai
  ///    mét (`overshootMm` +1946), nên `planeAlignment` của nó vẫn `horizontal`
  ///    y hệt điểm đầu.
  /// 2. Ba lần đầu điểm bị bắt xuống dưới chân bàn — tức mặt SÀN, vì lúc ấy mặt
  ///    bàn chưa được dò. Sàn và mặt bàn ĐỀU ngang.
  ///
  /// Mọi phép suy từ chín trường cũ trả lời "cùng mặt phẳng" ở đúng hai cảnh
  /// chúng cần phân biệt, nên phải có một định danh THẬT chứ không phải một
  /// phép suy. Bên Swift thứ cần đã nằm sẵn ngay chỗ tính van:
  /// `hit.anchor as? ARPlaneAnchor`.
  ///
  /// Cả nhóm canh dạng hỏng riêng của một trường ĐỊNH DANH: nó vẫn in ra một
  /// chuỗi trông hợp lệ trong khi hai mặt phẳng khác nhau đụng độ cùng một giá
  /// trị — và lúc ấy app kết luận "cùng mặt phẳng" ở đúng chỗ nó phải kêu.
  group('định danh mặt phẳng', () {
    test('định danh đọc từ MỘT chỗ, dùng chung cho tia ngắm và điểm đã chấm', () {
      expect(
        sessionSource,
        contains(
          'private static func planeId(of hit: ARRaycastResult) -> String?',
        ),
        reason:
            'Cùng một luật với `raycastTarget(of:)` và `rayAngleDeg(from:...)`: '
            'MỘT phép dịch dùng chung cho tia ĐANG ngắm và cho chẩn đoán của '
            'một điểm ĐÃ chấm. Hai bản chép lệch nhau thì tâm ngắm và dải chẩn '
            'đoán khai hai mặt phẳng khác nhau cho cùng một lượt raycast, và cả '
            'hai đều là một chuỗi trông hợp lệ.',
      );

      for (final noiGoi in [
        'private func makeDiagnostics(for hit: ArSurfaceHit)',
        'private func probeReticle(now: TimeInterval, frame: ARFrame)',
      ]) {
        expect(
          _withoutComments(_swiftMethodBody(sessionSource, noiGoi)),
          contains('Self.planeId('),
          reason:
              '`$noiGoi` tự cast `ARPlaneAnchor` lấy id thay vì gọi hàm chung '
              'là dựng bản chép thứ hai ngay tại chỗ luật này cấm.',
        );
      }
    });

    test('định danh là uuidString ĐẦY ĐỦ, không rút gọn và không băm', () {
      final body = _withoutComments(
        _swiftMethodBody(
          sessionSource,
          'private static func planeId(of hit: ARRaycastResult) -> String?',
        ),
      );

      expect(
        body,
        contains('.identifier.uuidString'),
        reason:
            '`UUID` là dữ liệu định danh, và `uuidString` là giá trị đầy đủ của '
            'nó. Gói bắn nguyên chuỗi ấy: nó chỉ để SO SÁNH BẰNG NHAU, nên thứ '
            'duy nhất mua được bằng cách rút gọn là vài chục byte mỗi mẫu — và '
            'cái giá là một xác suất đụng độ, tức là hai mặt phẳng khác nhau '
            'đọc ra "cùng một mặt phẳng", đúng kết luận sai mà trường này sinh '
            'ra để chặn.',
      );

      for (final catGon in [
        'prefix(',
        'suffix(',
        'dropLast(',
        'dropFirst(',
        'hashValue',
        'hash(',
      ]) {
        expect(
          body,
          isNot(contains(catGon)),
          reason:
              '`$catGon` trong hàm định danh là một phép rút gọn. Nó không bao '
              'giờ nổ, không bao giờ in ra gì lạ, và nó hỏng đúng một lần trong '
              'nhiều nghìn lượt — ở đúng cái lượt hai mặt phẳng đụng độ.',
        );
      }
    });

    test('hai đường định danh đi lên Dart, và Dart đọc cả hai', () {
      expect(
        sessionSource,
        contains('sample["aimPlaneId"]'),
        reason: 'định danh của tia ĐANG ngắm — thứ tâm ngắm đọc trước cú bấm',
      );
      expect(
        dartSource,
        contains("raw['aimPlaneId']"),
        reason: 'Swift vẫn gửi, và không ai nhận.',
      );
      expect(
        sessionSource,
        contains('map["planeId"]'),
        reason:
            'định danh của một điểm ĐÃ chấm. Thiếu nó thì câu hỏi "hai đầu mút '
            'có cùng mặt phẳng không" không trả lời được sau cú bấm thứ hai — '
            'mà đó đúng là lúc nó được hỏi.',
      );
      expect(dartSource, contains("raw['planeId']"));
    });

    test('định danh của tia ngắm KHÔNG bị bộ giãn nhịp nuốt', () {
      expect(
        sessionSource.replaceAll(RegExp(r'\s+'), ' '),
        contains('aimPlaneId == lastAimPlaneId'),
        reason:
            'Cảnh cụ thể, và nó chính là cảnh hỏng số 2: người dùng rê tia từ '
            'MẶT BÀN xuống SÀN. Cả hai đều `horizontal`, cả hai đều ở tầng '
            '`existingPlaneGeometry`, `status` đứng im, `limitedReason` là '
            '`nil`, van là `nil` ở cả hai, và cầm máy cùng một độ nghiêng thì '
            'góc tia cũng bằng nhau. Thứ DUY NHẤT đổi là định danh. Không đưa '
            'nó vào điều kiện gộp thì mẫu ấy không bao giờ được bắn, và app đọc '
            'mãi tên mặt phẳng cũ. `featureCensus` không đỡ được chuyện này: '
            'tài liệu của chính nó nói nó là một phép đo có hạn dùng và sẽ rời '
            'gói.',
      );
    });

    test('định danh chỉ ghi ở một lượt BẮN TIA — không đường nào viết lại', () {
      final khongChuThich = _withoutComments(sessionSource);

      // Đúng HAI đường ghi, và cả hai đứng sau một lượt raycast mới:
      // `placePoint` (chấm), và `replacePoint` — chỗ chốt điểm dùng chung cho
      // một nhát `movePoint` lẫn cú buông ở cuối một quãng kéo. Đường thứ ba ở
      // bất cứ đâu là một lượt viết lại định danh mà KHÔNG có tia nào đứng sau
      // — tức là một phép đoán, mà đó chính là quyết định gói đã bác: ARKit GỘP
      // mặt phẳng và không nói mặt phẳng bị nuốt đã nhập vào mặt phẳng NÀO, nên
      // một cú đoán sai in ra đúng chữ "cùng mặt phẳng".
      final luotGhi = RegExp(
        r'pointDiagnostics\[[^\]]+\]\s*=',
      ).allMatches(khongChuThich).length;
      expect(luotGhi, 2, reason: 'chỉ `placePoint` và `replacePoint` được ghi');

      for (final ten in ['func placePoint()', 'private func replacePoint(']) {
        expect(
          _withoutComments(_swiftMethodBody(sessionSource, ten)),
          contains('pointDiagnostics['),
          reason: '`$ten` phải ghi lai lịch của đúng lượt bắn đứng sau nó',
        );
      }

      expect(
        _withoutComments(
          _swiftMethodBody(
            sessionSource,
            'private func adoptUpdatedAnchors(_ updated: [ARAnchor])',
          ),
        ),
        isNot(contains('pointDiagnostics')),
        reason:
            '`adoptUpdatedAnchors` KHÔNG cùng một chuyện với lượt gộp, và chỗ '
            'khác nhau là toàn bộ lý do gói để nguyên định danh: nó thay ĐỐI '
            'TƯỢNG anchor cho CÙNG một `identifier` mà chính ARKit trao lại — '
            'không có phép đoán nào. Đuổi theo lượt gộp thì phải bịa ra một ánh '
            'xạ danh tính mà ARKit chưa bao giờ nói.',
      );

      expect(
        dartSource,
        contains('định danh **lúc chấm**'),
        reason:
            'Hành vi đã chọn phải nằm trong tài liệu của chính trường ấy. Hai '
            'cách xử lượt gộp cho hành vi KHÁC NHAU ở đúng cảnh mặt bàn vừa dò '
            'xong, nên người đọc phải biết mình đang cầm cách nào.',
      );
    });

    test('gói trả định danh, KHÔNG kết luận cùng hay khác', () {
      for (final ketLuan in [
        'samePlane',
        'isSamePlane',
        'sharesPlane',
        'planesMatch',
        'coplanar',
      ]) {
        expect(
          sessionSource + dartSource,
          isNot(contains(ketLuan)),
          reason:
              'Cùng một ranh giới với `overshootMm`: gói trả sự thật đo được, '
              'app quyết. "Cùng mặt phẳng hay không" phụ thuộc việc app đang đo '
              'cái gì — sau một lượt gộp, hai định danh khác nhau có thể vẫn là '
              'một mặt bàn — và gói không biết điều đó.',
        );
      }
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
      for (final name in ['featureRangeNearMeters', 'featureRangeFarMeters']) {
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
          'grabbedPointIndex == lastGrabbedPointIndex, '
          'aimOvershootMm == lastAimOvershootMm, '
          'aimRayAngleDeg == lastAimRayAngleDeg, '
          'aimPlaneId == lastAimPlaneId {',
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

  /// Hai con số của 0.7.0, và cả hai chỉ có một việc: nuôi số hạng dung sai mà
  /// app vừa dựng xong.
  ///
  ///     ε = d · Δu / (fx · sin θ)
  ///
  /// Sai số hướng ngắm chiếu lên mặt phẳng bị chia cho `sin θ`, với θ là góc
  /// giữa tia và MẶT phẳng. Ở 0,6 m với lệch 2 điểm ảnh: θ=90° cho 0,83 mm,
  /// θ=12° cho 4,00 mm, θ=5° cho 9,55 mm — và θ nhỏ là đúng tư thế người ta cầm
  /// máy khi đo mép bàn.
  ///
  /// **Gói KHÔNG tính `ε`, không đặt ngưỡng, không biết `Δu`.** Nó trả đúng hai
  /// sự thật đo được: tiêu cự bao nhiêu điểm ảnh, góc bao nhiêu độ. Ngưỡng nào
  /// là "quá sượt" phụ thuộc app đang đo cái gì — cùng một lẽ với `overshootMm`.
  group('tiêu cự và góc tia sống', () {
    test(
      'góc tia tính ở MỘT chỗ, dùng chung cho điểm đã chấm và tia đang ngắm',
      () {
        final noComments = _withoutComments(sessionSource);

        expect(
          noComments,
          contains('asin('),
          reason: 'không còn phép tính góc nào trong tệp',
        );
        expect(
          'asin('.allMatches(noComments).length,
          1,
          reason:
              'Hai bản chép của cùng một phép tính góc — một cho điểm ĐÃ chấm, '
              'một cho tia ĐANG ngắm — lệch nhau thì cảnh báo "ngắm quá sượt" '
              'hiện lên ở một góc, còn dải chẩn đoán của đúng cú bấm ấy ghi một '
              'góc khác. Cả hai đều là số độ hợp lệ, và không ai soi ra được. '
              'Cùng một luật với `raycastTarget(of:)` và với `PlaneOvershoot`.',
        );
      },
    );

    test('góc tia sống đi CÙNG lượt raycast với tầng tia và với van', () {
      final body = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func probeReticle('),
      );

      expect(
        body,
        contains('rayAngleDeg'),
        reason:
            'Góc phải đọc từ ĐÚNG lượt bắn đã sinh ra tầng tia và cái van — '
            'cùng khung hình, cùng mặt phẳng, cùng tia. Mở một lượt bắn thứ hai '
            'để đo góc là trả tiền hai lần cho cùng một việc, và hai lượt ấy '
            'trúng hai chỗ khác nhau ngay khi tay người dùng nhúc nhích.',
      );

      final refresh = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func refreshAimTarget('),
      );
      expect(
        refresh,
        contains('aimRayAngleDeg = '),
        reason:
            'Cùng chỗ, cùng lưới nhịp 10 Hz với `aimTarget` và `aimOvershootMm`. '
            'Một cái đồng hồ riêng cho góc là ba con số nói về ba khoảnh khắc '
            'khác nhau trong cùng một mẫu.',
      );
    });

    test('góc tia sống gác theo TRÚNG, không gác theo tầng ngoại suy', () {
      final publish = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func publish('),
      ).replaceAll(RegExp(r'\s+'), ' ');

      expect(
        publish,
        contains(
          'aimRayAngleDeg = aimTarget != nil ? self.aimRayAngleDeg : nil',
        ),
        reason:
            'Bất biến cũ giữ nguyên: `aimOvershootMm != nil` ⟺ `aimTarget == '
            '.existingPlaneInfinite`, vì nó nói về một cái biên bị vượt và hai '
            'tầng kia không vượt biên nào. Góc tia thì khác — một tia sượt 4° '
            'vào một mặt phẳng ARKit ĐÃ XÁC NHẬN vẫn là một tia sượt 4°. Gác nó '
            'theo tầng ngoại suy là tắt cảnh báo sượt ở đúng cái tầng người ta '
            'tin nhất.',
      );
      expect(
        publish,
        contains(
          'aimOvershootMm = aimTarget != nil ? self.aimOvershootMm : nil',
        ),
        reason: 'và bất biến của van không được đụng tới trong lượt này',
      );
    });

    test('góc tia sống đi lên Dart, và Dart đọc', () {
      expect(sessionSource, contains('sample["aimRayAngleDeg"]'));
      expect(
        dartSource,
        contains("raw['aimRayAngleDeg']"),
        reason:
            'Swift gửi mà Dart không đọc thì cảnh báo sượt không bao giờ có.',
      );
    });

    /// Ca này KHÔNG thừa dù `featureCensus` đang đổi gần như mỗi lượt lấy mẫu
    /// và vì thế đang kéo mọi thứ khác đi cùng.
    ///
    /// `ArFeatureCensus` là một PHÉP ĐO có hạn dùng — tài liệu của chính nó nói
    /// *"nó biến mất cùng lúc câu hỏi ấy được trả lời"*. Ngày nó ra khỏi gói,
    /// một góc tia không nằm trong điều kiện gộp sẽ đóng băng ở giá trị của
    /// lượt đầu trong khi người dùng vẫn đang nghiêng máy: đúng lỗi mà cái van
    /// đã trả giá một lần, chỉ khác con số.
    test('góc tia sống KHÔNG bị bộ giãn nhịp nuốt', () {
      expect(
        sessionSource.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'if !force, status == lastStatus, '
          'limitedReason == lastLimitedReason, aimTarget == lastAimTarget, '
          'featureCensus == lastFeatureCensus, '
          'grabbedPointIndex == lastGrabbedPointIndex, '
          'aimOvershootMm == lastAimOvershootMm, '
          'aimRayAngleDeg == lastAimRayAngleDeg, '
          'aimPlaneId == lastAimPlaneId {',
        ),
        reason:
            'Người dùng đứng yên một chỗ và chỉ NGHIÊNG máy: `status` đứng im, '
            '`limitedReason` là `nil`, `aimTarget` không đổi (vẫn cùng mặt '
            'phẳng), `mm` là `nil` khi chưa chấm điểm nào, và van cũng không '
            'đổi. Thứ duy nhất đổi là chính con số này — và nó là con số quyết '
            'định có cảnh báo hay không.',
      );
    });

    /// **`fx` KHÔNG được ghim cứng, và đây là ca canh chuyện đó.**
    ///
    /// Con số 1442 mà mọi bài viết dẫn ra là tiêu cự của khuôn 1920×1440. Gói
    /// chọn khuôn to nhất máy hỗ trợ (3840×2160 trên máy thật), và `fx` co giãn
    /// theo bề rộng khuôn — nên nó gần gấp đôi. Ghim cứng thì mọi con số dung
    /// sai lệch đúng một hệ số 2, và cả hai giá trị đều nằm gọn trong khoảng
    /// "trông hợp lý": vài milimét.
    ///
    /// Khuôn hình đổi không phải chuyện xa xôi: khối chọn khuôn là một PHÉP THỬ
    /// chưa nghiệm thu, và chú thích của chính nó nói **"nhịp khung tụt mà thời
    /// gian chờ không giảm thì bỏ hẳn đoạn này"**.
    test('fx đọc từ ARFrame.camera.intrinsics, không từ một hằng số', () {
      expect(
        sessionSource,
        contains('camera.intrinsics'),
        reason:
            'Đây là chỗ DUY NHẤT iOS nói ra tiêu cự thật của khuôn đang chạy. '
            'Mọi con số khác là một con số của máy khác, hoặc của khuôn khác.',
      );
      expect(
        sessionSource,
        contains('camera.intrinsics[0][0]'),
        reason:
            'Cột 0 hàng 0 của ma trận nội tại LÀ `fx`. `[0][1]` là hệ số xiên '
            '(gần như luôn bằng 0) và `[1][1]` là `fy` — trên máy iOS hai tiêu '
            'cự gần bằng nhau, nên nhầm cột cho ra một con số vẫn đúng cỡ.',
      );
      expect(
        _withoutComments(
          _swiftMethodBody(
            sessionSource,
            'private func runSession(options: ARSession.RunOptions)',
          ),
        ),
        isNot(contains('intrinsics')),
        reason:
            'Đọc `fx` một lần lúc `run` rồi để im là đúng cái lỗi ghim cứng, '
            'chỉ mặc áo khác: gói bật `isAutoFocusEnabled`, nên tiêu cự nhúc '
            'nhích theo cự ly lấy nét trong suốt phiên — và khuôn hình thì có '
            'thể đổi ở lượt `run` sau.',
      );
    });

    /// `fx` một mình là một con số không đọc được: 1442 và 2884 cùng là "đúng",
    /// và cái phân biệt chúng là bề rộng khuôn. Người đọc dải chẩn đoán phải
    /// thấy cả hai cạnh nhau thì mới hiểu con số, và app muốn quy về khuôn khác
    /// cũng cần đúng bề rộng ấy.
    ///
    /// Bề rộng ấy KHÔNG được mượn của [ArVideoFormat]: khối kia là ảnh chụp lúc
    /// `run` (khuôn được CẤU HÌNH), khối này là khung hình vừa tới (khuôn đang
    /// CHẠY). ARKit không hứa giao đúng khuôn đã xin, nên hai thứ lệch được
    /// thật — và một `fx` đọc trên bề rộng của khối kia là một phép chia sai mà
    /// kết quả vẫn là một số milimét bình thường.
    test('fx đi kèm khuôn hình của CHÍNH khung ấy, không mượn của cấu hình', () {
      expect(
        sessionSource,
        contains('camera.imageResolution'),
        reason:
            '`ARCamera.imageResolution` là hệ toạ độ điểm ảnh mà `intrinsics` '
            'được biểu diễn trên đó. `config.videoFormat.imageResolution` là '
            'khuôn đã XIN, và nó nằm ở khối `video` rồi.',
      );
      expect(sessionSource, contains('diagnostics["camera"]'));
      for (final key in ['"fx"']) {
        expect(sessionSource, contains(key));
      }
      expect(
        dartSource,
        contains("raw['camera']"),
        reason: 'Swift gửi mà Dart không đọc thì dải chẩn đoán vẫn trống.',
      );
      expect(
        dartSource,
        contains("raw['fx']"),
        reason: 'và không có `fx` thì app không tính nổi một milimét nào',
      );
    });

    /// `fx` KHÔNG nằm trong điều kiện gộp, và đó là một lựa chọn ngược với góc
    /// tia ngay bên trên — nên nó phải được ghi lại.
    ///
    /// Lấy nét tự động làm `fx` nhúc nhích gần như mỗi khung hình. Đưa nó vào
    /// điều kiện gộp là biến kênh trạng thái thành một cái vòi 60 Hz vì một con
    /// số mà **không ai nhìn theo thời gian thực** — app đọc nó một lần để đặt
    /// vào công thức. Nó đi nhờ mọi mẫu đã được bắn, y như khối `video`.
    test('fx KHÔNG nằm trong điều kiện gộp, và đi nhờ mọi mẫu đã bắn', () {
      expect(
        sessionSource.replaceAll(RegExp(r'\s+'), ' '),
        isNot(contains('cameraIntrinsics == lastCameraIntrinsics')),
        reason:
            'Lấy nét tự động làm `fx` đổi gần như mỗi khung hình. Đưa vào điều '
            'kiện gộp là bắn 60 mẫu mỗi giây vì một con số app đọc một lần.',
      );
      expect(
        _withoutComments(
          _swiftMethodBody(
            sessionSource,
            'func session(_ session: ARSession, didUpdate frame: ARFrame)',
          ),
        ),
        contains('frame.camera'),
        reason:
            'Chỗ đọc phải là đường khung hình — đó là nơi duy nhất có một '
            '`ARFrame` để đọc, và là nhịp mà con số này thật sự đổi.',
      );
    });
  });

  /// Dời một đầu mút đã chấm — vào từ 0.10.0.
  ///
  /// Vì sao nó tồn tại, nguyên văn lượt máy thật: *"khi chọn xong 2 đầu thì
  /// hiện ra nút cộng trừ, tuy nhiên nó gây confuse cho user khi thay đổi số mà
  /// điểm trên màn hình không đổi"*. Con số và HÌNH nói hai chuyện khác nhau
  /// trên cùng một màn. Đường ra không phải một cái nút chỉnh số khéo hơn: nó
  /// là cho người dùng dời chính cái điểm, để con số đổi VÌ hình đổi.
  ///
  /// Cả nhóm canh hai dạng hỏng câm rất riêng của một lệnh DỜI, và không dạng
  /// nào nổ:
  ///
  /// 1. **Dời hụt phá luôn điểm cũ.** Tia trượt, điểm biến mất, và người dùng
  ///    mất một đầu họ đã chấm đúng — để "sửa" một thứ họ chỉ định nhích đi vài
  ///    milimét.
  /// 2. **Điểm mới mang lai lịch CŨ.** Nó dời sang một mặt phẳng khác nhưng vẫn
  ///    khai định danh, tầng tia và van của cú bấm trước. Mọi tín hiệu trung
  ///    thực gói đã dựng — van vượt biên, định danh mặt phẳng, góc sượt — nói
  ///    dối về đúng cái điểm vừa đổi chỗ, và chúng nói dối một cách trông hoàn
  ///    toàn hợp lệ.
  group('dời một đầu mút', () {
    test('lệnh khớp từng chữ giữa Swift và Dart', () {
      expect(pluginSource, contains('case "movePoint":'));
      expect(dartSource, contains("invokeMethod<String>('movePoint'"));

      // Bốn giá trị trên dây, và chúng phải khớp từng chữ ở cả hai đầu — danh
      // sách hai bên do `status_contract_test.dart` canh. Ở đây canh nửa còn
      // lại: Dart phải DỊCH được cả bốn. Thiếu một nhánh thì nó rơi về `_ =>`
      // và trả `notReady` cho một lượt dời đã chạy xong, không lỗi nào nổ, và
      // câu nói với người dùng là "chưa dời được" trong khi điểm vừa đổi chỗ.
      for (final v in ['moved', 'missed', 'notReady', 'noSuchPoint']) {
        expect(
          dartSource,
          contains("'$v' => ArMeasureMoveResult."),
          reason: 'Dart không dịch nổi giá trị dây `$v`',
        );
      }
    });

    /// Ca số một của lượt này: **dời hụt thì điểm cũ còn nguyên**.
    ///
    /// Canh bằng THỨ TỰ trong thân hàm, vì đó là chỗ lỗi sống: một cách cài
    /// "gỡ điểm cũ ra rồi chấm lại" đọc rất tự nhiên, chạy đúng ở mọi lượt
    /// trúng, và chỉ hỏng ở lượt trượt — đúng lượt người dùng đang ngắm vào một
    /// bề mặt tệ, tức là đúng lượt họ cần lệnh này nhất.
    test('dời hụt thì điểm cũ còn nguyên', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'func movePoint(at index: Int)'),
      );

      final banTia = than.indexOf('raycastFromReticle()');
      expect(
        banTia,
        greaterThanOrEqualTo(0),
        reason:
            'Lệnh dời phải bắn CHÍNH tia mà `placePoint` bắn. Một tia gần giống '
            'là một lời hứa hão: tâm ngắm khoá, người dùng bấm, điểm không đi '
            'đâu cả.',
      );
      expect(
        than,
        contains('return .missed'),
        reason:
            'Tia trượt có một câu riêng — "rê máy quanh vật cho tới khi tâm '
            'ngắm khoá lại". Gộp nó vào `notReady` là mời người dùng chờ một '
            'phiên đang chạy hoàn toàn bình thường.',
      );

      // Mọi phép đột biến đi qua ĐÚNG một lời gọi, và lời gọi ấy phải đứng SAU
      // lời gác tia. Ba chữ dưới đây canh chiều ngược lại: không có phép đột
      // biến nào viết thẳng trong thân hàm, ở bất cứ đâu — kể cả sau lời gác.
      // Viết thẳng ở đó vẫn chạy đúng, nhưng nó dựng bản chép thứ hai của luật
      // chốt điểm, và bản chép ấy trôi ra khỏi `replacePoint` trong im lặng.
      for (final dotBien in [
        'anchors[',
        'session.remove(',
        'pointDiagnostics',
      ]) {
        expect(
          than,
          isNot(contains(dotBien)),
          reason:
              '`$dotBien` viết thẳng trong `movePoint`. Mọi phép đột biến phải '
              'đi qua `replacePoint(at:with:diagnostics:)`, chỗ duy nhất chốt '
              'một điểm — cùng chỗ mà cú buông ở cuối một quãng kéo dùng.',
        );
      }

      final chot = than.indexOf('replacePoint(');
      expect(
        chot,
        greaterThan(banTia),
        reason:
            'Lời chốt nằm TRƯỚC lời gác tia. Một lượt trượt ở đó đã kịp phá '
            'điểm cũ, và người dùng mất một đầu họ chấm đúng để đổi lấy một '
            'lượt dời không xảy ra. Dời hụt phải là một phép rỗng.',
      );
    });

    /// Ca số hai: **lai lịch của điểm sau khi dời là lai lịch MỚI**.
    ///
    /// Ca dời trong CÙNG một mặt phẳng không phân biệt được hai cách cài, nên
    /// thứ canh được ở tầng chữ là NGUỒN của khối chẩn đoán: nó phải dựng từ
    /// lượt trúng MỚI, cả khối một lần, không phải vá vài trường lên khối cũ.
    test('lai lịch của điểm sau khi dời là lai lịch MỚI', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'func movePoint(at index: Int)'),
      );

      expect(
        than,
        contains('makeDiagnostics(for: hit)'),
        reason:
            'Tầng tia, van vượt biên, định danh mặt phẳng, góc và cự ly chỉ tồn '
            'tại trong `ARRaycastResult` của đúng lượt bắn NÀY. Dựng lại khối '
            'chẩn đoán từ lượt bắn cũ là khai một mặt phẳng người dùng vừa rời '
            'khỏi.',
      );
      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func replacePoint('),
        ),
        contains('pointDiagnostics.removeValue(forKey:'),
        reason:
            'Khối chẩn đoán khoá theo `identifier` của anchor, và anchor cũ bị '
            'thay bằng một anchor MỚI (`ARAnchor.transform` là readonly). Không '
            'gỡ khoá cũ thì nó nằm lại trong map suốt phiên.',
      );

      // Không đường nào CHÉP một khối chẩn đoán sang khoá khác. Đây là cách
      // viết sai trông tự nhiên nhất — "giữ lại lai lịch cho khỏi mất" — và nó
      // dựng ra đúng cảnh hỏng: một điểm nằm trên tường, khai mình ở trên mặt
      // bàn.
      //
      // Hai vế được nhận, và chỉ hai: một phép đo mới tại chỗ
      // (`makeDiagnostics(for:)`, đường của `placePoint`), hoặc tham số
      // `diagnostics` của `replacePoint` — mà ca "buông chốt lai lịch của chỗ
      // CUỐI" đã truy tiếp tới nguồn của nó.
      for (final chep in RegExp(
        r'pointDiagnostics\[[^\]]+\]\s*=\s*([^\n]+)',
      ).allMatches(_withoutComments(sessionSource))) {
        expect(
          chep.group(1),
          anyOf(startsWith('makeDiagnostics(for:'), equals('diagnostics')),
          reason:
              'Mọi lượt ghi vào khối chẩn đoán phải là một PHÉP ĐO mới. Chép '
              'một khối cũ sang khoá mới là dựng lại lai lịch của một cú bấm '
              'chưa từng xảy ra ở chỗ ấy.',
        );
      }
    });

    /// Ca số ba: chỉ số ngoài khoảng, và lúc chưa đủ hai điểm.
    test('chỉ số phải NAME một điểm đang có, và luật ấy nằm ở MỘT chỗ', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'func movePoint(at index: Int)'),
      );

      expect(
        than,
        contains('anchors.indices.contains(index)'),
        reason:
            'Luật là "chỉ số phải trỏ vào một điểm ĐANG CÓ" — không phải "phải '
            'đủ hai điểm". Gói không biết app đang bày nút dời lúc nào, và một '
            'điểm đã chấm là một điểm đã chấm dù đầu kia còn đang chạy.',
      );
      expect(
        than,
        contains('return .noSuchPoint'),
        reason:
            'Chỉ số không trỏ vào đâu là một câu về DỮ LIỆU CỦA APP, không phải '
            'về ARKit. Đổ nó vào `notReady` là bảo app "chờ phiên bám lại" cho '
            'một điểm sẽ không bao giờ tồn tại.',
      );

      // Dart KHÔNG chép luật ấy. Hai bản chép lệch nhau thì Dart trả
      // `noSuchPoint` cho một chỉ số Swift chấp nhận, và lệnh không rời máy.
      final thanDart = dartSource.substring(
        dartSource.indexOf('Future<ArMeasureMoveResult> movePoint('),
      );
      expect(
        thanDart.substring(0, thanDart.indexOf('\n  }')),
        isNot(contains('noSuchPoint')),
        reason:
            'Chỉ tầng Swift biết đang có mấy điểm. Dart đoán thêm một lượt là '
            'dựng một nguồn sự thật thứ hai về số điểm — thứ mà chính luồng '
            '`samples` đã nói.',
      );
    });

    test('chỉ số kiểm TRƯỚC trạng thái', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'func movePoint(at index: Int)'),
      );

      // So với lời gác TRẠNG THÁI, không so với `.notReady` đầu tiên trong
      // thân: lời gác `isStopped` cũng trả `.notReady` và nó đứng trước mọi thứ
      // — đúng chỗ của nó, vì một phiên đã dừng thì không có mảng điểm nào để
      // tra chỉ số.
      expect(
        than.indexOf('.noSuchPoint'),
        lessThan(than.indexOf('reticleIsMeaningful(')),
        reason:
            'Cùng một luật thứ tự với `alreadyComplete` đi trước `notReady` ở '
            '`placePoint`: nửa giây rung tay không được biến "điểm ấy không tồn '
            'tại" thành "chờ phiên bám lại". Chờ bao lâu cũng không làm điểm số '
            '5 mọc ra.',
      );
    });

    /// Điểm ĐANG DỜI không đi qua `LivePointFilter`, và đó là một quyết định,
    /// không phải một chỗ sót.
    test('dời KHÔNG đi qua bộ lọc đầu mút sống', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'func movePoint(at index: Int)'),
      );

      expect(
        than,
        isNot(contains('livePoint')),
        reason:
            'Bộ lọc tồn tại cho một điểm được VẼ LẠI 60 lần mỗi giây; một điểm '
            'dời được đặt đúng một lần cho mỗi cú chạm, y như `placePoint`. Cái '
            'giá của bộ lọc là ĐỘ TRỄ (10,8 mm ở nhịp rê 0,48 m/s), nên cho '
            'điểm dời đi qua đó là chôn một sai số hệ thống vào một điểm ĐÃ '
            'CHỐT. Tệ hơn: quãng ôm 100 ms sẽ cho một lượt TRƯỢT trả về một '
            'toạ độ cũ, và lệnh báo `moved` cho một cú dời chưa xảy ra.',
      );
    });

    test('điểm mới là một ARAnchor MỚI, và anchor cũ được gỡ khỏi phiên', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func replacePoint('),
      );

      expect(
        than,
        contains('ARAnchor('),
        reason:
            '`ARAnchor.transform` là readonly — tài liệu của Apple bảo bỏ '
            'anchor cũ và thêm anchor mới. Không có đường nào "dời" một anchor '
            'tại chỗ.',
      );
      expect(
        than,
        contains('transform: hit.result.worldTransform'),
        reason:
            'Anchor mới dựng từ một lượt TRÚNG. Dựng từ bất cứ toạ độ nào khác '
            '— một điểm đã làm mượt, một transform cũ — là dời điểm tới một chỗ '
            'không phải chỗ người dùng đang chỉ. Ở cú buông thì lượt trúng ấy là '
            'lượt CUỐI của quãng kéo, không phải vệt đã làm mượt mà mắt vừa '
            'nhìn theo.',
      );
      expect(
        than,
        contains('sceneView.session.remove(anchor:'),
        reason:
            'Không gỡ là để lại một anchor mồ côi trong phiên ARKit cho mỗi lượt '
            'dời. Nó không vẽ gì (node bị chặn), nên nó tích lại im lặng.',
      );
      expect(than, contains('sceneView.session.add(anchor:'));

      final movePointBody = _withoutComments(
        _swiftMethodBody(sessionSource, 'func movePoint(at index: Int)'),
      );
      expect(
        movePointBody,
        contains('publish(force: true)'),
        reason:
            'Số đo phải đổi NGAY ở cú chạm, không đợi nhịp 15 Hz hay đợi số đo '
            'nhích quá 0,5 mm — đây là một lượt ĐỔI TRẠNG THÁI, cùng lối với '
            '`placePoint` và `undoPoint`.',
      );
    });

    /// Tâm ngắm phải còn nói được ở `measured`, nếu không thì cả lượt này ship
    /// ra một cái nút chết.
    test('tâm ngắm còn sống khi đã đủ hai điểm, và luật ấy ở MỘT chỗ', () {
      final sach = _withoutComments(sessionSource);
      final khaiBao = _withoutComments(
        _swiftMethodBody(
          sessionSource,
          'private static func reticleIsMeaningful(',
        ),
      );

      expect(
        khaiBao,
        contains('.measured'),
        reason:
            'Trước 0.10.0, hai điểm đã đủ thì tâm ngắm hết nghĩa — không còn gì '
            'để chấm. Lệnh dời phá đúng giả định ấy: ở `measured` vẫn có một cú '
            'bấm đặt được một điểm. Để tâm ngắm câm ở đó là bắt người dùng biết '
            'mình đang ngắm vào chỗ trống bằng cách BẤM — đúng cái nút chết mà '
            'cờ này sinh ra để chặn.',
      );
      expect(
        RegExp(r'reticleIsMeaningful\(').allMatches(sach).length,
        7,
        reason:
            'Một lần khai và SÁU chỗ gọi — lượt dò, hai lời gác cuối trong '
            '`publish` (tầng ngắm và phép đếm vân), `placePoint`, `movePoint`, '
            '`grabPoint`. Sáu bản chép lệch nhau thì tâm ngắm khoá trong khi '
            'lệnh dời trả `notReady`, hoặc ngược lại: lệnh chạy được trong khi '
            'tâm ngắm nói không có gì để bấm. Cả hai chiều đều là một cái nút '
            'nói dối, và không lỗi nào nổ.',
      );

      // Lời gác viết tay phải chỉ còn ĐÚNG một chỗ: trong chính hàm khai báo
      // luật. Một bản sót lại ở ngoài là một luật thứ hai về cùng một câu hỏi,
      // và nó đứng im khi luật chính đổi.
      expect(
        RegExp(
          r'status == \.ready \|\| status == \.firstPointPlaced',
        ).allMatches(sach.replaceFirst(khaiBao, '')),
        isEmpty,
        reason:
            'còn một lời gác trạng thái viết tay ngoài `reticleIsMeaningful`',
      );

      expect(
        dartSource,
        contains('ArMeasureStatus.measured'),
        reason:
            'Tài liệu của `aimLocked` từng nói thẳng rằng nó LUÔN `false` ở '
            '`measured`. Câu ấy nay sai, và một câu sai trong tài liệu của '
            'chính trường ấy là chỗ người đọc tin trước tiên.',
      );
    });
  });

  group('nắm và kéo một đầu mút', () {
    test('hai lệnh khớp từng chữ giữa Swift và Dart', () {
      expect(pluginSource, contains('case "grabPoint":'));
      expect(pluginSource, contains('case "releasePoint":'));
      expect(dartSource, contains("invokeMethod<String>('grabPoint'"));
      expect(dartSource, contains("invokeMethod<String>('releasePoint'"));
    });

    // Đây là luật đắt nhất của cả lượt, và nó KHÔNG có triệu chứng nào ngoài
    // hoá đơn pin: một quãng nắm cài bằng cách app gọi `movePoint` 30 lần mỗi
    // giây vẫn cho ra đúng hình ấy trên màn. Cái giá là 30 lượt qua kênh nền
    // mỗi giây, 30 lượt gỡ-và-thêm `ARAnchor`, và 30 `ArMeasureMoveResult`
    // không ai đọc.
    test('quãng nắm sống ở tầng Swift, không phải một vòng lặp bên Dart', () {
      expect(
        _withoutComments(sessionSource),
        contains('private func stepDrag('),
        reason:
            'Điểm đang nắm bám theo tia ở tầng Swift, mỗi khung hình, trong '
            'cùng lượt dò mà tâm ngắm đã chạy.',
      );

      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func stepDrag('),
      );
      expect(
        than,
        isNot(contains('raycastFromReticle')),
        reason:
            'Lượt dò của khung hình này đã bắn tia rồi và kết quả được truyền '
            'vào. Bắn lần thứ hai là hai tia khác nhau trong cùng một khung — '
            'điểm đi tới một chỗ, tâm ngắm hứa một chỗ khác.',
      );
    });

    test('đang nắm thì dò MỖI khung hình, không theo nhịp 10 Hz', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func probeReticle('),
      );

      expect(
        RegExp(r'drag != nil').hasMatch(than),
        isTrue,
        reason:
            'Ở `measured` lượt dò bị giãn xuống 10 Hz, và một đầu mút đang bị '
            'kéo mà chỉ nhích 10 lần mỗi giây thì đọc ra một đầu mút GIẬT — '
            'đúng cái cảm giác "nhích được một khoảng" mà cả lượt này đi bỏ.',
      );
    });

    // Nguyên văn lời đặt hàng: *"một cái thước dây không rơi mất đầu khi tay
    // che mất vạch"*. Tia trượt giữa quãng nắm là chuyện xảy ra liên tục — rê
    // qua một mép bàn, qua một vệt sáng — và ở đó đầu mút phải ĐỨNG YÊN chờ,
    // không được rơi về chỗ cũ và cũng không được biến mất.
    test('tia trượt giữa quãng nắm thì đầu mút ĐỨNG YÊN', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func stepDrag('),
      );

      expect(
        than,
        isNot(contains('.miss(')),
        reason:
            'Quãng ôm của `LivePointFilter` hết hạn sau 100 ms và trả `nil`, và '
            'ở đây `nil` nghĩa là đầu mút rơi về vị trí ARAnchor CŨ — tức là '
            'nhảy ngược lại chỗ trước khi nắm, giữa lúc tay người dùng vẫn đang '
            'giữ nó. Quãng nắm chỉ dùng nửa LÀM MƯỢT của bộ lọc.',
      );
      expect(
        than,
        isNot(contains('drag = nil')),
        reason:
            'Một khung trượt không kết thúc quãng nắm. Chỉ `releasePoint` và '
            'các đường buông an toàn mới được buông.',
      );
    });

    // Hai đường chốt điểm — một nhát `movePoint`, và cái buông ở cuối một quãng
    // kéo — phải đi qua CÙNG một hàm. Hai bản chép lệch nhau thì một đường gỡ
    // anchor cũ còn đường kia quên, hoặc một đường thay khối chẩn đoán còn
    // đường kia để nguyên khối của lần chấm trước; cả hai hỏng câm.
    test('nhát dời và cú buông chốt điểm qua CÙNG một hàm', () {
      final sach = _withoutComments(sessionSource);

      expect(sach, contains('private func replacePoint('));
      expect(
        RegExp(r'replacePoint\(').allMatches(sach).length,
        3,
        reason:
            'Một lần khai và HAI chỗ gọi — `movePoint(at:)` và `releasePoint()`.',
      );

      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func replacePoint('),
      );
      expect(than, contains('ARAnchor('));
      expect(
        than,
        contains('sceneView.session.remove(anchor:'),
        reason:
            'Không gỡ là để lại một anchor mồ côi cho mỗi lượt chốt. Nó không '
            'vẽ gì (node bị chặn), nên nó tích lại im lặng.',
      );
      expect(than, contains('sceneView.session.add(anchor:'));
      expect(
        than,
        contains('pointDiagnostics.removeValue(forKey:'),
        reason:
            'Khối chẩn đoán CŨ phải rời map cùng lúc anchor cũ rời phiên. Để '
            'lại là một khối gán cho một điểm không còn tồn tại, và nó lớn dần.',
      );
    });

    // CA BẮT LỖI THẬT của cả lượt. Kéo trong CÙNG một mặt phẳng là ca mù: lai
    // lịch của chỗ đầu và của chỗ cuối trùng nhau, nên mọi cách cài đều xanh.
    // Thứ phân biệt chúng là một quãng kéo ĐỔI mặt phẳng — mặt bàn sang sàn —
    // và ở đó một khối lai lịch chốt sai đọc ra những con số hoàn toàn hợp lệ.
    test('buông chốt lai lịch của chỗ CUỐI, không của chỗ đầu', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'func releasePoint('),
      );

      expect(
        than,
        contains('diagnostics'),
        reason: 'cú buông phải chốt một khối lai lịch',
      );
      expect(
        than,
        isNot(contains('makeDiagnostics(')),
        reason:
            'Lai lịch KHÔNG được dựng lại ở lúc buông: `rayAngleDeg` và '
            '`cameraDistanceMm` đo so với tư thế camera HIỆN TẠI, mà tư thế ấy '
            'không phải tư thế đã sinh ra lượt trúng cuối. Dựng lại ở đây là '
            'gán một góc chưa ai bắn cho một điểm đã đứng yên. Khối phải được '
            'ghi tại CHÍNH khung hình đã đặt điểm tới chỗ ấy.',
      );

      final buoc = _withoutComments(
        _swiftMethodBody(sessionSource, 'private func stepDrag('),
      );
      expect(
        buoc,
        contains('makeDiagnostics('),
        reason:
            'và chỗ ghi nó là mỗi bước kéo — khối của bước CUỐI chính là khối '
            'của chỗ điểm dừng lại.',
      );
    });

    // "Nắm mà app chết thì điểm không được kẹt ở trạng thái đang nắm."
    test('mọi đường ra khỏi quãng nắm đều BUÔNG', () {
      for (final signature in [
        'func stop()',
        'func pause()',
        'func undoPoint()',
        'func movePoint(at index: Int)',
        'func sessionWasInterrupted(',
      ]) {
        expect(
          _withoutComments(_swiftMethodBody(sessionSource, signature)),
          contains('releasePoint()'),
          reason:
              '`$signature` bỏ quãng nắm lại phía sau. Đầu mút kẹt ở trạng thái '
              'đang nắm, và app không có đường nào biết để vẽ lại.',
        );
      }

      expect(
        _withoutComments(
          _swiftMethodBody(sessionSource, 'private func clearAnchors('),
        ),
        contains('drag = nil'),
        reason:
            'Bỏ hết điểm thì cái đang nắm không còn tồn tại. Ở đây KHÔNG chốt '
            'gì — chốt một điểm vào một danh sách vừa bị xoá là thêm lại đúng '
            'cái điểm mà `reset` vừa bỏ.',
      );
    });

    // App phải biết phiên còn đang nắm hay không, và biết từ MỘT nguồn: gói tự
    // buông ở những đường app không gây ra.
    test('đầu mút đang nắm đi lên Dart, và Dart đọc', () {
      expect(sessionSource, contains('"grabbedPointIndex"'));
      expect(dartSource, contains("raw['grabbedPointIndex']"));
      expect(dartSource, contains('grabbedPointIndex'));
    });

    // Vị trí ĐANG VẼ của một điểm đang bị kéo đọc từ một chỗ DUY NHẤT. Hai phép
    // tra chép tay lệch nhau thì hình vẽ bám theo tia còn con số tính trên
    // ARAnchor chưa đổi — đúng cái "số và hình nói hai chuyện khác nhau" mà cả
    // đường dời đầu mút sinh ra để đóng, chỉ lật ngược.
    test('hình vẽ và con số đọc CHUNG một vị trí khi đang kéo', () {
      final sach = _withoutComments(sessionSource);

      expect(sach, contains('private func position(ofPointAt'));
      expect(
        RegExp(r'position\(ofPointAt:').allMatches(sach).length,
        greaterThanOrEqualTo(3),
        reason:
            'Một lần khai và ít nhất hai chỗ gọi — `currentMarks()` (hình vẽ '
            'SceneKit và khung lớp phủ) và `currentDistanceMm()` (con số).',
      );

      for (final signature in [
        'private func currentMarks()',
        'private func currentDistanceMm()',
      ]) {
        expect(
          _withoutComments(_swiftMethodBody(sessionSource, signature)),
          contains('position(ofPointAt:'),
          reason:
              '`$signature` còn đọc thẳng `anchor.transform`, nên nó đứng im '
              'suốt quãng kéo trong khi chỗ kia đã chạy theo tia.',
        );
      }
    });
  });

  group('chụp ảnh cảnh', () {
    // Cả bảy ca dưới đây canh cùng một dạng hỏng: ảnh VẪN ra, tệp VẪN có, và
    // thứ sai chỉ lộ ra khi mở ảnh lên xem trên một máy khác.
    test('lệnh khớp từng chữ giữa Swift và Dart', () {
      expect(pluginSource, contains('case "captureFrame":'));
      expect(dartSource, contains("invokeMethod<String>('captureFrame'"));
    });

    test('chụp CẢNH bằng snapshot(), không đọc capturedImage nữa', () {
      final sach = _withoutComments(sessionSource);

      expect(
        sach,
        contains('sceneView.snapshot()'),
        reason:
            'Từ 0.13.0 đường kẻ, hai chấm và viên số đều là node trong cảnh, '
            'nên ảnh của CẢNH là đúng thứ người dùng vừa nhìn — theo định '
            'nghĩa, chứ không theo một phép dựng lại ở Dart.',
      );
      expect(
        sach,
        isNot(contains('capturedImage')),
        reason:
            'Khung camera THUẦN là nền của bản cài THỨ HAI đã bị bỏ: app vẽ '
            'lại đường kẻ, hai chấm và viên số bằng canvas từ toạ độ chiếu. '
            'Giữ đường này lại là mời nó quay về.',
      );
      expect(
        sach,
        isNot(contains('displayTransform(for:')),
        reason:
            'Phép xoay ấy tồn tại vì `capturedImage` nằm theo CẢM BIẾN. '
            '`snapshot()` dựng theo KHUNG NGẮM, nên xoay thêm một lượt nữa là '
            'lật ảnh đi một phần tư vòng.',
      );
    });

    test('snapshot() chạy trên LUỒNG CHÍNH', () {
      final than = _withoutComments(
        _swiftMethodBody(sessionSource, 'func captureFrame()'),
      );

      expect(
        than,
        contains('Thread.isMainThread'),
        reason:
            '`SCNView.snapshot()` đọc thẳng bộ dựng hình của view. Gọi nó từ '
            'một luồng khác không ném lỗi nào — nó trả một tấm ảnh ĐEN, hoặc '
            'làm hỏng lượt dựng hình đang chạy.',
      );
      expect(
        than,
        contains('DispatchQueue.main.sync'),
        reason:
            'Nhánh không-phải-luồng-chính phải ĐỢI ảnh chứ không bỏ qua: giá '
            'trị trả về của một cú bấm nút không chờ được một callback.',
      );
    });

    test('ghi ĐÚNG CHIỀU bằng cách nướng hướng, không dựa cờ EXIF', () {
      final sach = _withoutComments(sessionSource);

      expect(
        sach,
        contains('imageOrientation == .up'),
        reason:
            '`snapshot()` trả `.up` trên mọi máy đã thử, nhưng một `UIImage` '
            'mang hướng khác đi thẳng qua `cgImage` là RỤNG mất phép xoay — '
            'ảnh vẫn ra, vẫn đúng tỉ lệ, chỉ nằm nghiêng.',
      );
      expect(
        sach,
        isNot(contains('kCGImagePropertyOrientation')),
        reason:
            'ghi cờ hướng là nói "ảnh nằm nghiêng, người xem tự xoay hộ" — '
            'đúng thứ mà spec §5.1 cấm dựa vào.',
      );
    });

    test('lượt nướng hướng GIỮ hệ số điểm ảnh của tấm ảnh', () {
      expect(
        _withoutComments(sessionSource),
        contains('format.scale = image.scale'),
        reason:
            '`UIGraphicsImageRendererFormat()` mặc định lấy hệ số của MÀN '
            'CHÍNH, không lấy của tấm ảnh. Trên một máy mà hai số ấy khác '
            'nhau, ảnh ra đúng chiều và sai cỡ — và app quy toạ độ lớp phủ '
            'sang toạ độ ảnh bằng đúng tỉ lệ ấy.',
      );
    });

    // Đây là ca giữ cho lượt đổi sang `snapshot()` không kéo theo thứ mà
    // chính chú thích cũ của `captureFrame` sợ: *"một tấm thẻ chữ trắng chình
    // ình giữa ảnh"*.
    //
    // `snapshot()` dựng CẢNH SceneKit, không dựng cây UIView. Nên lời hứa
    // "hướng dẫn quét không lọt vào ảnh" quy về đúng một tính chất kiểm được:
    // lớp hướng dẫn là một SUBVIEW, và cảnh chỉ có node đo.
    test('hướng dẫn quét là SUBVIEW, nên snapshot() không thấy nó', () {
      final sach = _withoutComments(sessionSource);

      expect(
        sach,
        contains('sceneView.addSubview(coachingOverlay)'),
        reason:
            'Nó phải ở cây UIView. `SCNView.snapshot()` dựng cảnh bằng bộ dựng '
            'hình của SceneKit và KHÔNG đi qua `drawHierarchy`, nên mọi '
            'subview nằm ngoài ảnh.',
      );
      expect(
        sach,
        isNot(contains('rootNode.addChildNode(coachingOverlay')),
        reason:
            'Đưa hướng dẫn quét vào CẢNH là đưa nó vào ảnh — cùng cửa với hình '
            'đo.',
      );

      final vaoCanh = RegExp(
        r'rootNode\.addChildNode\(([^)]*)\)',
      ).allMatches(sach).map((m) => m.group(1)!.trim()).toList();
      expect(
        vaoCanh,
        ['measureNodes.root'],
        reason:
            'Cảnh chỉ được chứa hình ĐO. Mỗi node thêm vào đây từ nay đi thẳng '
            'vào mọi tấm ảnh người dùng chụp, và không ca kiểm nào khác nói ra '
            'điều đó.',
      );
    });

    test('ảnh nằm ở thư mục TẠM, không nằm trong Documents', () {
      final than = _swiftMethodBody(
        sessionSource,
        'private func captureSceneOnMain()',
      );

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
/// nó — `contentScaleFactor`, `projected.z`, `livePoint`. Không bóc thì ca kiểm
/// xanh nhờ chính lời chú thích, và nó hỏng theo CẢ HAI chiều:
///
/// * ca `contains` xanh sau khi dòng mã đã bị xoá, vì lời giải thích còn nằm đó;
/// * ca `isNot(contains)` ĐỎ dù dòng mã đã bị bỏ đúng như phải thế, vì lời giải
///   thích *vì sao* nó bị bỏ buộc phải gọi tên nó. Chiều này có thật từ 0.9.1,
///   khi ca canh phép chia `contentScaleFactor` đổi chiều.
String _withoutComments(String swift) {
  return swift.replaceAll(RegExp(r'//.*'), '');
}
