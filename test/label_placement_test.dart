import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ca kiểm SỐ của chỗ đứng tấm ảnh dán trên đoạn — chạy phép tính Swift thật.
///
/// Cùng lối với `plane_overshoot_test.dart`, và cùng lý do: ba luật mà lượt này
/// thêm vào đều để lại một tệp Swift trông hoàn toàn hợp lý khi làm sai, và cả
/// ba vẫn trả về những con số hữu hạn, cỡ đúng hàng. Thứ phân biệt đúng với sai
/// là GIÁ TRỊ, nên ca kiểm phải chạy phép tính.
///
/// Chạy được là nhờ [LabelPlacement] cố ý nằm ở một tệp RIÊNG chỉ nhập
/// `Foundation` và `simd` — không `ARKit`, không `SceneKit`, không `UIKit`.
///
/// Ba lớp lỗi mà ca dưới đây phải bắt:
///
/// * **Phép lật KHÔNG có trễ**, hoặc dải trễ đặt sai phía. Một mốc lật đơn ở
///   đúng 90° thì tay rung quanh mốc ấy làm chữ NHẢY — kho `lobanar_app` đã trả
///   giá cho đúng cơ chế này một lần ở mặt số la bàn, và một lần nữa ở bản
///   Flutter của chính viên số này.
/// * **Luật cỡ quên mẫu số**, tức viên to dần theo khoảng cách thay vì giữ
///   nguyên cỡ trên màn. Nhìn một con số đơn lẻ thì không thấy gì sai: nó vẫn
///   là một quãng mét dương, cỡ đúng hàng.
/// * **Hệ trục dựng sai tay**, hoặc pháp tuyến quay lưng lại camera. Cả hai vẫn
///   cho một quaternion hợp lệ, và SceneKit vẫn vẽ — chỉ là vẽ mặt sau.
void main() {
  group('LabelPlacement · chỗ đứng của tấm ảnh dán', () {
    late Map<String, String> ketQua;

    setUpAll(() {
      ketQua = _chayHinhHocSwift();
    });

    // -----------------------------------------------------------------------
    // Luật cỡ
    // -----------------------------------------------------------------------

    /// Trong quãng `[0,30 m; 3,00 m]`, viên cao ĐÚNG cỡ danh định trên màn.
    ///
    /// **Quét cả quãng chứ không ghim một điểm.** `zoom` của mặt số đã dạy bài
    /// ấy một lần: ghim bất biến ở MỘT điểm của một tham số liên tục không phải
    /// là canh. Ở đây còn nặng hơn — một luật "cỡ thật cố định" (tức quên chia
    /// cho khoảng cách) vẫn đi qua một ca ghim đúng một khoảng cách.
    test('giữ NGUYÊN cỡ trên màn suốt quãng 0,30–3,00 m', () {
      for (final d in _trongQuang) {
        expect(
          _so(ketQua, 'screen_$d'),
          closeTo(_caoDanhDinh, 0.01),
          reason:
              'Ở $d m viên phải cao đúng $_caoDanhDinh pt trên màn. Lệch ở đây '
              'nghĩa là cỡ THẬT của node không tỉ lệ thuận với khoảng cách, và '
              'triệu chứng trên máy là con số nhỏ dần khi lùi ra.',
        );
      }
    });

    /// Quá `farClamp` thì viên THÔI to thêm trong không gian thật, nên nó bắt
    /// đầu nhỏ dần trên màn — đúng tỉ lệ `farClamp / d`.
    ///
    /// Vì sao có trần: cỡ thật tỉ lệ thuận với khoảng cách nghĩa là ở 10 m viên
    /// rộng hơn một mét. Nó chui qua tường, chui vào vật, và nó che đúng cái
    /// đoạn nó đang chú thích.
    test('quá 3 m thì nhỏ dần trên màn theo đúng tỉ lệ trần', () {
      expect(
        _so(ketQua, 'screen_6.0'),
        closeTo(_caoDanhDinh * 3.0 / 6.0, 0.01),
      );
      expect(
        _so(ketQua, 'screen_12.0'),
        closeTo(_caoDanhDinh * 3.0 / 12.0, 0.01),
      );
    });

    /// Dưới `nearClamp` thì viên thôi nhỏ thêm trong không gian thật, nên nó
    /// TO dần trên màn.
    ///
    /// Vì sao có sàn — và đây là vế dễ đọc ngược nhất: giữ cỡ màn không đổi thì
    /// ở cự ly rất gần viên che mất chính cái vật đang đo. Người ta tới gần để
    /// đo thứ NHỎ, nên một viên rộng 60 pt cố định nuốt trọn một khe 5 cm đang
    /// chiếm 60 pt trên màn. Sàn làm viên to lên trên màn khi tới quá gần, và
    /// đó là lời mời lùi lại — không phải một lỗi.
    test('dưới 0,30 m thì to dần trên màn theo đúng tỉ lệ sàn', () {
      expect(
        _so(ketQua, 'screen_0.15'),
        closeTo(_caoDanhDinh * 0.30 / 0.15, 0.01),
      );
    });

    /// Đầu vào rác không được đẻ ra một cỡ rác: `NaN` hay `inf` gán vào
    /// `simdScale` làm SceneKit bỏ vẽ cả node — im lặng, không lỗi nào nổ.
    test('đầu vào suy biến ra 0, không ra NaN hay vô cực', () {
      for (final ten in ['edge_ppmZero', 'edge_dZero', 'edge_dNaN']) {
        final v = _so(ketQua, ten);
        expect(v, 0, reason: '$ten phải ra 0 — xem chú thích của worldHeight');
      }
    });

    // -----------------------------------------------------------------------
    // Phép lật, và cái TRỄ của nó
    // -----------------------------------------------------------------------

    test('chữ nằm ngang thì không lật, chữ chúc ngược thì lật', () {
      expect(_co(ketQua, 'flip_0_from_false'), isFalse);
      expect(_co(ketQua, 'flip_170_from_false'), isTrue);
    });

    /// Dải trễ: ra khỏi mốc 90° **một quãng** mới lật, và về lại phải vượt
    /// ngược quãng ấy mới thôi lật.
    test('mốc lật có TRỄ, và dải trễ rộng đúng 2 lần hệ số', () {
      // Đang KHÔNG lật: phải vượt quá 90 + h mới lật.
      expect(_co(ketQua, 'flip_96_from_false'), isFalse);
      expect(_co(ketQua, 'flip_99_from_false'), isTrue);

      // Đang LẬT: phải tụt xuống dưới 90 − h mới thôi.
      expect(_co(ketQua, 'flip_84_from_true'), isTrue);
      expect(_co(ketQua, 'flip_81_from_true'), isFalse);
    });

    /// **Ca bắt lỗi thật của dải trễ.** Một mốc lật ĐƠN vẫn đi qua mọi ca
    /// "ngang thì không lật, dốc thì lật" ở trên; thứ nó không đi qua được là
    /// một lượt quét qua lại quanh mốc.
    ///
    /// Quét 0° → 180° → 0° theo bước 1°: một luật đúng cho đúng HAI lượt đổi
    /// (lật lúc đi lên, thôi lật lúc đi xuống). Một mốc đơn cho hai lượt đổi ở
    /// lượt quét thô này nhưng vỡ ở lượt quét rung ngay dưới.
    test('quét lên rồi xuống chỉ đổi đúng hai lần', () {
      expect(_so(ketQua, 'sweep_transitions'), 2);
    });

    /// Rung quanh đúng mốc 90°, biên độ 3° — nhỏ hơn dải trễ 8°.
    ///
    /// Đây là cái tay người cầm máy. Với dải trễ thì KHÔNG lượt lật nào; không
    /// có trễ thì nó lật mỗi bước, và trên màn là chữ NHẢY.
    test('rung ±3° quanh mốc thì KHÔNG lật lần nào', () {
      expect(_so(ketQua, 'jitter_transitions'), 0);
    });

    test('đoạn suy biến trên màn thì GIỮ NGUYÊN trạng thái đang có', () {
      expect(_co(ketQua, 'flip_degenerate_from_true'), isTrue);
      expect(_co(ketQua, 'flip_degenerate_from_false'), isFalse);
    });

    // -----------------------------------------------------------------------
    // Hệ trục
    // -----------------------------------------------------------------------

    /// Toạ độ của ca này cố ý **không trục nào song song với trục thế giới**,
    /// và camera không nằm trên mặt phẳng đối xứng nào của đoạn. Hình đối xứng
    /// cộng góc kiểm đối xứng bằng ca kiểm mù.
    test('trục X nằm dọc đoạn, pháp tuyến quay VỀ PHÍA camera', () {
      // X song song đoạn, cùng chiều.
      expect(_so(ketQua, 'basis_xDotU'), closeTo(1, 1e-5));
      // Z quay về phía camera, không quay lưng lại.
      expect(_so(ketQua, 'basis_zDotCam'), greaterThan(0));
      // Z vuông góc đoạn: mặt phẳng của viên CHỨA đoạn.
      expect(_so(ketQua, 'basis_zDotU'), closeTo(0, 1e-5));
    });

    test('ba trục trực chuẩn và thuận tay phải', () {
      expect(_so(ketQua, 'basis_xLen'), closeTo(1, 1e-5));
      expect(_so(ketQua, 'basis_yLen'), closeTo(1, 1e-5));
      expect(_so(ketQua, 'basis_zLen'), closeTo(1, 1e-5));
      expect(_so(ketQua, 'basis_xDotY'), closeTo(0, 1e-5));
      expect(_so(ketQua, 'basis_yDotZ'), closeTo(0, 1e-5));
      // y = z × x, tức det[x y z] = +1.
      expect(_so(ketQua, 'basis_det'), closeTo(1, 1e-5));
    });

    /// Lật là nửa vòng quanh PHÁP TUYẾN, không phải nửa vòng quanh đoạn.
    ///
    /// Hai phép ấy khác nhau ở đúng chỗ đắt nhất: quay quanh đoạn lật pháp
    /// tuyến ra sau, nên viên quay LƯNG về camera và trên màn nó biến mất (hoặc
    /// hiện ra ảnh gương, nếu vật liệu hai mặt). Quay quanh pháp tuyến thì mặt
    /// vẫn hướng về camera, chỉ chữ xoay ngược.
    test('lật giữ nguyên pháp tuyến, chỉ đảo X và Y', () {
      expect(_so(ketQua, 'flipbasis_xDotU'), closeTo(-1, 1e-5));
      expect(_so(ketQua, 'flipbasis_zSame'), closeTo(1, 1e-5));
      expect(_so(ketQua, 'flipbasis_yOpposite'), closeTo(-1, 1e-5));
      expect(_so(ketQua, 'flipbasis_det'), closeTo(1, 1e-5));
    });

    /// Camera nằm ĐÚNG trên đường thẳng chứa đoạn: phần vuông góc của véc-tơ
    /// tới camera bằng 0, và một phép chuẩn hoá thẳng tay cho ra NaN.
    ///
    /// Đây không phải một góc hiếm — nó là lúc người ta ngắm dọc theo chính cái
    /// cạnh đang đo. Một node có transform NaN thì SceneKit bỏ vẽ, im lặng.
    test('camera nằm trên trục đoạn vẫn ra hệ trục hợp lệ', () {
      expect(_so(ketQua, 'degen_xLen'), closeTo(1, 1e-5));
      expect(_so(ketQua, 'degen_yLen'), closeTo(1, 1e-5));
      expect(_so(ketQua, 'degen_zLen'), closeTo(1, 1e-5));
      expect(_so(ketQua, 'degen_zDotU'), closeTo(0, 1e-5));
      expect(_so(ketQua, 'degen_det'), closeTo(1, 1e-5));
    });

    test('đoạn dài 0 vẫn ra hệ trục hợp lệ', () {
      expect(_so(ketQua, 'zero_xLen'), closeTo(1, 1e-5));
      expect(_so(ketQua, 'zero_det'), closeTo(1, 1e-5));
    });

    /// Quaternion phải dựng ra ĐÚNG ba trục ấy.
    ///
    /// Tách khỏi ca trên vì nó bắt một lỗi khác hẳn: ba trục đúng mà phép đổi
    /// sang quaternion sai tay (hoặc chuyển vị ma trận) vẫn cho một quaternion
    /// chuẩn hoá, và node vẫn xoay — chỉ là xoay sang chỗ khác.
    test('quaternion dựng lại đúng ba trục đã tính', () {
      for (final t in ['qx', 'qy', 'qz']) {
        expect(
          _so(ketQua, 'quat_$t'),
          closeTo(1, 1e-4),
          reason: 'quaternion đưa trục $t đi chệch khỏi hệ trục đã tính',
        );
      }
    });
  });
}

