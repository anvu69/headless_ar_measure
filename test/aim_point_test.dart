import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ca kiểm SỐ của điểm ngắm — chạy phép tính Swift thật, không đọc chữ.
///
/// Cùng lối với `plane_overshoot_test.dart` và `video_format_choice_test.dart`,
/// và vì cùng một lẽ: mọi cách cài sai ở đây để lại một tệp Swift trông hoàn
/// toàn hợp lý và một toạ độ màn trông hoàn toàn hợp lý. Thứ phân biệt chúng là
/// CON SỐ ra được, nên ca kiểm phải chạy phép tính.
///
/// Hai câu hỏi ca kiểm này canh, và cả hai đều đã có giá trên máy thật ở gói
/// này một lần rồi:
///
/// 1. **Đơn vị.** Từ `0.2.0` tới `0.9.0` phép chiếu chia cho `contentScaleFactor`
///    và nhãn lệch đúng một hệ số nguyên trên hai máy khác hệ số. Nay mọi thứ ở
///    **point**, và một điểm ngắm nhận vào ở đơn vị khác là dựng lại đúng cái
///    lỗi ấy cho đầu vào thay vì cho đầu ra.
/// 2. **Ngoài khung.** Ngón tay trượt ra mép màn là chuyện thường; một tia bắn
///    từ ngoài khung nhìn là một tia ARKit chưa quan sát chỗ nào, nên chỉ tầng
///    ngoại suy trả lời được — và nó trả lời bằng một con số milimét trông hợp
///    lệ, đo trên một mặt phẳng camera không hề thấy.
void main() {
  group('AimPoint · toạ độ điểm ngắm', () {
    late Map<String, String> ketQua;

    setUpAll(() {
      ketQua = _chayPhepTinhSwift();
    });

    /// **CA BẮT LỖI THẬT của cả lượt.**
    ///
    /// Một ca dùng đúng tâm màn là ca MÙ: nó xanh y hệt khi tham số điểm ngắm
    /// bị bỏ qua hoàn toàn, vì đáp án của "bỏ qua" và đáp án của "dùng" trùng
    /// nhau ở đúng một điểm — tâm. Hai dòng dưới đây phá chỗ trùng ấy.
    test('điểm KHÁC tâm màn cho ra toạ độ KHÁC tâm màn', () {
      final tam = _diem(ketQua, 'tamMan');
      final ngon = _diem(ketQua, 'ngonKhongOTam');

      expect(
        ngon,
        isNot(_gan(tam)),
        reason:
            'Nếu hai con số này bằng nhau thì điểm ngắm đang bị bỏ qua và mọi '
            'tia vẫn bắn từ tâm màn — đúng cái hỏng câm mà cả lượt này đi sửa.',
      );
      expect(
        ngon,
        _gan(const [120, 200]),
        reason: 'điểm nằm trong khung thì đi thẳng ra, không nắn gì',
      );
      expect(tam, _gan(const [201, 437]));
    });

    /// Đơn vị là **point**, cùng hệ với `sceneView.bounds` và với
    /// `ArMeasureOverlay.pointA`/`pointB`.
    ///
    /// Khung 402×874 là iPhone 16 tính bằng point. Cùng cái màn ấy là
    /// 1206×2622 điểm ảnh. Hai ca dưới đây chỉ phân biệt được hai hệ ấy.
    test('đơn vị là point, không phải điểm ảnh', () {
      expect(
        _diem(ketQua, 'trongKhungTheoPoint'),
        _gan(const [390, 860]),
        reason:
            '(390, 860) nằm TRONG khung 402×874 point. Nếu con số vào được '
            'hiểu là điểm ảnh thì chỗ ấy là (130, 286,7) trên màn @3x — một '
            'chỗ khác hẳn, và không có gì trong hai con số nói ra chuyện đó.',
      );
      expect(
        _diem(ketQua, 'theoDiemAnhThiNgoaiKhung'),
        _gan(const [402, 874]),
        reason:
            '(1200, 2600) là toạ độ ĐIỂM ẢNH của gần đúng chỗ trên, trên màn '
            '@3x. Ở hệ point nó nằm ngoài khung và phải bị kẹp về góc. Xanh ở '
            'đây mà đỏ ở ca trên nghĩa là ai đó đã nhân hệ số điểm ảnh vào.',
      );
      expect(
        ketQua['trongKhungTheoDiemAnh'],
        'false',
        reason:
            'Một điểm ảnh không bao giờ là một point. Nếu chỗ này nói "true" '
            'thì khung đang được đọc ở hệ điểm ảnh.',
      );
    });

    /// Ngoài khung thì **KẸP**, không coi là trượt.
    ///
    /// Vì sao kẹp chứ không trượt: kẹp giữ được đúng nửa sau của cử chỉ người
    /// dùng xin — *"vừa giữ ngón tay vừa lia camera thì đầu mút cũng đi theo"*.
    /// Ngón ghim ở mép màn mà coi là trượt thì đầu mút đóng băng, và lia camera
    /// không còn kéo được nó. Kẹp thì tia vẫn bắn qua một điểm ảnh camera THẬT
    /// SỰ nhìn thấy, nên cả ba tầng tia còn trả lời trung thực.
    test('ra ngoài khung thì kẹp vào biên, cả bốn phía', () {
      expect(_diem(ketQua, 'ngoaiPhaiDuoi'), _gan(const [402, 874]));
      expect(_diem(ketQua, 'ngoaiTraiTren'), _gan(const [0, 0]));
      expect(
        _diem(ketQua, 'ngoaiMotTruc'),
        _gan(const [402, 500]),
        reason:
            'Chỉ trục vượt biên mới bị nắn. Nắn cả hai là ngón trượt ra mép '
            'phải kéo luôn đầu mút về giữa theo chiều dọc.',
      );
    });

    /// Biên là khoảng **ĐÓNG**, và đó là chỗ hàm này cố ý không dùng
    /// `CGRect.contains`.
    test('mép phải và mép dưới vẫn là TRONG khung', () {
      expect(
        ketQua['mepDuoiPhaiLaTrong'],
        'true',
        reason:
            'Kẹp và phép hỏi "có ngoài khung không" phải cùng một biên. Lệch '
            'nhau là một phép kẹp KHÔNG đổi gì mà vẫn báo là đã kẹp.',
      );
      expect(
        ketQua['mepDuoiPhaiTheoCGRect'],
        'false',
        reason:
            '`CGRect.contains` là khoảng NỬA MỞ — nó loại đúng hàng cuối và cột '
            'cuối. Ca này ghim lý do hàm tự viết phép so thay vì gọi nó.',
      );
    });

    /// Khung chưa có kích thước là một khả năng thật: platform view ở khung
    /// hình đầu tiên. Ở đó không có tâm nào và không có biên nào để kẹp vào.
    test('khung rỗng thì không có điểm nào, không bịa ra (0,0)', () {
      expect(ketQua['tamKhungRong'], 'nil');
      expect(ketQua['kepTrongKhungRong'], 'nil');
      expect(ketQua['kepTrongKhungAm'], 'nil');
    });

    /// NaN và vô cực phải chết ngay ở cửa. Kẹp một `NaN` bằng `min`/`max` cho
    /// ra `NaN` — một toạ độ đi tiếp vào `raycastQuery` và ra một lượt trượt
    /// không ai giải thích được.
    test('toạ độ không hữu hạn thì nil, không phải một con số', () {
      expect(ketQua['nanX'], 'nil');
      expect(ketQua['nanY'], 'nil');
      expect(ketQua['voCuc'], 'nil');
    });
  });
}

