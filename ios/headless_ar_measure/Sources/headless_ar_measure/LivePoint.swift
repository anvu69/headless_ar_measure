import Foundation
import simd

/// Đầu SỐNG của đoạn thẳng — kết quả tia tâm ngắm, lọc theo **thời gian**.
///
/// Đầu mút này là thứ duy nhất trong cả phép đo đổi ở MỖI khung hình: hai điểm
/// đã chấm nằm yên trong `ARAnchor`, còn nó là một lượt raycast mới, 60 lần mỗi
/// giây. Hai dạng nhiễu đi thẳng từ đó ra màn, và cả hai đều được người dùng
/// gọi tên trên máy thật — *"đoạn thẳng vẫn chưa mượt lắm. Đặc biệt ở đầu mút
/// có thể nhấp nháy liên tục"*:
///
/// * **Khung TRƯỢT xen kẽ.** Một khung không trúng gì thì đầu sống biến mất,
///   và cả đoạn thẳng ẩn đúng một khung rồi hiện lại. Ở 60 khung/s, một chuỗi
///   trúng-trượt xen kẽ không đọc ra "tia đang trượt"; nó đọc ra một cái nháy.
/// * **Đổi TẦNG giữa hai khung.** `raycastFromReticle` thử ba tầng theo thứ tự,
///   nên hai khung liên tiếp có thể trả về hai BỀ MẶT khác nhau — mặt phẳng đã
///   xác nhận ở khung này, mặt phẳng ARKit ước lượng ở khung sau. Điểm nhảy
///   hàng centimét, và cả hai khung đều báo "trúng".
///
/// **Chỗ này KHÔNG phải chỗ vẽ, và đó là điểm chính.** Lượt điều tra bắt đầu ở
/// giả thuyết ngược lại — rằng đường vẽ dựng lại node mỗi khung — và giả thuyết
/// ấy sai: `ArMeasureNodes` dựng đủ năm node một lần ở `init` rồi chỉ đổi
/// `simdPosition` và `isHidden`, còn `ArMeasureNodeSuppressor` trả `nil` cho
/// mọi anchor nên ARKit cũng không dựng node nào. Không có gì để sửa ở tầng vẽ;
/// thứ nháy là con số đi vào nó.
///
/// **Điều bộ lọc này KHÔNG đụng tới.** `placePoint()` bắn một tia MỚI và không
/// đọc đầu sống, nên độ trễ và quãng ôm dưới đây không đẩy điểm đã chấm đi đâu
/// cả — chúng chỉ đổi thứ được VẼ và con số đang trôi dưới nhãn. Lời hứa "bấm
/// bây giờ thì trúng" cũng không đi qua đây: nó đi trên `aimTarget`, và trường
/// ấy vẫn về `nil` ở lượt trượt như trước.
///
/// **Tệp riêng, và không nhập `ARKit`.** Cùng chủ ý với `PlaneOvershoot.swift`:
/// chỉ `Foundation` và `simd` thì phép lọc dịch và chạy được thẳng trên macOS,
/// nên nó có ca kiểm SỐ (`test/live_point_test.dart`) mà không cần một máy iOS
/// nào — và ca kiểm ấy đo cả CÁI GIÁ, không chỉ cái lợi.
struct LivePointFilter {
  /// Quãng ÔM một lượt trượt trước khi buông, giây.
  ///
  /// Hai đầu của lời đánh đổi này đều hỏng nhìn thấy được. Ngắn quá thì không
  /// nuốt nổi một khung trượt và cái nháy còn nguyên. Dài quá thì đoạn thẳng
  /// ĐỨNG YÊN giữa lúc người dùng vẫn đang rê máy — và một đoạn đứng yên đọc ra
  /// "đã chấm xong", đúng cái hiểu nhầm mà bản trước cố ý chọn xoá-ngay để
  /// tránh.
  ///
  /// 100 ms nằm giữa: sáu khung ở 60 Hz, quá ngắn để đọc ra một đoạn bị đóng
  /// băng, quá dài để một chuỗi trượt lẻ tẻ lọt qua. Nó KHÔNG phủ được một quãng
  /// `needsMotion` nửa giây, và đó là chủ ý — ở đó tia trượt thật, kéo dài, và
  /// đoạn thẳng nên biến mất.
  static let holdSeconds: TimeInterval = 0.10

