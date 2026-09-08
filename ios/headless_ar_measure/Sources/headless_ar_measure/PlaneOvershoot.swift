import Foundation
import simd

/// Quãng từ một điểm chạm tới **đa giác biên** của mặt phẳng đã sinh ra nó.
///
/// Đây là **cái van** của tầng tia thứ ba (`.existingPlaneInfinite`). Tầng ấy
/// kéo dài một mặt phẳng đã dò ra vượt khỏi biên thật của nó, nên nó luôn trả
/// về một điểm — kể cả khi điểm ấy nằm cách mép bàn thật hàng mét. Không có con
/// số này thì một cảnh hỏng như thế **im lặng**: tâm ngắm khoá chắc, số đo hiện
/// ra bình thường, và không có gì nói rằng cao độ vừa lấy là cao độ mặt bàn chứ
/// không phải mặt vật đang ngắm.
///
/// Có con số này thì cảnh ấy tự lộ: vài chục mm là mép bàn mà biên chưa mọc
/// tới, hàng trăm mm tới hàng mét là đúng cảnh hỏng. Gói KHÔNG quyết định
/// ngưỡng — nó trả sự thật, và ngưỡng là việc của app.
///
/// **Tệp riêng, và không nhập `ARKit`.** Đó là chủ ý, không phải chuyện xếp
/// tệp cho gọn: chỉ `Foundation` và `simd` thì phép tính này dịch và chạy được
/// thẳng trên macOS, nên nó có ca kiểm SỐ (`test/plane_overshoot_test.dart`)
/// mà không cần một máy iOS nào. Hai cách tính sai mà ca kiểm ấy chặn đều để
/// lại một tệp trông hợp lý và một con số milimét trông hợp lý — không ca kiểm
/// đọc-chữ nào phân biệt được chúng.
enum PlaneOvershoot {
  /// Quãng ngắn nhất từ [worldPoint] tới đa giác [boundaryVertices], milimét.
  ///
  /// `nil` khi không có gì để đo tới: biên dưới ba đỉnh (không phải một đa
  /// giác), hoặc kết quả không hữu hạn. Người gọi phải coi `nil` là **không có
  /// van** — và một lượt trúng ngoại suy không có van thì bỏ đi, đừng nhận.
  ///
  /// - Parameters:
  ///   - worldPoint: điểm chạm, hệ toạ độ **thế giới** của ARKit.
  ///   - planeTransform: `ARPlaneAnchor.transform` của đúng mặt phẳng ấy.
  ///   - boundaryVertices: `ARPlaneAnchor.geometry.boundaryVertices`, hệ toạ độ
  ///     **của mặt phẳng** (nằm trên mặt phẳng y = 0 trong hệ ấy).
  static func millimetres(
    worldPoint: SIMD3<Float>,
    planeTransform: simd_float4x4,
    boundaryVertices: [SIMD3<Float>]
  ) -> Double? {
    // Dưới ba đỉnh thì không có đa giác nào. Trả một con số ở đây là bịa ra một
    // cái van: app nới dung sai theo một quãng đo tới một thứ không có biên.
    guard boundaryVertices.count >= 3 else { return nil }

    // Một đỉnh không hữu hạn làm HỎNG cả biên, và nó hỏng theo kiểu câm nhất có
    // thể: phép so `<` ở vòng lặp dưới luôn trả `false` cho NaN, nên cái đỉnh
    // hỏng bị BỎ QUA và hàm trả về quãng ngắn nhất của những đỉnh còn lại — một
    // con số dương, hữu hạn, tự tin, đo tới một biên đã thủng một mảng. Ca kiểm
    // số bắt được đúng chuyện này, và lời chặn nằm đây chứ không nằm ở vòng lặp:
    // biên đọc không trọn thì không có van, chứ không phải có một van bé hơn.
    guard boundaryVertices.allSatisfy(isFinite) else { return nil }

    // ĐỔI HỆ TOẠ ĐỘ, và đây là nửa dễ quên nhất của cả hàm. `boundaryVertices`
    // nằm trong hệ CỦA MẶT PHẲNG; điểm chạm nằm trong hệ THẾ GIỚI. So thẳng hai
    // thứ ấy là cộng nguyên quãng dời của mặt phẳng vào quãng vượt biên — cùng
    // một mép bàn báo 300 mm ở chỗ này và hàng mét ở chỗ kia, tuỳ ARKit đặt gốc
    // thế giới ở đâu. Mà gốc thế giới đặt ở chỗ cái máy đang đứng lúc mở app,
    // nên con số sai ấy đổi theo từng phiên và không lặp lại được.
    let local4 = simd_inverse(planeTransform) * SIMD4<Float>(worldPoint, 1)
    // Chiếu bỏ trục pháp tuyến: biên là một hình PHẲNG, và quãng vượt biên là
    // quãng đo TRONG mặt phẳng. Giữ lại `y` là trộn "ra ngoài mép" với "cách
    // mặt bao xa" — hai chuyện khác hẳn nhau, và tia thì luôn kết thúc ĐÚNG
    // trên mặt (y ≈ 0), nên phần cộng thêm ấy chỉ là nhiễu số học.
    let point = SIMD2<Float>(local4.x, local4.z)

    var best = Float.infinity
    for index in boundaryVertices.indices {
      let a = boundaryVertices[index]
      // Đa giác ĐÓNG: đỉnh cuối nối về đỉnh đầu. Bỏ đoạn khép kín là để hở đúng
      // một cạnh của biên, và một điểm nằm ngoài cạnh ấy đo vòng sang cạnh khác
      // — xa hơn thật, nên van báo động khi không cần và im khi cần.
      let b = boundaryVertices[(index + 1) % boundaryVertices.count]
      let distance = distanceToSegment(
        point: point,
        a: SIMD2<Float>(a.x, a.z),
        b: SIMD2<Float>(b.x, b.z))
      if distance < best { best = distance }
    }

    // Không hữu hạn thì `nil`, không phải NaN. NaN đi tiếp lên kênh thành một
    // `double` mà mọi phép so sánh đều trả `false`, nên một ngưỡng "vượt quá
    // ngần này thì cảnh báo" lặng lẽ không bao giờ đúng.
    guard best.isFinite else { return nil }
    return Double(best) * 1000
  }

