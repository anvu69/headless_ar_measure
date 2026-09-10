import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ca kiểm SỐ của phép chọn khuôn hình — chạy phép chọn Swift thật, không đọc chữ.
///
/// Cùng lối với `plane_overshoot_test.dart`, và vì cùng một lẽ: hai tiêu chí
/// đối nghịch nhau ("nhiều điểm ảnh nhất" và "nhịp khung cao nhất") để lại một
/// tệp Swift trông hoàn toàn hợp lý, cùng một tên hàm, cùng một danh sách vào,
/// và cả hai đều trả về một khuôn hình có thật của máy. Thứ phân biệt chúng là
/// KHUÔN NÀO ĐƯỢC CHỌN, nên ca kiểm phải chạy phép chọn.
///
/// Chạy được là nhờ [VideoFormatChoice] cố ý nằm ở một tệp RIÊNG chỉ nhập
/// `Foundation` — không `ARKit`. `ARVideoFormat` không dựng được bằng tay và
/// `supportedVideoFormats` là danh sách của máy đang chạy, nên một phép chọn
/// viết thẳng trên `ARVideoFormat` chỉ kiểm được bằng cách cầm đúng cái máy có
/// đúng danh sách ấy. Rút ba con số ra khỏi khung của Apple là thứ biến nó
/// thành một hàm kiểm được.
///
/// **Mọi ca dưới đây có ít nhất HAI khuôn.** Một danh sách một khuôn cho cùng
/// một đáp án dưới mọi tiêu chí, nên nó không nói được tiêu chí nào đang chạy —
/// nó xanh y hệt trên bản trước lẫn bản này.
void main() {
  group('VideoFormatChoice · khuôn hình được chọn', () {
    late Map<String, String> ketQua;

    setUpAll(() {
      ketQua = _chayPhepChonSwift();
    });

    /// Đây là ca của lượt 0.9.0, và nó ĐỎ trên tiêu chí cũ.
    ///
    /// Tiêu chí cũ ("nhiều điểm ảnh nhất") chọn 3840×2160@30. Tiêu chí mới chọn
    /// 1920×1080@60. Hai khuôn, hai đáp án khác nhau, không có cách nào nhầm.
    test('nhịp khung thắng điểm ảnh: 4K@30 thua 1080p@60', () {
      expect(
        _chon(ketQua, 'nhipThangDiemAnh'),
        1,
        reason:
            'Khuôn 4K@30 có nhiều gấp bốn số điểm ảnh, và nó vẫn phải thua. '
            'Đoạn thẳng sống vẽ trong SceneKit chỉ mượt được bằng nhịp khung: '
            '30 khung/s là 33 ms mỗi bước nhảy, và người cầm máy gọi nó là giật.',
      );
    });

    /// Cùng hai khuôn ấy, đảo thứ tự trong danh sách.
    ///
    /// Có mặt vì hai cách hỏng tầm thường qua được ca trên mà không ai thấy:
    /// "luôn trả về phần tử đầu" và "luôn trả về phần tử cuối". Cả hai đều là
    /// một con số chỉ số hợp lệ, và cả hai đều trỏ vào một khuôn có thật.
    test('không phải "lấy phần tử đầu" hay "lấy phần tử cuối"', () {
      expect(
        _chon(ketQua, 'nhipThangDiemAnhDaoThuTu'),
        0,
        reason:
            'Cùng hai khuôn của ca trên, đảo chỗ. Đáp án phải đảo theo. Một '
            'phép chọn trả về chỉ số cố định xanh ở đúng một trong hai ca này.',
      );
    });

    /// Ca ngược: tiêu chí mới KHÔNG bỏ điểm ảnh, nó chỉ xếp sau nhịp khung.
    test('cùng nhịp thì lấy khuôn nhiều điểm ảnh hơn', () {
      expect(
        _chon(ketQua, 'cungNhipLayNhieuDiemAnh'),
        1,
        reason:
            'Hai khuôn cùng 60 khung/s cho SceneKit cùng một độ mượt, nên thứ '
            'còn lại phân biệt chúng là lượng thông tin mỗi ảnh. Bỏ nấc này là '
            'chọn 1280×720 trên một máy có 1920×1440 cùng nhịp — mất điểm ảnh '
            'mà không đổi được gì.',
      );
    });

    test('nấc điểm ảnh cũng không phải "lấy phần tử đầu/cuối"', () {
      expect(_chon(ketQua, 'cungNhipLayNhieuDiemAnhDaoThuTu'), 0);
    });

    /// Nấc thứ hai đo DIỆN TÍCH, không đo bề ngang.
    ///
    /// `3840×640` không phải khuôn của máy nào — nó ở đây vì một phép "rút gọn"
    /// rất dễ viết: so `imageResolution.width` cho nhanh, hai khuôn thật của
    /// một máy hầu như luôn cùng tỉ lệ nên bề ngang xếp đúng thứ tự với diện
    /// tích. Cho tới cái ngày nó không.
    test('nấc thứ hai đo diện tích, không đo bề ngang', () {
      expect(
        _chon(ketQua, 'dienTichKhongPhaiBeRong'),
        0,
        reason:
            '1920×1440 là 2 764 800 điểm ảnh; 3840×640 là 2 457 600. So bề '
            'ngang thì 3840 thắng, so diện tích thì 1920×1440 thắng. Chỉ một '
            'trong hai là "nhiều điểm ảnh hơn".',
      );
    });

    /// Danh sách máy iPad Air M3 quan sát được, ba khuôn.
    ///
    /// Đây là ĐỐI CHỨNG của lượt này: cùng bản dựng, iPad chọn 1920×1440@60 và
    /// người dùng không báo giật; iPhone chọn 3840×2160@30 và báo giật. Không
    /// phải một thí nghiệm sạch — hai máy khác nhau ở nhiều thứ — nhưng danh
    /// sách khuôn của nó là dữ kiện, và tiêu chí mới phải chọn ra đúng cái mà
    /// máy ấy đang chạy.
    test('ba khuôn: 60 khung/s to nhất, không phải 4K@30', () {
      expect(_chon(ketQua, 'baKhuon'), 1);
    });

    /// Danh sách RỖNG là một khả năng thật: máy ảo, hay một bản iOS sau không
    /// khai khuôn nào. Ở đó phép chọn phải nói "không có gì" để người gọi giữ
    /// nguyên mặc định của Apple — chứ không phải sập, và cũng không phải trả
    /// một chỉ số 0 trỏ vào hư không.
    test('danh sách rỗng trả nil, không trả một chỉ số bịa', () {
      expect(ketQua['danhSachRong'], 'nil');
    });

    /// Hai khuôn giống hệt nhau về cả ba con số.
    ///
    /// Không có đáp án "đúng" nào ở đây, chỉ có một đòi hỏi: cùng một danh sách
    /// phải cho cùng một khuôn ở mọi lượt chạy. Một phép chọn không xác định
    /// làm mọi ca ở trên thành ca thi thoảng đỏ.
    test('hoà tuyệt đối thì lấy khuôn đầu, và lấy một cách xác định', () {
      expect(_chon(ketQua, 'hoaTuyetDoi'), 0);
    });
  });
}

