import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ca kiểm SỐ của bộ lọc đầu mút sống — chạy phép tính Swift thật, không đọc chữ.
///
/// Cùng lối với `plane_overshoot_test.dart`, và vì cùng một lẽ: mọi cách viết
/// SAI mà lượt này phải chặn đều để lại một tệp Swift trông hợp lý và một toạ
/// độ trông hợp lý. Thứ phân biệt chúng là GIÁ TRỊ và NHỊP, nên ca kiểm phải
/// chạy phép tính.
///
/// Chạy được là nhờ `LivePoint.swift` chỉ nhập `Foundation` và `simd` — không
/// `ARKit`, không `SceneKit`, không `UIKit` — nên nó dịch và chạy thẳng trên
/// macOS bằng `swiftc`.
///
/// **Vì sao bộ lọc này tồn tại.** Người dùng trên máy thật: *"đoạn thẳng vẫn
/// chưa mượt lắm. Đặc biệt ở đầu mút có thể nhấp nháy liên tục"* — ở 60 khung/s,
/// nên nhịp khung không phải nguyên nhân. Đường VẼ đã đúng từ trước: năm node
/// dựng một lần ở `init`, mỗi khung chỉ đổi `simdPosition` và `isHidden`. Thứ
/// nháy là NGUỒN toạ độ:
///
/// * một khung mà tia trượt xoá thẳng đầu sống → cả đoạn ẩn đúng một khung rồi
///   hiện lại;
/// * ba tầng tia thử theo thứ tự, nên hai khung liên tiếp trả về hai BỀ MẶT
///   khác nhau — điểm nhảy hàng centimét mà vẫn "trúng".
///
/// **Cái giá của bộ lọc là ĐỘ TRỄ, và ca `treKhiRe` dưới đây đo nó ra milimét
/// thay vì để nó trốn trong một hằng số.** Nâng `smoothingSeconds` là đổi đúng
/// con số ấy, và ca kiểm sẽ nói ra ngay.
///
/// **Điều bộ lọc KHÔNG đụng tới:** `placePoint()` bắn một tia MỚI, không đọc
/// đầu sống — nên độ trễ và quãng ôm ở đây không đẩy điểm đã chấm đi đâu cả.
/// Chúng chỉ đổi thứ được VẼ.
///
/// **Không có nhánh "bỏ qua khi thiếu swiftc"**, cùng lý do với ca kiểm hình
/// học: gói chỉ có nền tảng iOS, nên máy nào dựng được nó cũng có Xcode.
void main() {
  group('LivePointFilter · đầu mút sống, lọc theo thời gian', () {
    late Map<String, String> ketQua;

    setUpAll(() {
      ketQua = _chayLocSwift();
    });

    /// Mẫu ĐẦU TIÊN ra đúng chính nó, không trôi từ đâu tới.
    ///
    /// Một bộ lọc khởi tạo ở gốc toạ độ sẽ trả về một điểm nằm giữa gốc và mẫu
    /// — trên máy đó là đoạn thẳng đầu tiên phóng ra từ chỗ người dùng đứng lúc
    /// mở app, rồi bò về chỗ đúng trong một phần mười giây.
    test('mẫu đầu tiên KHÔNG bị làm mượt', () {
      expect(_so(ketQua, 'dauTienX'), closeTo(1.0, 1e-5));
      expect(
        _so(ketQua, 'dauTienZ'),
        closeTo(-2.0, 1e-5),
        reason:
            'Bộ lọc trống thì mẫu đầu tiên là sự thật duy nhất đang có. Trộn nó '
            'với một trạng thái chưa tồn tại là bịa ra một điểm.',
      );
    });

    /// Máy đứng yên, tia trả về cùng một điểm: bộ lọc phải HỘI TỤ về đúng điểm
    /// ấy, không đứng lại ở giữa đường.
    test('mẫu lặp lại thì hội tụ về đúng mẫu', () {
      expect(
        _so(ketQua, 'hoiTuSaiSoMm'),
        lessThan(0.05),
        reason:
            'Người dùng giữ yên máy để bấm. Nếu bộ lọc dừng lại cách mẫu một '
            'quãng cố định thì đoạn vẽ ra và điểm sắp chấm không bao giờ trùng '
            'nhau, dù đứng yên bao lâu.',
      );
    });

    /// Nhiễu xen kẽ ±10 mm ở 60 Hz — đúng dạng của hai tầng tia thay nhau trúng.
    ///
    /// Vào: biên độ đỉnh-đỉnh **20 mm**.
    /// Ra (trạng thái dừng, `smoothingSeconds` = 0,03 s, `dt` = 1/60 s):
    /// **5,42 mm** — hệ số `α/(2−α)` với `α = 1 − e^(−dt/τ) = 0,4262`.
    ///
    /// Ca này bắt CẢ HAI phía: bỏ phép lọc thì ra 20, đóng băng thì ra 0.
    test('nhiễu xen kẽ bị nén xuống còn hơn một phần tư', () {
      expect(
        _so(ketQua, 'nhieuRaMm'),
        closeTo(5.42, 0.6),
        reason:
            'Vào 20 mm đỉnh-đỉnh. Ra 20 nghĩa là không có phép lọc nào; ra 0 '
            'nghĩa là đầu mút đã đóng băng và không còn đi theo tâm ngắm. Con '
            'số đúng nằm giữa, và nó suy được từ hai hằng số — đổi hằng số mà '
            'quên đổi ở đây thì ca này đỏ, đúng như phải thế.',
      );
    });

    /// Rê máy đều, mỗi khung đi 8 mm (≈ 0,48 m/s). Trạng thái dừng của một bộ
    /// lọc mũ tụt lại sau mẫu đúng `d·(1−α)/α` = **10,77 mm**.
    ///
    /// Đây là CÁI GIÁ, viết ra thành số. Nó không được phép trốn trong một
    /// hằng số mà không ai đọc.
    test('độ trễ khi rê máy đo được bằng milimét, không giấu trong hằng số', () {
      expect(
        _so(ketQua, 'treKhiReMm'),
        closeTo(10.77, 1.0),
        reason:
            'Đầu mút vẽ ra tụt sau tâm ngắm chừng một centimét trong lúc rê. '
            'Nâng `smoothingSeconds` là nâng đúng con số này — 0,06 s cho ra '
            '23 mm, và ở đó đoạn thẳng đọc ra như một sợi dây bị kéo lê. Người '
            'dùng dừng tay để bấm thì nó về 0 (ca hội tụ ở trên).',
      );
    });

    /// Một khung trượt giữa một chuỗi trúng: giữ nguyên điểm cũ.
    test('một khung trượt KHÔNG tắt đoạn thẳng', () {
      expect(
        ketQua['omMotKhung'],
        isNull,
        reason:
            'Trả `nil` thì chương trình in ra khoá trần `omMotKhung`; có toạ độ '
            'thì nó in ba khoá `X`/`Y`/`Z`. Khoá trần có mặt là đã buông.',
      );
      expect(
        _so(ketQua, 'omMotKhungX'),
        closeTo(1.0, 1e-5),
        reason:
            'Đây là chính cái nháy phải chữa. Xoá đầu sống ở khung trượt là ẩn '
            'cả đoạn thẳng đúng 16 ms rồi hiện lại, và một chuỗi trúng-trượt xen '
            'kẽ ở 60 Hz đọc ra một cái nháy liên tục ở đầu mút.',
      );
    });

    /// Trượt quá quãng ôm: buông.
    test('trượt quá quãng ôm thì BUÔNG, không ôm mãi', () {
      expect(
        ketQua['omHetHan'],
        'nil',
        reason:
            'Giữ lại vô hạn là vẽ một đoạn ĐỨNG YÊN giữa lúc người dùng vẫn '
            'đang rê máy — và một đoạn đứng yên đọc ra "đã chấm xong". Quãng ôm '
            'chữa cái nháy; nó không được phép chữa luôn cả sự thật.',
      );
    });

    /// Sau khi buông rồi trúng lại ở một chỗ khác hẳn: nhận thẳng.
    test('trúng lại sau khi đã buông thì KHÔNG trộn với điểm trước quãng hở', () {
      expect(
        _so(ketQua, 'trucLaiX'),
        closeTo(3.5, 1e-5),
        reason:
            'Điểm trước quãng hở đã bị buông, nên nó không còn là dữ kiện nào '
            'nữa. Trộn với nó là để đoạn thẳng bò từ một bề mặt cũ sang bề mặt '
            'mới, và quãng bò ấy dài đúng bằng quãng giữa hai bề mặt.',
      );
    });

    /// Mẫu không hữu hạn coi như một lượt TRƯỢT, và không được lọt vào trạng thái.
    test('mẫu không hữu hạn không đầu độc bộ lọc', () {
      expect(
        _so(ketQua, 'hongGiuLaiX'),
        closeTo(1.0, 1e-5),
        reason:
            'NaN cộng vào một trạng thái mũ thì cả trạng thái thành NaN, vĩnh '
            'viễn — và một node có transform NaN thì SceneKit bỏ vẽ, im lặng. '
            'Đoạn thẳng biến mất và không bao giờ trở lại, không lỗi nào nổ.',
      );
      expect(_so(ketQua, 'hongSauDoX'), closeTo(1.0, 0.2));
    });

    /// `clear()` là XOÁ CỨNG, không đi qua quãng ôm.
    test('xoá cứng thì buông ngay, kể cả trong quãng ôm', () {
      expect(
        ketQua['xoaCung'],
        'nil',
        reason:
            '`reset()` dựng lại cả hệ toạ độ. Ôm thêm 100 ms ở đó là vẽ tới một '
            'toạ độ thuộc về hệ CŨ — một chỗ trông hoàn toàn bình thường và '
            'không còn liên quan gì tới thứ đang ở trước ống kính.',
      );
    });

    /// Đồng hồ lùi (không nên xảy ra, nhưng `dt` âm thì `1 − e^(−dt/τ)` âm).
    test('dt âm không đẩy điểm ra ngoài đoạn giữa hai mẫu', () {
      expect(
        _so(ketQua, 'dongHoLuiX'),
        closeTo(1.0, 1e-5),
        reason:
            'Một `α` âm kéo điểm ra NGƯỢC phía mẫu mới — đầu mút bay ra xa dần '
            'mỗi khung, và không có gì trong toạ độ nói ra vì sao.',
      );
    });
  });
}