  /// Cả ba thành phần đều là số hữu hạn.
  private static func isFinite(_ v: SIMD3<Float>) -> Bool {
    v.x.isFinite && v.y.isFinite && v.z.isFinite
  }

  /// Quãng từ một điểm tới ĐOẠN thẳng `a`–`b`, không phải tới đường thẳng qua
  /// chúng và không phải tới đỉnh gần nhất.
  ///
  /// **Vì sao tới đoạn.** `boundaryVertices` là các điểm MẪU ARKit rải dọc
  /// biên, không phải góc của một đa giác đều — quãng giữa hai đỉnh liên tiếp
  /// có thể tới hàng chục centimét. Một điểm nằm ngay ngoài giữa một cạnh dài
  /// thì đỉnh gần nhất xa hơn cạnh gấp nhiều lần, và con số đo tới đỉnh vẫn
  /// dương, vẫn hữu hạn, vẫn đúng hàng milimét. Đó là dạng hỏng mà cả cái van
  /// này sinh ra để chặn, xảy ra ngay bên trong chính cái van.
  private static func distanceToSegment(
    point: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>
  ) -> Float {
    let segment = b - a
    let lengthSquared = simd_length_squared(segment)
    // Hai đỉnh trùng nhau: không có đoạn nào, đo tới chính cái đỉnh ấy. Chia cho
    // 0 ở dưới sẽ ra NaN, và một NaN lọt vào phép so sánh `<` thì luôn `false`
    // — đoạn hỏng bị bỏ qua im lặng thay vì được đo.
    guard lengthSquared > 0 else { return simd_distance(point, a) }

    // Ghim vào [0, 1] LÀ chỗ "đoạn" khác "đường thẳng vô hạn": bỏ phép ghim thì
    // một điểm nằm ngoài đầu mút đo tới phần kéo dài của cạnh, và quãng vượt
    // biên nhỏ hơn sự thật — van báo an toàn ở đúng chỗ nó phải kêu.
    let t = min(1, max(0, simd_dot(point - a, segment) / lengthSquared))
    return simd_distance(point, a + segment * t)
  }
}
