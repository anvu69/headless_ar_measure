import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ca kiểm SỐ của quãng vượt biên — chạy phép tính Swift thật, không đọc chữ.
///
/// Mọi ca kiểm khác của gói đọc tệp Swift như văn bản. Ở đây không đủ: hai cách
/// tính SAI mà lượt này phải chặn đều để lại một tệp Swift trông hoàn toàn hợp
/// lý, và cả hai vẫn trả về một con số milimét dương, hữu hạn, cỡ đúng hàng.
/// Thứ phân biệt chúng là GIÁ TRỊ, nên ca kiểm phải chạy phép tính.
///
/// Chạy được là nhờ [PlaneOvershoot] cố ý nằm ở một tệp RIÊNG chỉ nhập
/// `Foundation` và `simd` — không `ARKit`, không `UIKit`. Nó dịch và chạy được
/// thẳng trên macOS bằng `swiftc`, nên phần hình học của gói có ca kiểm số mà
/// không cần một máy iOS nào.
///
/// Hai cách tính sai mà mỗi ca dưới đây phải bắt:
///
/// * **Đo tới ĐỈNH gần nhất thay vì tới ĐOẠN gần nhất.** Đỉnh chỉ là điểm mẫu
///   dọc biên; ARKit rải chúng thưa. Điểm nằm ngay giữa một cạnh dài thì đỉnh
///   gần nhất xa hơn cạnh rất nhiều — và con số vẫn đọc ra như một quãng vượt
///   biên bình thường.
/// * **Quên chuyển hệ toạ độ.** `boundaryVertices` nằm trong hệ CỦA MẶT PHẲNG;
///   điểm chạm nằm trong hệ THẾ GIỚI. So thẳng hai thứ ấy là cộng nguyên cả
///   quãng dời của mặt phẳng vào quãng vượt biên.
///
/// **Biên đối xứng làm ca kiểm mù**: với một hình chữ nhật quanh gốc và một
/// điểm nằm trên trục, đỉnh gần nhất và đoạn gần nhất cho cùng một số, và phép
/// dời hệ toạ độ cũng có thể triệt tiêu. Mọi hình dưới đây cố ý lệch.
void main() {
  group('PlaneOvershoot · quãng vượt biên, tính bằng mm', () {
    late Map<String, String> ketQua;

    setUpAll(() {
      ketQua = _chayHinhHocSwift();
    });

    /// Điểm nằm ngoài giữa CẠNH DÀI nhất của biên.
    ///
    /// Biên (hệ mặt phẳng, đơn vị mét, đọc theo `x` và `z`):
    ///
    /// ```
    ///   D(-0,40; 0,55) ── C(0,20; 0,60)
    ///     ╲                       ╲
    ///   A(-1,00; 0,00) ────────── B(1,00; 0,00)
    /// ```
    ///
    /// Điểm chạm ở `(0,00; −0,30)`: ngay dưới điểm giữa cạnh A–B.
    ///
    /// * Tới ĐOẠN A–B: **300 mm** — đáp án đúng.
    /// * Tới ĐỈNH gần nhất (C): **921,95 mm** — sai gấp ba, và vẫn là một con số
    ///   trông hợp lý cho một mép bàn.
    test('đo tới ĐOẠN biên gần nhất, không tới ĐỈNH gần nhất', () {
      expect(
        _mm(ketQua, 'canhDai'),
        closeTo(300, 0.5),
        reason:
            'Đỉnh của `boundaryVertices` chỉ là điểm mẫu rải dọc biên, không '
            'phải góc của một đa giác đều. Đo tới đỉnh gần nhất ở đây cho '
            '921,95 mm thay vì 300 mm — một con số vẫn dương, vẫn hữu hạn, vẫn '
            'đúng hàng milimét, và sai gấp ba. Đúng dạng hỏng mà cả cái van này '
            'sinh ra để chặn.',
      );
    });

    /// Cùng biên ấy, điểm nằm ngoài giữa một cạnh XIÊN.
    ///
    /// Điểm chạm ở `(0,70; 0,70)`, cạnh gần nhất là B–C (xiên, không song song
    /// trục nào).
    ///
    /// * Tới ĐOẠN B–C: **380 mm**.
    /// * Tới ĐỈNH gần nhất (C): **509,90 mm**.
    ///
    /// Cạnh xiên có mặt vì một cách tính sai THỨ BA cũng qua được ca trên: lấy
    /// khoảng cách tới hình chữ nhật bao biên. Với cạnh song song trục thì nó
    /// trùng đáp án đúng; với cạnh xiên thì không.
    test('cạnh XIÊN cũng đo tới đoạn, không rơi về hình chữ nhật bao', () {
      expect(
        _mm(ketQua, 'canhXien'),
        closeTo(380, 0.5),
        reason:
            'Hình chữ nhật bao biên (`ARPlaneAnchor.extent`) là thứ có sẵn và '
            'rẻ hơn hẳn đa giác. Nó đúng ở cạnh song song trục và sai ở mọi '
            'cạnh xiên — mà mặt bàn thật ARKit dò ra thì gần như không có cạnh '
            'nào song song trục.',
      );
    });

    /// Cùng MỘT điểm chạm và cùng MỘT biên, đặt trên hai mặt phẳng ở hai chỗ
    /// khác nhau trong thế giới.
    ///
    /// Quãng vượt biên là một tính chất của hình học TRONG mặt phẳng, nên nó
    /// phải cho ra cùng một con số. Quên chuyển hệ toạ độ thì hai con số ấy
    /// khác nhau đúng bằng quãng dời giữa hai mặt phẳng.
    test('quãng vượt biên KHÔNG đổi theo chỗ mặt phẳng nằm trong thế giới', () {
      final xa = _mm(ketQua, 'canhDaiDoiCho');

      expect(
        xa,
        closeTo(300, 0.5),
        reason:
            '`boundaryVertices` nằm trong hệ toạ độ CỦA MẶT PHẲNG, điểm chạm '
            'nằm trong hệ THẾ GIỚI. So thẳng hai thứ ấy là cộng cả quãng dời '
            'của mặt phẳng vào quãng vượt biên: cùng một mép bàn báo 300 mm ở '
            'chỗ này và hàng mét ở chỗ kia, tuỳ ARKit đặt gốc thế giới ở đâu — '
            'và gốc thế giới thì đặt ở chỗ máy đang đứng lúc mở app.',
      );
      expect(
        xa,
        closeTo(_mm(ketQua, 'canhDai'), 0.5),
        reason:
            'Hai mặt phẳng khác chỗ, khác hướng, cùng hình biên, cùng điểm chạm '
            'trong hệ của chúng — một phép biến đổi cứng không đổi khoảng cách, '
            'nên hai con số phải bằng nhau.',
      );
    });

    // Biên dưới ba đỉnh không phải một đa giác. Trả một con số ở đó là bịa ra
    // một cái van: app sẽ nới dung sai theo một quãng đo tới một thứ không có
    // biên. `nil` đọc đúng nghĩa "không nói được", và tầng gọi đã có sẵn đường
    // xử lý nó — nó BỎ luôn lượt trúng ngoại suy ấy.
    test('biên dưới ba đỉnh trả nil, không trả một con số bịa', () {
      expect(ketQua['bienRong'], 'nil');
      expect(ketQua['bienHaiDinh'], 'nil');
    });

    // Một đỉnh NaN lọt vào (một khung hình hỏng, một bản iOS sau) thì kết quả
    // là NaN. NaN đi tiếp lên kênh thành `double.nan` bên Dart, so sánh nào với
    // nó cũng false, và một ngưỡng "vượt quá 50 mm thì cảnh báo" im lặng không
    // bao giờ đúng. Chặn tại chỗ sinh ra nó.
    test('đỉnh không hữu hạn trả nil, không trả NaN', () {
      expect(ketQua['bienNaN'], 'nil');
    });
  });
}

