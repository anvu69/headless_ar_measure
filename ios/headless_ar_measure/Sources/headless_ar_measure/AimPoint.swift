import CoreGraphics
import Foundation

/// Điểm trên màn mà một lượt raycast bắn ra từ đó.
///
/// **Đơn vị là POINT**, cùng hệ với `UIView.bounds`, với phép chiếu
/// `projectToScreen` và với `ArMeasureOverlay.pointA`/`pointB` mà gói bắn lên
/// Dart. Không phải điểm ảnh, và không có phép nhân hay chia hệ số nào ở bất cứ
/// đâu trong đường này.
///
/// Câu ấy phải viết ra vì gói đã trả giá cho nó một lần: từ `0.2.0` tới `0.9.0`
/// phép chiếu CHIA cho `contentScaleFactor`, và nhãn số đo lệch khỏi đoạn thẳng
/// đúng một hệ số nguyên trên hai máy khác hệ số (iPhone @3x, iPad @2x). Một
/// điểm ngắm nhận VÀO ở sai đơn vị là cùng cái lỗi ấy soi gương: nó không lệch
/// một hệ số nguyên ở chỗ dễ thấy, nó chỉ bắn tia vào một chỗ khác trên cảnh —
/// và trả về một toạ độ ba chiều hoàn toàn hợp lệ ở cái chỗ khác ấy.
///
/// **Tệp riêng, và không nhập `ARKit` hay `UIKit`.** Đó là chủ ý, không phải
/// chuyện xếp tệp cho gọn: chỉ `Foundation` và `CoreGraphics` thì phép tính này
/// dịch và chạy được thẳng trên macOS, nên nó có ca kiểm SỐ
/// (`test/aim_point_test.dart`) mà không cần một máy iOS nào. Cùng một lẽ với
/// `PlaneOvershoot.swift` và `VideoFormatChoice.swift`.
enum AimPoint {
  /// Tâm của khung — chỗ tâm ngắm đứng, và điểm ngắm MẶC ĐỊNH của cả gói.
  ///
  /// `nil` khi khung chưa có kích thước, và đó là một khả năng thật: platform
  /// view ở khung hình đầu tiên. Trả `CGPoint.zero` ở đó là bắn một tia vào góc
  /// trên bên trái của một khung không tồn tại, và nhận lấy bất cứ thứ gì rơi
  /// ra — thay vì nói "chưa bắn được".
  static func centre(of bounds: CGRect) -> CGPoint? {
    guard hasArea(bounds) else { return nil }
    return CGPoint(x: bounds.midX, y: bounds.midY)
  }

  /// Kéo [point] vào trong [bounds], hoặc trả `nil` khi không kéo vào đâu được.
  ///
  /// **Ngoài khung thì KẸP, không coi là trượt.** Ngón tay trượt ra mép màn
  /// giữa một quãng kéo là chuyện thường, và hai lối xử nó không tương đương:
  ///
  /// * Coi là trượt thì đầu mút ĐÓNG BĂNG ở chỗ cuối — và nửa sau của cử chỉ
  ///   người dùng xin (*"vừa giữ ngón tay vừa lia camera thì đầu mút cũng đi
  ///   theo"*) chết theo, vì lia camera không còn kéo được gì nữa.
  /// * Kẹp thì tia vẫn bắn qua một điểm màn camera ĐANG NHÌN THẤY, nên cả ba
  ///   tầng tia còn trả lời trung thực, và ngón quay lại trong khung thì đầu
  ///   mút đi tiếp từ mép chứ không nhảy.
  ///
  /// Và lối "bắn thẳng từ chỗ ngón đang ở" — tức là từ ngoài khung — là lối tệ
  /// nhất trong ba, dù nó trông thật thà nhất: một tia bắn ngoài khung nhìn đi
  /// về một hướng camera CHƯA BAO GIỜ quan sát, nên hai tầng tia đầu (hình học
  /// đã dựng, mặt phẳng vừa ước lượng) không có gì để trúng. Thứ duy nhất còn
  /// trả lời là tầng ngoại suy — một mặt phẳng đã dò được kéo dài ra khỏi biên
  /// của nó — và nó trả lời bằng một toạ độ ba chiều trông hoàn toàn hợp lệ,
  /// trên một mặt phẳng camera không hề thấy.
  ///
  /// `nil` ở hai đường, và cả hai là "không có tia nào bắn được", không phải
  /// "bắn ở đâu đó cho xong":
  ///
  /// * Khung chưa có kích thước.
  /// * Toạ độ không hữu hạn. `min`/`max` với `NaN` trả về `NaN` một cách im
  ///   lặng, và một `NaN` đi tiếp vào `raycastQuery` ra một lượt trượt không ai
  ///   giải thích được — nó trông y hệt một bề mặt xấu.
  static func clamped(_ point: CGPoint, into bounds: CGRect) -> CGPoint? {
    guard hasArea(bounds), isFinite(point) else { return nil }
    return CGPoint(
      x: min(max(point.x, bounds.minX), bounds.maxX),
      y: min(max(point.y, bounds.minY), bounds.maxY))
  }

  /// [point] có nằm trong [bounds] không — biên **ĐÓNG**, kể cả mép phải và
  /// mép dưới.
  ///
  /// **Cố ý không gọi `CGRect.contains`.** Phép ấy dùng khoảng NỬA MỞ: nó loại
  /// đúng hàng cuối và cột cuối. Dùng nó ở đây thì một ngón đặt đúng mép dưới
  /// bị khai là "ngoài khung" trong khi [clamped] không đổi toạ độ ấy một chút
  /// nào — một lượt kẹp không kẹp gì mà vẫn báo là đã kẹp. Hai hàm này phải
  /// nói về CÙNG một biên, nếu không thì lời khai gửi lên Dart cãi nhau với toạ
  /// độ mà tia thật sự bắn từ đó.
  static func isInside(_ point: CGPoint, of bounds: CGRect) -> Bool {
    guard hasArea(bounds), isFinite(point) else { return false }
    return point.x >= bounds.minX && point.x <= bounds.maxX
      && point.y >= bounds.minY && point.y <= bounds.maxY
  }

  /// Khung có diện tích dương và hữu hạn.
  ///
  /// Đọc `bounds.size`, **không** đọc `bounds.width`. Hai thứ ấy không bằng
  /// nhau: `CGRect.width` trả về TRỊ TUYỆT ĐỐI — CoreGraphics lặng lẽ chuẩn hoá
  /// một khung có bề rộng âm thành một khung dương nằm lệch chỗ. Một khung như
  /// thế không phải một khung nhìn, và nắn nó thành một khung nhìn là bịa ra
  /// một cái màn rồi bắn tia vào đó.
  private static func hasArea(_ bounds: CGRect) -> Bool {
    bounds.size.width > 0 && bounds.size.height > 0
      && bounds.size.width.isFinite && bounds.size.height.isFinite
      && bounds.origin.x.isFinite && bounds.origin.y.isFinite
  }

  private static func isFinite(_ point: CGPoint) -> Bool {
    point.x.isFinite && point.y.isFinite
  }
}