/// Dịch `LivePoint.swift` cùng một chương trình thử rồi đọc kết quả in ra.
Map<String, String> _chayLocSwift() {
  final filter = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/LivePoint.swift',
  );
  expect(
    filter.existsSync(),
    isTrue,
    reason:
        'không tìm thấy ${filter.path} — phép lọc đầu mút phải nằm ở một tệp '
        'KHÔNG nhập ARKit, nếu không thì không ca kiểm nào chạy nổi nó ngoài '
        'một máy iOS thật.',
  );

  final temp = Directory.systemTemp.createTempSync('live_point_test');
  addTearDown(() => temp.deleteSync(recursive: true));

  final harness = File('${temp.path}/main.swift')..writeAsStringSync(_harness);
  final binary = '${temp.path}/live_point';

  final built = Process.runSync('swiftc', [
    '-O',
    filter.absolute.path,
    harness.path,
    '-o',
    binary,
  ]);
  expect(
    built.exitCode,
    0,
    reason:
        'swiftc không dịch được bộ lọc:\n${built.stderr}\n'
        'Nếu lỗi là "cannot find type in scope" thì tệp đã nhập một khung của '
        'iOS — nó phải chỉ nhập Foundation và simd.',
  );

  final ran = Process.runSync(binary, const []);
  expect(ran.exitCode, 0, reason: 'chương trình lọc chạy hỏng:\n${ran.stderr}');

  final ketQua = <String, String>{};
  for (final line in const LineSplitter().convert(ran.stdout as String)) {
    final i = line.indexOf('=');
    if (i > 0) ketQua[line.substring(0, i)] = line.substring(i + 1);
  }
  expect(ketQua, isNotEmpty, reason: 'chương trình lọc không in ra gì');
  return ketQua;
}