double _mm(Map<String, String> ketQua, String ten) {
  final raw = ketQua[ten];
  expect(
    raw,
    isNotNull,
    reason: 'chương trình Swift không in ra ca `$ten`',
  );
  final value = double.tryParse(raw!);
  expect(
    value,
    isNotNull,
    reason: 'ca `$ten` trả `$raw`, không phải một con số',
  );
  return value!;
}

/// Dịch và chạy [PlaneOvershoot] thật, trả về map `tên ca` → `chuỗi in ra`.
///
/// Dịch bằng `swiftc` nhắm macOS, không nhắm iOS: tệp hình học cố ý không nhập
/// `ARKit`, nên nó chạy được ngay trên máy đang dịch. Đó là toàn bộ lý do nó
/// nằm tách khỏi `ArMeasureSession.swift`.
///
/// **Không có nhánh "bỏ qua khi thiếu swiftc".** Gói này chỉ có nền tảng iOS,
/// nên máy nào dựng được nó cũng có Xcode; một ca kiểm tự bỏ qua ở đây sẽ XANH
/// trên đúng cái máy không kiểm được gì.
Map<String, String> _chayHinhHocSwift() {
  final geometry = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/PlaneOvershoot.swift',
  );
  expect(
    geometry.existsSync(),
    isTrue,
    reason:
        'không tìm thấy ${geometry.path} — phép tính quãng vượt biên phải nằm '
        'ở một tệp KHÔNG nhập ARKit, nếu không thì không ca kiểm nào chạy nổi '
        'nó ngoài một máy iOS thật.',
  );

  final temp = Directory.systemTemp.createTempSync('plane_overshoot_test');
  addTearDown(() => temp.deleteSync(recursive: true));

  final harness = File('${temp.path}/main.swift')..writeAsStringSync(_harness);
  final binary = '${temp.path}/plane_overshoot';

  final built = Process.runSync('swiftc', [
    '-O',
    geometry.absolute.path,
    harness.path,
    '-o',
    binary,
  ]);
  expect(
    built.exitCode,
    0,
    reason:
        'swiftc không dịch được phần hình học:\n${built.stderr}\n'
        'Nếu lỗi là "cannot find type in scope" thì tệp hình học đã nhập một '
        'khung của iOS — nó phải chỉ nhập Foundation và simd.',
  );

  final ran = Process.runSync(binary, const []);
  expect(ran.exitCode, 0, reason: 'chương trình hình học chạy hỏng:\n${ran.stderr}');

  final ketQua = <String, String>{};
  for (final line in const LineSplitter().convert(ran.stdout as String)) {
    final i = line.indexOf('=');
    if (i > 0) ketQua[line.substring(0, i)] = line.substring(i + 1);
  }
  expect(ketQua, isNotEmpty, reason: 'chương trình hình học không in ra gì');
  return ketQua;
}

