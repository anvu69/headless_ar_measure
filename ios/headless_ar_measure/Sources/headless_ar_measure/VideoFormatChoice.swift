import Foundation

/// Một khuôn hình ứng cử, rút xuống đúng ba con số phép chọn nhìn vào.
///
/// Không phải `ARVideoFormat`, và đó là chủ ý: `ARVideoFormat` không dựng được
/// bằng tay, còn `ARWorldTrackingConfiguration.supportedVideoFormats` là danh
/// sách của CÁI MÁY ĐANG CHẠY. Một phép chọn viết thẳng trên `ARVideoFormat`
/// chỉ kiểm được bằng cách cầm đúng cái máy có đúng danh sách cần thử — tức là
/// không kiểm được. Ba con số này là thứ biến nó thành một hàm có ca kiểm.
struct VideoFormatCandidate {
  /// `ARVideoFormat.imageResolution`, tính bằng điểm ảnh.
  let width: Int
  let height: Int

  /// `ARVideoFormat.framesPerSecond` — nhịp **danh định** của khuôn.
  ///
  /// Không phải nhịp giao được thật. Máy nóng hay cảnh nặng làm nhịp thật tụt
  /// xuống dưới con số này, và không có gì ở tầng này biết chuyện đó. Xem
  /// CHANGELOG 0.9.0: đo nhịp thật là đếm khung, và gói không đếm.
  let fps: Int
}

/// Chọn khuôn hình cho phiên: **nhịp khung cao nhất trước, rồi mới tới điểm ảnh.**
///
/// **Đây là lượt LẬT tiêu chí của 0.4.0**, vốn xếp ngược lại — nhiều điểm ảnh
/// nhất trước, hoà điểm ảnh thì lấy nhịp cao hơn. Đọc CHANGELOG 0.4.0, 0.4.1 và
/// 0.9.0 trước khi đổi lại, vì lịch sử ở đây dễ nhớ nhầm theo cả hai chiều:
///
/// * 0.4.0 tự ghi điều kiện hoàn nguyên của nó TRƯỚC khi có dữ liệu — *"nhịp
///   khung tụt mà thời gian chờ không giảm thì bỏ"*. Lượt máy thật cho nhịp tụt
///   còn 30 **nhưng quãng chờ co từ 130 s xuống 7,8 s**. Điều kiện ấy KHÔNG đạt,
///   nên lượt này **không phải** một lượt hoàn nguyên theo tiêu chí cũ.
/// * Nó đổi vì một triệu chứng MỚI, không nằm trong tiêu chí ấy: đoạn thẳng
///   **giật khi rê máy**. Đoạn thẳng vẽ trong SceneKit, nên nó chỉ mượt được
///   bằng nhịp khung — 30 khung/s là 33 ms mỗi bước nhảy.
///
/// Nấc thứ hai — điểm ảnh — vẫn còn, và nó không phải phần thừa: hai khuôn cùng
/// nhịp cho SceneKit cùng một độ mượt, nên thứ còn lại phân biệt chúng là lượng
/// thông tin mỗi ảnh mà ARKit rút điểm đặc trưng ra. Bỏ nấc ấy là chọn 1280×720
/// trên một máy có 1920×1440 cùng 60 khung/s — mất điểm ảnh mà không đổi được gì.
///
/// **Không có kết luận nào ở đây về phân giải.** Không ai đo được rằng phân
/// giải cao phản tác dụng; phép thử 0.4.0 vẫn chưa ngã ngũ vì nó lẫn biến với
/// lượt sửa tâm ngắm cùng bản dựng. Lượt này chỉ nói rằng khi hai thứ cãi nhau
/// thì **nhịp** được ưu tiên.
enum VideoFormatChoice {
  /// Chỉ số trong [candidates] của khuôn nên chạy, `nil` khi danh sách rỗng.
  ///
  /// **Trả về CHỈ SỐ, không trả về khuôn.** Người gọi cần chính đối tượng
  /// `ARVideoFormat` của Apple để gán vào `config.videoFormat`, và tra ngược từ
  /// ba con số là mở đúng chỗ cho một lỗi câm: hai mục cùng bề ngang, bề cao và
  /// nhịp là hai khuôn KHÁC nhau ở những thứ không nằm trong `struct` này. Chỉ
  /// số thì không nhập nhằng được.
  ///
  /// `nil` ở danh sách rỗng là một khả năng THẬT — máy ảo, hay một bản iOS sau
  /// không khai khuôn nào — và người gọi phải hiểu nó là *giữ nguyên mặc định
  /// của Apple*, chứ không phải một lỗi. Phòng hờ nằm trong chính kiểu trả về,
  /// không phải một nhánh riêng ai đó quên viết.
  ///
  /// Hoà tuyệt đối (cả ba con số bằng nhau) lấy khuôn ĐẦU, và lấy một cách xác
  /// định. Không có đáp án nào đúng hơn ở đó, nhưng một phép chọn đổi ý giữa
  /// hai lượt chạy biến mọi ca kiểm của nó thành ca thi thoảng đỏ.
  static func indexOfBest(among candidates: [VideoFormatCandidate]) -> Int? {
    var best: Int?

    for (index, candidate) in candidates.enumerated() {
      guard let current = best else {
        best = index
        continue
      }

      let incumbent = candidates[current]

      // Nấc 1: nhịp khung. So TRƯỚC, và một mình nó quyết định khi hai nhịp
      // khác nhau — kể cả khi khuôn chậm hơn có nhiều gấp bốn số điểm ảnh.
      if candidate.fps != incumbent.fps {
        if candidate.fps > incumbent.fps { best = index }
        continue
      }

      // Nấc 2: DIỆN TÍCH, không phải bề ngang. Hai khuôn thật của cùng một máy
      // hầu như luôn cùng tỉ lệ, nên bề ngang xếp đúng thứ tự với diện tích và
      // phép rút gọn ấy trông vô hại — cho tới cái ngày nó không.
      let incumbentPixels = incumbent.width * incumbent.height
      let candidatePixels = candidate.width * candidate.height
      if candidatePixels > incumbentPixels { best = index }
    }

    return best
  }
}