/// Đọc chỉ số khuôn được chọn ở ca [name].
int _chon(Map<String, String> ketQua, String name) {
  final value = ketQua[name];
  expect(
    value,
    isNotNull,
    reason:
        'chương trình Swift không in ra ca "$name" — nó đã đổi tên ca hoặc '
        'chết giữa chừng',
  );
  expect(
    value,
    isNot('nil'),
    reason: 'ca "$name" có khuôn để chọn, mà phép chọn trả về nil',
  );
  return int.parse(value!);
}

/// Dịch và chạy [VideoFormatChoice] thật, trả về map `tên ca` → `chuỗi in ra`.
///
/// Dịch bằng `swiftc` nhắm macOS, không nhắm iOS: tệp phép chọn cố ý không nhập
/// `ARKit`, nên nó chạy được ngay trên máy đang dịch. Đó là toàn bộ lý do nó
/// nằm tách khỏi `ArMeasureSession.swift`.
///
/// **Không có nhánh "bỏ qua khi thiếu swiftc"**, cùng lẽ với ca kiểm hình học:
/// gói này chỉ có nền tảng iOS, nên máy nào dựng được nó cũng có Xcode; một ca
/// kiểm tự bỏ qua ở đây sẽ XANH trên đúng cái máy không kiểm được gì.
Map<String, String> _chayPhepChonSwift() {
  final choice = File(
    'ios/headless_ar_measure/Sources/headless_ar_measure/VideoFormatChoice.swift',
  );
  expect(
    choice.existsSync(),
    isTrue,
    reason:
        'không tìm thấy ${choice.path} — phép chọn khuôn hình phải nằm ở một '
        'tệp KHÔNG nhập ARKit, nếu không thì không ca kiểm nào chạy nổi nó '
        'ngoài một máy iOS có đúng danh sách khuôn cần thử.',
  );

  final temp = Directory.systemTemp.createTempSync('video_format_choice_test');
  addTearDown(() => temp.deleteSync(recursive: true));

  final harness = File('${temp.path}/main.swift')..writeAsStringSync(_harness);
  final binary = '${temp.path}/video_format_choice';

  final built = Process.runSync('swiftc', [
    '-O',
    choice.absolute.path,
    harness.path,
    '-o',
    binary,
  ]);
  expect(
    built.exitCode,
    0,
    reason:
        'swiftc không dịch được phép chọn khuôn hình:\n${built.stderr}\n'
        'Nếu lỗi là "cannot find type in scope" thì tệp ấy đã nhập một khung '
        'của iOS — nó phải chỉ nhập Foundation.',
  );

  final ran = Process.runSync(binary, const []);
  expect(
    ran.exitCode,
    0,
    reason: 'chương trình chọn khuôn chạy hỏng:\n${ran.stderr}',
  );

  final ketQua = <String, String>{};
  for (final line in const LineSplitter().convert(ran.stdout as String)) {
    final i = line.indexOf('=');
    if (i > 0) ketQua[line.substring(0, i)] = line.substring(i + 1);
  }
  expect(ketQua, isNotEmpty, reason: 'chương trình chọn khuôn không in ra gì');
  return ketQua;
}