/// Cỡ danh định của viên, point. Trùng với `pointHeight` trong chương trình.
const double _caoDanhDinh = 19;

/// Những khoảng cách nằm TRONG quãng giữ nguyên cỡ.
/// Viết đúng như `Double.description` của Swift in ra — chương trình dùng
/// chính chuỗi ấy làm khoá, nên `0.30` ở đây sẽ không khớp `0.3` ở kia.
const List<String> _trongQuang = ['0.3', '0.45', '0.8', '1.25', '2.1', '3.0'];

double _so(Map<String, String> r, String ten) {
  final raw = r[ten];
  expect(raw, isNotNull, reason: 'chương trình không in ra `$ten`');
  final v = double.tryParse(raw!);
  expect(v, isNotNull, reason: '`$ten` không đọc được thành số: $raw');
  expect(v!.isFinite, isTrue, reason: '`$ten` không hữu hạn: $raw');
  return v;
}

bool _co(Map<String, String> r, String ten) {
  final raw = r[ten];
  expect(raw, anyOf('true', 'false'), reason: '`$ten` không phải cờ: $raw');
  return raw == 'true';
}

/// Dịch và chạy tệp hình học Swift, trả về bảng `tên=giá trị`.
///
/// **Không có nhánh "bỏ qua khi thiếu swiftc"**, cùng lẽ với
/// `plane_overshoot_test.dart`: gói này chỉ có nền tảng iOS, nên máy nào dựng
/// được nó cũng có Xcode.
Map<String, String> _chayHinhHocSwift() {
  final geometry = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/LabelPlacement.swift',
  );
  expect(
    geometry.existsSync(),
    isTrue,
    reason:
        'không tìm thấy ${geometry.path} — phép đặt tấm ảnh phải nằm ở một tệp '
        'KHÔNG nhập ARKit/SceneKit, nếu không thì không ca kiểm nào chạy nổi nó '
        'ngoài một máy iOS thật.',
  );

  final temp = Directory.systemTemp.createTempSync('label_placement_test');
  addTearDown(() => temp.deleteSync(recursive: true));

  final harness = File('${temp.path}/main.swift')..writeAsStringSync(_harness);
  final binary = '${temp.path}/label_placement';

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
        'Nếu lỗi là "cannot find type in scope" thì tệp đã nhập một khung của '
        'iOS — nó phải chỉ nhập Foundation và simd.',
  );

  final ran = Process.runSync(binary, const []);
  expect(
    ran.exitCode,
    0,
    reason: 'chương trình hình học chạy hỏng:\n${ran.stderr}',
  );

  final ketQua = <String, String>{};
  for (final line in const LineSplitter().convert(ran.stdout as String)) {
    final i = line.indexOf('=');
    if (i > 0) ketQua[line.substring(0, i)] = line.substring(i + 1);
  }
  expect(ketQua, isNotEmpty, reason: 'chương trình hình học không in ra gì');
  return ketQua;
}