  /// Hằng số thời gian của phép làm mượt, giây.
  ///
  /// Cái giá của nó là ĐỘ TRỄ, và độ trễ ấy tính được chứ không phải cảm giác:
  /// rê máy đều với bước `d` mỗi khung thì trạng thái dừng tụt sau mẫu đúng
  /// `d·(1−α)/α` với `α = 1 − e^(−dt/τ)`. Ở 60 khung/s, bước 8 mm (≈ 0,48 m/s),
  /// τ = 0,03 s: **10,8 mm**. Cùng bộ số ấy nén nhiễu xen kẽ 20 mm đỉnh-đỉnh
  /// xuống **5,4 mm**.
  ///
  /// Ca kiểm số ghim CẢ HAI con số, nên nâng τ là thấy ngay mình vừa mua cái gì
  /// bằng cái gì: τ = 0,06 s cho ra độ trễ 23 mm, và ở đó đoạn thẳng đọc ra như
  /// một sợi dây bị kéo lê sau tâm ngắm.
  ///
  /// **Chưa nghiệm thu trên máy.** Hai con số trên là phép tính, không phải một
  /// lượt cầm máy.
  static let smoothingSeconds: TimeInterval = 0.03

  /// Điểm ĐANG vẽ. `nil` là không có đầu sống nào.
  private(set) var point: SIMD3<Float>?

  /// Lúc có lượt TRÚNG gần nhất — mốc của quãng ôm.
  private var lastHitAt: TimeInterval?

  /// Lúc [point] được cập nhật gần nhất — mẫu số của `dt` trong phép làm mượt.
  ///
  /// Tách khỏi [lastHitAt] vì một lượt ôm KHÔNG cập nhật điểm: sau quãng hở,
  /// `dt` phải là quãng thật kể từ lần điểm đổi, nếu không thì lượt trúng đầu
  /// tiên sau đó bị làm mượt bằng một `dt` bé xíu và đầu mút bò về chỗ mới
  /// thay vì nhảy.
  private var lastStepAt: TimeInterval?

  /// Nhận một lượt TRÚNG. Trả về điểm đã lọc.
  ///
  /// Mẫu không hữu hạn coi như một lượt TRƯỢT, và đây là lời chặn duy nhất giữ
  /// NaN ra khỏi trạng thái: một NaN cộng vào trạng thái mũ thì cả trạng thái
  /// thành NaN vĩnh viễn, và một node có transform NaN thì SceneKit bỏ vẽ — im
  /// lặng, không lỗi nào nổ. Đoạn thẳng biến mất và không bao giờ trở lại.
  @discardableResult
  mutating func hit(_ sample: SIMD3<Float>, at now: TimeInterval) -> SIMD3<Float>? {
    guard sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else {
      return miss(at: now)
    }

    defer {
      lastHitAt = now
      lastStepAt = now
    }

    // Chưa có gì thì mẫu này là sự thật DUY NHẤT đang có. Trộn nó với một
    // trạng thái chưa tồn tại là bịa ra một điểm — và một bộ lọc khởi tạo ở gốc
    // toạ độ sẽ vẽ đoạn thẳng đầu tiên phóng ra từ chỗ người dùng đứng lúc mở
    // app rồi bò về chỗ đúng.
    guard let previous = point else {
      point = sample
      return sample
    }

    // `dt` ÂM bị ghim về 0, không để nó chạy tiếp: `α` âm kéo điểm ra NGƯỢC
    // phía mẫu mới, nên đầu mút bay xa dần mỗi khung và không có gì trong toạ
    // độ nói ra vì sao.
    let dt = max(0, now - (lastStepAt ?? now))
    let alpha = Self.blend(dt: dt)
    point = previous + (sample - previous) * alpha
    return point
  }

  /// Nhận một lượt TRƯỢT. Trả về điểm đang ôm, hoặc `nil` khi đã hết hạn ôm.
  @discardableResult
  mutating func miss(at now: TimeInterval) -> SIMD3<Float>? {
    guard let lastHitAt, now - lastHitAt <= Self.holdSeconds else {
      clear()
      return nil
    }
    return point
  }

  /// Buông NGAY, không đi qua quãng ôm.
  ///
  /// Dành cho những lượt mà điểm cũ không còn nghĩa gì chứ không phải "chưa dò
  /// lại được": `reset()` dựng lại cả hệ toạ độ, nên điểm của lượt dò trước nằm
  /// trong hệ CŨ. Ôm nó thêm 100 ms ở đó là vẽ tới một toạ độ thuộc về một thế
  /// giới không còn nữa — và chỗ ấy trông hoàn toàn bình thường.
  mutating func clear() {
    point = nil
    lastHitAt = nil
    lastStepAt = nil
  }

  /// `α` của một bước dài `dt`: `1 − e^(−dt/τ)`.
  ///
  /// Viết theo hàm mũ chứ không phải một hằng số `α` cố định, vì `dt` KHÔNG cố
  /// định: nhịp khung tụt khi máy nóng, và một `α` ghim theo 60 Hz thì ở 30 Hz
  /// làm mượt gấp đôi mức đã chọn — đoạn thẳng ì hẳn đi đúng lúc máy đã chậm.
  private static func blend(dt: TimeInterval) -> Float {
    guard smoothingSeconds > 0 else { return 1 }
    guard dt > 0 else { return 0 }
    return Float(1 - exp(-dt / smoothingSeconds))
  }
}