/// Chương trình Swift dựng các ca hình học rồi in kết quả.
///
/// Toạ độ và đáp án mong đợi nằm CẠNH NHAU trong tệp này — số liệu ở đây, con
/// số mong đợi ở phần `test` phía trên. Tách chúng ra hai tệp là mở đúng chỗ
/// cho một ca kiểm mù: ai đó sửa hình mà quên sửa đáp án, và ca vẫn xanh vì
/// đáp án cũ tình cờ vẫn khớp một hình mới.
///
/// Mỗi ca dựng điểm chạm bằng cách lấy toạ độ TRONG hệ mặt phẳng rồi đẩy ra hệ
/// thế giới bằng chính ma trận sẽ truyền vào. Nhờ vậy đáp án đúng tính được
/// bằng tay từ hình phẳng, và nó không đổi khi ma trận đổi.
const String _harness = r'''
import Foundation
import simd

/// Một phép biến đổi CỨNG: xoay quanh một trục rồi dời.
func rigid(axis: SIMD3<Float>, degrees: Float, translation: SIMD3<Float>)
  -> simd_float4x4
{
  let q = simd_quatf(angle: degrees * .pi / 180, axis: simd_normalize(axis))
  var m = simd_float4x4(q)
  m.columns.3 = SIMD4<Float>(translation, 1)
  return m
}

/// Điểm nằm trong mặt phẳng (y = 0), đẩy ra hệ thế giới.
func world(_ x: Float, _ z: Float, _ m: simd_float4x4) -> SIMD3<Float> {
  let v = m * SIMD4<Float>(x, 0, z, 1)
  return SIMD3<Float>(v.x, v.y, v.z)
}

func report(_ name: String, _ mm: Double?) {
  print("\(name)=\(mm.map { String($0) } ?? "nil")")
}

/// Biên LỆCH có chủ đích: một cạnh dài song song trục, một cạnh xiên, và không
/// một trục đối xứng nào. Biên đối xứng làm mọi ca dưới đây mù.
let bien: [SIMD3<Float>] = [
  SIMD3<Float>(-1.00, 0, 0.00),
  SIMD3<Float>(1.00, 0, 0.00),
  SIMD3<Float>(0.20, 0, 0.60),
  SIMD3<Float>(-0.40, 0, 0.55),
]

// Mặt bàn ngang, xoay 30° quanh trục dựng, đặt cách gốc thế giới vài mét.
let matBan = rigid(
  axis: SIMD3<Float>(0, 1, 0), degrees: 30,
  translation: SIMD3<Float>(2.5, 1.2, -0.7))

// Cùng hình biên ấy trên một mặt ĐỨNG, ở một chỗ khác hẳn trong thế giới.
let matTuong = rigid(
  axis: simd_normalize(SIMD3<Float>(1, 0.4, 0.2)), degrees: 105,
  translation: SIMD3<Float>(-1.75, 0.9, 3.2))

report(
  "canhDai",
  PlaneOvershoot.millimetres(
    worldPoint: world(0.00, -0.30, matBan),
    planeTransform: matBan,
    boundaryVertices: bien))

report(
  "canhXien",
  PlaneOvershoot.millimetres(
    worldPoint: world(0.70, 0.70, matBan),
    planeTransform: matBan,
    boundaryVertices: bien))

report(
  "canhDaiDoiCho",
  PlaneOvershoot.millimetres(
    worldPoint: world(0.00, -0.30, matTuong),
    planeTransform: matTuong,
    boundaryVertices: bien))

report(
  "bienRong",
  PlaneOvershoot.millimetres(
    worldPoint: world(0.00, -0.30, matBan),
    planeTransform: matBan,
    boundaryVertices: []))

report(
  "bienHaiDinh",
  PlaneOvershoot.millimetres(
    worldPoint: world(0.00, -0.30, matBan),
    planeTransform: matBan,
    boundaryVertices: Array(bien.prefix(2))))

report(
  "bienNaN",
  PlaneOvershoot.millimetres(
    worldPoint: world(0.00, -0.30, matBan),
    planeTransform: matBan,
    boundaryVertices: bien + [SIMD3<Float>(.nan, 0, .nan)]))
''';