/// Góc dùng cho ca hệ trục, độ. Không phải bội của 90 — xem chú thích ca kiểm.
const double _gocLech = 37;

/// Chương trình Swift dựng các ca rồi in kết quả.
///
/// Toạ độ nằm ở đây, đáp án nằm ở phần `test` phía trên, và cả hai trong CÙNG
/// một tệp — tách ra hai tệp là mở chỗ cho một ca kiểm mù.
final String _harness =
    '''
import Foundation
import simd

func report(_ name: String, _ value: Double) {
  print("\\(name)=\\(value)")
}

func report(_ name: String, _ value: Bool) {
  print("\\(name)=\\(value)")
}

// ---------------------------------------------------------------------------
// Luật cỡ
//
// `pointsPerMetre` là số point trên màn mà một mét ở khoảng cách ấy chiếm. Nó
// tỉ lệ NGHỊCH với khoảng cách — đó là toàn bộ phép phối cảnh, và là thứ luật
// cỡ phải khử. Hằng `f` dưới đây là một thấu kính giả định: ở 1 m, một mét
// chiếm 800 pt.
// ---------------------------------------------------------------------------

let f = 800.0
let pointHeight = $_caoDanhDinh

func screenHeight(at d: Double) -> Double {
  let ppm = f / d
  let h = LabelPlacement.worldHeight(
    pointHeight: pointHeight, pointsPerMetre: ppm, distanceMetres: d)
  return h * ppm
}

for d in [${_trongQuang.join(', ')}, 6.0, 12.0, 0.15] {
  report("screen_\\(d)", screenHeight(at: d))
}

report(
  "edge_ppmZero",
  LabelPlacement.worldHeight(
    pointHeight: pointHeight, pointsPerMetre: 0, distanceMetres: 1))
report(
  "edge_dZero",
  LabelPlacement.worldHeight(
    pointHeight: pointHeight, pointsPerMetre: f, distanceMetres: 0))
report(
  "edge_dNaN",
  LabelPlacement.worldHeight(
    pointHeight: pointHeight, pointsPerMetre: f, distanceMetres: .nan))

// ---------------------------------------------------------------------------
// Phép lật
//
// Đầu vào là véc-tơ trục X của viên ĐÃ CHIẾU xuống màn — hệ point, y đi XUỐNG,
// cùng hệ với `SCNSceneRenderer.projectPoint`.
// ---------------------------------------------------------------------------

func delta(_ degrees: Double) -> SIMD2<Double> {
  let r = degrees * .pi / 180
  return SIMD2<Double>(cos(r), sin(r))
}

func flip(_ degrees: Double, from was: Bool) -> Bool {
  LabelPlacement.isFlipped(screenDelta: delta(degrees), wasFlipped: was)
}

for (deg, was) in [
  (0.0, false), (170.0, false), (96.0, false), (99.0, false),
  (84.0, true), (81.0, true),
] {
  report("flip_\\(Int(deg))_from_\\(was)", flip(deg, from: was))
}

report(
  "flip_degenerate_from_true",
  LabelPlacement.isFlipped(
    screenDelta: SIMD2<Double>(0, 0), wasFlipped: true))
report(
  "flip_degenerate_from_false",
  LabelPlacement.isFlipped(
    screenDelta: SIMD2<Double>(0, 0), wasFlipped: false))

// Quét 0 → 180 → 0, bước 1°: đếm số lượt ĐỔI trạng thái.
var state = false
var transitions = 0
var angles: [Double] = []
for i in 0...180 { angles.append(Double(i)) }
for i in stride(from: 179, through: 0, by: -1) { angles.append(Double(i)) }
for a in angles {
  let next = flip(a, from: state)
  if next != state { transitions += 1 }
  state = next
}
report("sweep_transitions", Double(transitions))

// Rung ±3° quanh đúng mốc 90°, hai trăm bước. Biên độ nhỏ hơn dải trễ.
state = false
transitions = 0
for i in 0..<200 {
  let a = 90 + 3 * sin(Double(i) * 0.7)
  let next = flip(a, from: state)
  if next != state { transitions += 1 }
  state = next
}
report("jitter_transitions", Double(transitions))

// ---------------------------------------------------------------------------
// Hệ trục
// ---------------------------------------------------------------------------

func det(_ b: LabelPlacement.Basis) -> Double {
  Double(simd_determinant(simd_float3x3(columns: (b.x, b.y, b.z))))
}

func emit(_ name: String, _ b: LabelPlacement.Basis, u: SIMD3<Float>, cam: SIMD3<Float>, mid: SIMD3<Float>) {
  report("\\(name)_xLen", Double(simd_length(b.x)))
  report("\\(name)_yLen", Double(simd_length(b.y)))
  report("\\(name)_zLen", Double(simd_length(b.z)))
  report("\\(name)_xDotY", Double(simd_dot(b.x, b.y)))
  report("\\(name)_yDotZ", Double(simd_dot(b.y, b.z)))
  report("\\(name)_xDotU", Double(simd_dot(b.x, u)))
  report("\\(name)_zDotU", Double(simd_dot(b.z, u)))
  report("\\(name)_zDotCam", Double(simd_dot(b.z, simd_normalize(cam - mid))))
  report("\\(name)_det", det(b))
}

// Đoạn KHÔNG song song trục nào, camera KHÔNG nằm trên mặt phẳng đối xứng nào.
let rad = $_gocLech * Float.pi / 180
let u = simd_normalize(SIMD3<Float>(cos(rad), 0.42, sin(rad) * 0.83))
let mid = SIMD3<Float>(0.31, -0.17, 1.07)
let cam = SIMD3<Float>(-0.62, 0.94, -0.35)
let segment = u * 1.37

let b = LabelPlacement.basis(segment: segment, toCamera: cam - mid, flipped: false)
emit("basis", b, u: u, cam: cam, mid: mid)

let bf = LabelPlacement.basis(segment: segment, toCamera: cam - mid, flipped: true)
report("flipbasis_xDotU", Double(simd_dot(bf.x, u)))
report("flipbasis_zSame", Double(simd_dot(bf.z, b.z)))
report("flipbasis_yOpposite", Double(simd_dot(bf.y, b.y)))
report("flipbasis_det", det(bf))

// Camera đúng trên đường thẳng chứa đoạn.
let bd = LabelPlacement.basis(segment: segment, toCamera: u * 2.4, flipped: false)
emit("degen", bd, u: u, cam: mid + u * 2.4, mid: mid)

let bz = LabelPlacement.basis(
  segment: SIMD3<Float>(0, 0, 0), toCamera: cam - mid, flipped: false)
report("zero_xLen", Double(simd_length(bz.x)))
report("zero_det", det(bz))

// Quaternion phải dựng lại đúng ba trục.
let q = LabelPlacement.orientation(b)
report("quat_qx", Double(simd_dot(q.act(SIMD3<Float>(1, 0, 0)), b.x)))
report("quat_qy", Double(simd_dot(q.act(SIMD3<Float>(0, 1, 0)), b.y)))
report("quat_qz", Double(simd_dot(q.act(SIMD3<Float>(0, 0, 1)), b.z)))
''';