/// Đọc một điểm `x,y` ở ca [name].
List<double> _diem(Map<String, String> ketQua, String name) {
  final value = ketQua[name];
  expect(
    value,
    isNotNull,
    reason:
        'chương trình Swift không in ra ca "$name" — nó đã đổi tên ca hoặc '
        'chết giữa chừng',
  );
  expect(value, isNot('nil'), reason: 'ca "$name" phải có một điểm');
  final parts = value!.split(',');
  expect(parts, hasLength(2), reason: 'ca "$name" in ra "$value"');
  return [double.parse(parts[0]), double.parse(parts[1])];
}

/// So hai toạ độ theo dung sai một phần nghìn point.
Matcher _gan(List<num> expected) => pairwiseCompare<num, double>(
  expected,
  (e, a) => (a - e).abs() < 0.001,
  'khớp trong 0,001 point',
);

/// Dịch và chạy [AimPoint] thật, trả về map `tên ca` → `chuỗi in ra`.
///
/// **Không có nhánh "bỏ qua khi thiếu swiftc"**, cùng lẽ với hai ca kiểm số
/// kia: gói này chỉ có nền tảng iOS, nên máy nào dựng được nó cũng có Xcode;
/// một ca kiểm tự bỏ qua ở đây sẽ XANH trên đúng cái máy không kiểm được gì.
Map<String, String> _chayPhepTinhSwift() {
  final aim = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/AimPoint.swift',
  );
  expect(
    aim.existsSync(),
    isTrue,
    reason:
        'không tìm thấy ${aim.path} — phép tính điểm ngắm phải nằm ở một tệp '
        'KHÔNG nhập ARKit hay UIKit, nếu không thì không ca kiểm nào chạy nổi '
        'nó ngoài một máy iOS.',
  );

  final temp = Directory.systemTemp.createTempSync('aim_point_test');
  addTearDown(() => temp.deleteSync(recursive: true));

  final harness = File('${temp.path}/main.swift')..writeAsStringSync(_harness);
  final binary = '${temp.path}/aim_point';

  final built = Process.runSync('swiftc', [
    '-O',
    aim.absolute.path,
    harness.path,
    '-o',
    binary,
  ]);
  expect(
    built.exitCode,
    0,
    reason:
        'swiftc không dịch được phép tính điểm ngắm:\n${built.stderr}\n'
        'Nếu lỗi là "cannot find type in scope" thì tệp ấy đã nhập một khung '
        'của iOS — nó chỉ được nhập Foundation và CoreGraphics.',
  );

  final ran = Process.runSync(binary, const []);
  expect(
    ran.exitCode,
    0,
    reason: 'chương trình điểm ngắm chạy hỏng:\n${ran.stderr}',
  );

  final ketQua = <String, String>{};
  for (final line in const LineSplitter().convert(ran.stdout as String)) {
    final i = line.indexOf('=');
    if (i > 0) ketQua[line.substring(0, i)] = line.substring(i + 1);
  }
  expect(ketQua, isNotEmpty, reason: 'chương trình điểm ngắm không in ra gì');
  return ketQua;
}