/// Chương trình Swift dựng các danh sách khuôn giả rồi in chỉ số được chọn.
///
/// Danh sách và đáp án mong đợi nằm CẠNH NHAU giữa tệp này và phần `test` phía
/// trên. Tách chúng xa nhau là mở đúng chỗ cho một ca kiểm mù: ai đó sửa danh
/// sách mà quên sửa đáp án, và ca vẫn xanh vì chỉ số cũ tình cờ vẫn trỏ vào một
/// khuôn nào đó.
const String _harness = r'''
import Foundation

func report(_ name: String, _ formats: [VideoFormatCandidate]) {
  let pick = VideoFormatChoice.indexOfBest(among: formats)
  print("\(name)=\(pick.map(String.init) ?? "nil")")
}

func f(_ w: Int, _ h: Int, _ fps: Int) -> VideoFormatCandidate {
  VideoFormatCandidate(width: w, height: h, fps: fps)
}

// 4K@30 có nhiều gấp bốn điểm ảnh và vẫn phải thua 1080p@60.
report("nhipThangDiemAnh", [f(3840, 2160, 30), f(1920, 1080, 60)])
report("nhipThangDiemAnhDaoThuTu", [f(1920, 1080, 60), f(3840, 2160, 30)])

// Cùng nhịp thì nấc thứ hai — điểm ảnh — quyết định.
report("cungNhipLayNhieuDiemAnh", [f(1280, 720, 60), f(1920, 1440, 60)])
report("cungNhipLayNhieuDiemAnhDaoThuTu", [f(1920, 1440, 60), f(1280, 720, 60)])

// 1920×1440 = 2_764_800 điểm ảnh; 3840×640 = 2_457_600. So bề ngang thì thứ tự
// ĐẢO. Không máy nào khai 3840×640 — nó ở đây để chặn một phép rút gọn.
report("dienTichKhongPhaiBeRong", [f(1920, 1440, 60), f(3840, 640, 60)])

// Danh sách quan sát được trên iPad Air M3.
report("baKhuon", [f(3840, 2160, 30), f(1920, 1440, 60), f(1280, 720, 60)])

report("danhSachRong", [])

report("hoaTuyetDoi", [f(1920, 1440, 60), f(1920, 1440, 60)])
''';