double _so(Map<String, String> ketQua, String ten) {
  final raw = ketQua[ten];
  expect(raw, isNotNull, reason: 'chương trình lọc không in ra khoá `$ten`');
  expect(raw, isNot('nil'), reason: '`$ten` trả nil, không phải một con số');
  return double.parse(raw!);
}

/// Chương trình Swift bơm từng chuỗi mẫu vào bộ lọc rồi in kết quả.
///
/// Nhịp khung và hằng số của bộ lọc nằm CẠNH đáp án mong đợi ở phần `test`
/// phía trên — tách ra là mở đúng chỗ cho một ca kiểm mù: ai đó sửa hằng số mà
/// quên sửa đáp án, và ca vẫn xanh vì đáp án cũ tình cờ vẫn khớp.
const String _harness = r'''
import Foundation
import simd

/// Một khung ở 60 khung/s.
let dt = 1.0 / 60.0

func report(_ name: String, _ v: Float?) {
  print("\(name)=\(v.map { String($0) } ?? "nil")")
}

func reportPoint(_ name: String, _ p: SIMD3<Float>?) {
  guard let p else {
    print("\(name)=nil")
    return
  }
  print("\(name)X=\(p.x)")
  print("\(name)Y=\(p.y)")
  print("\(name)Z=\(p.z)")
}

// ---- Mẫu đầu tiên ra đúng chính nó ------------------------------------------
do {
  var f = LivePointFilter()
  let out = f.hit(SIMD3<Float>(1, 0.5, -2), at: 0)
  reportPoint("dauTien", out)
}

// ---- Mẫu lặp lại thì hội tụ --------------------------------------------------
do {
  var f = LivePointFilter()
  let target = SIMD3<Float>(0.3, -0.1, -1.4)
  // Mẫu đầu ở một chỗ KHÁC hẳn, để phép hội tụ có quãng đường mà đi. Bắt đầu
  // ngay tại đích thì ca này xanh với cả một bộ lọc đóng băng.
  _ = f.hit(SIMD3<Float>(0.9, 0.4, -2.2), at: 0)
  var t = dt
  for _ in 0..<40 {
    _ = f.hit(target, at: t)
    t += dt
  }
  let sai = simd_distance(f.point ?? SIMD3<Float>(repeating: .nan), target)
  report("hoiTuSaiSoMm", sai * 1000)
}

// ---- Nhiễu xen kẽ ±10 mm -----------------------------------------------------
do {
  var f = LivePointFilter()
  let tam = SIMD3<Float>(0, 0, -1)
  let lech = SIMD3<Float>(0, 0, 0.010)
  var t = 0.0
  var thap = Float.infinity
  var cao = -Float.infinity
  for i in 0..<80 {
    _ = f.hit(tam + (i % 2 == 0 ? lech : -lech), at: t)
    t += dt
    // Chỉ đo 20 bước CUỐI: hai chục bước đầu là quãng quá độ, và nó rộng hơn
    // trạng thái dừng — đo cả chuỗi là đo nhầm một con số lớn hơn sự thật.
    if i >= 60, let p = f.point {
      thap = min(thap, p.z)
      cao = max(cao, p.z)
    }
  }
  report("nhieuRaMm", (cao - thap) * 1000)
}

// ---- Rê máy đều: độ trễ trạng thái dừng --------------------------------------
do {
  var f = LivePointFilter()
  let buoc: Float = 0.008
  var t = 0.0
  var mau = SIMD3<Float>(0, 0, -1)
  var tre: Float = .nan
  for i in 0..<200 {
    _ = f.hit(mau, at: t)
    if i >= 150, let p = f.point {
      tre = mau.x - p.x
    }
    mau.x += buoc
    t += dt
  }
  report("treKhiReMm", tre * 1000)
}

// ---- Một khung trượt giữa chuỗi trúng ----------------------------------------
do {
  var f = LivePointFilter()
  _ = f.hit(SIMD3<Float>(1, 0, -1), at: 0)
  let out = f.miss(at: dt)
  reportPoint("omMotKhung", out)
}

// ---- Trượt quá quãng ôm ------------------------------------------------------
do {
  var f = LivePointFilter()
  _ = f.hit(SIMD3<Float>(1, 0, -1), at: 0)
  // 0,15 s > holdSeconds. Bơm cả chuỗi khung trượt chứ không nhảy thẳng tới
  // 0,15: một lượt buông chỉ xảy ra ở lượt gọi vượt hạn, và nếu lời chặn đặt
  // sai thì chuỗi khung ở GIỮA sẽ nạp lại mốc — một ca nhảy thẳng không thấy.
  var t = dt
  var out: SIMD3<Float>? = nil
  while t <= 0.15 {
    out = f.miss(at: t)
    t += dt
  }
  reportPoint("omHetHan", out)
}

// ---- Buông rồi trúng lại ở chỗ khác ------------------------------------------
do {
  var f = LivePointFilter()
  _ = f.hit(SIMD3<Float>(1, 0, -1), at: 0)
  var t = dt
  while t <= 0.15 {
    _ = f.miss(at: t)
    t += dt
  }
  let out = f.hit(SIMD3<Float>(3.5, 0, -1), at: t)
  reportPoint("trucLai", out)
}

// ---- Mẫu không hữu hạn -------------------------------------------------------
do {
  var f = LivePointFilter()
  _ = f.hit(SIMD3<Float>(1, 0, -1), at: 0)
  let giuLai = f.hit(SIMD3<Float>(.nan, 0, -1), at: dt)
  reportPoint("hongGiuLai", giuLai)
  // Và trạng thái không bị đầu độc: mẫu hữu hạn ngay sau đó vẫn ra số thật.
  let sauDo = f.hit(SIMD3<Float>(1.01, 0, -1), at: dt * 2)
  reportPoint("hongSauDo", sauDo)
}

// ---- Xoá cứng ----------------------------------------------------------------
do {
  var f = LivePointFilter()
  _ = f.hit(SIMD3<Float>(1, 0, -1), at: 0)
  f.clear()
  reportPoint("xoaCung", f.miss(at: dt))
}

// ---- Đồng hồ lùi -------------------------------------------------------------
do {
  var f = LivePointFilter()
  _ = f.hit(SIMD3<Float>(1, 0, -1), at: 10)
  let out = f.hit(SIMD3<Float>(2, 0, -1), at: 9.9)
  reportPoint("dongHoLui", out)
}
''';