/// Chương trình Swift dựng các khung và điểm giả rồi in kết quả.
///
/// Khung và đáp án mong đợi nằm CẠNH NHAU giữa tệp này và phần `test` phía
/// trên — cùng lối với `video_format_choice_test.dart`, và vì cùng một lẽ: tách
/// chúng xa nhau là mở đúng chỗ cho một ca kiểm mù.
const String _harness = r'''
import CoreGraphics
import Foundation

// iPhone 16 tính bằng POINT. Cùng cái màn ấy là 1206×2622 điểm ảnh — mọi ca
// đơn vị dưới đây dựng trên đúng cặp số ấy.
let man = CGRect(x: 0, y: 0, width: 402, height: 874)

func diem(_ name: String, _ point: CGPoint?) {
  guard let point else {
    print("\(name)=nil")
    return
  }
  print(String(format: "%@=%.4f,%.4f", name, point.x, point.y))
}

func co(_ name: String, _ value: Bool) {
  print("\(name)=\(value)")
}

diem("tamMan", AimPoint.centre(of: man))
diem("tamKhungRong", AimPoint.centre(of: CGRect(x: 0, y: 0, width: 0, height: 0)))

// Ngón tay KHÔNG ở tâm. Đây là ca duy nhất phân biệt "dùng điểm ngắm" với "bỏ
// qua điểm ngắm".
diem("ngonKhongOTam", AimPoint.clamped(CGPoint(x: 120, y: 200), into: man))

// Đơn vị: (390, 860) là point và nằm trong khung; (1200, 2600) là điểm ảnh của
// gần đúng chỗ ấy trên màn @3x và nằm ngoài khung.
diem("trongKhungTheoPoint", AimPoint.clamped(CGPoint(x: 390, y: 860), into: man))
diem(
  "theoDiemAnhThiNgoaiKhung",
  AimPoint.clamped(CGPoint(x: 1200, y: 2600), into: man))
co("trongKhungTheoDiemAnh", AimPoint.isInside(CGPoint(x: 1200, y: 2600), of: man))

// Kẹp bốn phía.
diem("ngoaiPhaiDuoi", AimPoint.clamped(CGPoint(x: 900, y: 2000), into: man))
diem("ngoaiTraiTren", AimPoint.clamped(CGPoint(x: -30, y: -12), into: man))
diem("ngoaiMotTruc", AimPoint.clamped(CGPoint(x: 900, y: 500), into: man))

// Biên ĐÓNG, khác `CGRect.contains` (nửa mở).
let goc = CGPoint(x: 402, y: 874)
co("mepDuoiPhaiLaTrong", AimPoint.isInside(goc, of: man))
co("mepDuoiPhaiTheoCGRect", man.contains(goc))

// Khung chưa có kích thước.
diem(
  "kepTrongKhungRong",
  AimPoint.clamped(CGPoint(x: 10, y: 10), into: CGRect.zero))
diem(
  "kepTrongKhungAm",
  AimPoint.clamped(
    CGPoint(x: 10, y: 10), into: CGRect(x: 0, y: 0, width: -5, height: 10)))

// Không hữu hạn.
diem("nanX", AimPoint.clamped(CGPoint(x: CGFloat.nan, y: 10), into: man))
diem("nanY", AimPoint.clamped(CGPoint(x: 10, y: CGFloat.nan), into: man))
diem("voCuc", AimPoint.clamped(CGPoint(x: CGFloat.infinity, y: 10), into: man))
''';
