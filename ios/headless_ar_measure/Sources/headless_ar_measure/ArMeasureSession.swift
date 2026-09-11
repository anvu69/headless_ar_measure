import ARKit
import AVFoundation
import QuartzCore
import SceneKit
import UIKit
import simd

/// Tám trạng thái của một phiên đo — đúng bằng `ArMeasureStatus` bên Dart.
///
/// `rawValue` **LÀ** hợp đồng: `ArMeasure.parseSample` bên Dart so chuỗi, và một
/// chuỗi lạ ở đây làm cả mẫu bị bỏ (Dart trả `null`) chứ không có lỗi nào nổ.
/// Đổi tên ở một bên mà quên bên kia là một lỗi câm hoàn toàn — hai bên phải
/// sửa cùng một lượt.
enum ArMeasureStatus: String {
  case initializing
  case needsMotion
  case ready
  case firstPointPlaced
  case measured
  case trackingLost
  case interrupted
  case cameraUnauthorized
}

/// Vì sao ARKit đang bám hạn chế — khoá phụ đi kèm `needsMotion`.
///
/// `.excessiveMotion` và `.insufficientFeatures` đổ chung vào MỘT trạng thái vì
/// cả hai đều là "đang không đo được, chưa hỏng hẳn". Nhưng cách gỡ thì ngược
/// nhau: một cái bảo người dùng chậm lại, cái kia bảo rê máy quanh tìm bề mặt
/// có vân. Không nói ra thì màn phải chọn một câu và sai một nửa số lần.
///
/// Là khoá phụ chứ không phải trạng thái thứ chín: `ArMeasure.parseSample` bỏ
/// qua khoá lạ một cách vô hại, nên bản Dart cũ vẫn đọc được mẫu này.
///
/// `rawValue` **LÀ** hợp đồng, y như `ArMeasureStatus` ở trên — và
/// `test/status_contract_test.dart` canh cả hai enum.
enum ArMeasureLimitedReason: String {
  case excessiveMotion
  case insufficientFeatures
}

/// Chuyện gì đã xảy ra với một lời gọi `placePoint`.
///
/// Bản trước trả `Bool`, và trên máy thật cái `false` ấy hoá ra là một cái nút
/// không làm gì: người dùng chĩa vào màn iPad đen bóng, bấm, và không có điểm,
/// không có thông báo, không có gì. `false` đúng — nhưng nó gộp ba chuyện có ba
/// lời khuyên NGƯỢC nhau vào một giá trị, nên màn không có câu nào để nói:
///
/// * [missed] — "rê máy chậm quanh vật cho tới khi tâm ngắm khoá lại"
/// * [notReady] — "chờ, phiên chưa bám được" (chính trạng thái đang bắn ra nói
///   nốt phần còn lại)
/// * [alreadyComplete] — "đã đủ hai điểm, bấm Chốt hoặc Hoàn tác"
///
/// `rawValue` **LÀ** hợp đồng, y như `ArMeasureStatus`: `ArMeasureController`
/// bên Dart so chuỗi bằng tay, và một chuỗi lạ rơi về `notReady` — tức là một
/// cú chấm THÀNH CÔNG cũng bị báo là chưa sẵn sàng, không lỗi nào nổ.
/// `test/status_contract_test.dart` canh cả bốn.
enum ArMeasurePlaceResult: String {
  case placed
  case missed
  case notReady
  case alreadyComplete
}

/// Chuyện gì đã xảy ra với một lời gọi `movePoint(at:)`.
///
/// Cùng một họ với `ArMeasurePlaceResult`, và cùng một lẽ: ba trong bốn giá trị
/// là "không có điểm nào đổi chỗ", và ba câu đi kèm chúng **ngược nhau**.
///
/// * `moved` — điểm đã đổi chỗ, số đo đã tính lại
/// * `missed` — tia trượt; **điểm cũ còn nguyên**, rê máy rồi bấm lại
/// * `notReady` — phiên không ở trạng thái bắn tia được; `ArMeasureStatus` nói
///   vì sao
/// * `noSuchPoint` — chỉ số không trỏ vào điểm nào đang có; không có câu nào
///   để nói với NGƯỜI DÙNG, đây là một câu nói với app
///
/// `rawValue` **LÀ** hợp đồng, y như `ArMeasurePlaceResult`, và ở lệnh này
/// chiều hỏng đắt hơn: một chuỗi lệch làm Dart báo "chưa dời được" cho một điểm
/// vừa nhảy chỗ trên màn — con số và hình lại nói hai chuyện khác nhau, đúng
/// dạng lỗi mà cả lệnh này sinh ra để đóng.
/// `test/status_contract_test.dart` canh cả bốn.
enum ArMeasureMoveResult: String {
  case moved
  case missed
  case notReady
  case noSuchPoint
}

/// Chuyện gì đã xảy ra với một lời gọi `grabPoint(at:)`.
///
/// Vì sao cặp `grabPoint`/`releasePoint` tồn tại bên cạnh `movePoint(at:)`,
/// nguyên văn lượt máy thật: *"chiếu hồng tâm vào đầu mút thì hiện lên chức
/// năng Dời đầu này. Tuy nhiên cách dùng khó chịu, nó không phải nắm lấy điểm
/// đó và kéo cho đến khi buông ra, mà nhấn vào nút Dời đầu này là chỉ nhích
/// được một khoảng. Phải làm cho nó thực tế giống như chỉnh 2 đầu của một chiếc
/// thước dây vậy."*
///
/// `movePoint` là một NHÁT dời; cặp này mở một QUÃNG nắm, và trong quãng ấy đầu
/// mút bám theo tia ở mỗi khung hình.
///
/// * `grabbed` — đã nắm; từ khung hình kế tiếp đầu mút bám theo tâm ngắm
/// * `notReady` — phiên không ở trạng thái bắn tia được, hoặc phiên đã dừng
/// * `noSuchPoint` — chỉ số không trỏ vào điểm nào đang có; một câu nói với APP
/// * `alreadyGrabbing` — đang nắm một đầu rồi; buông cái ấy trước
///
/// `rawValue` **LÀ** hợp đồng, y như `ArMeasureMoveResult`. Chiều hỏng ở đây là
/// chiều câm nhất của cả bộ: một chuỗi lệch làm Dart đọc ra `notReady` trong
/// khi tầng Swift ĐÃ nắm, nên app không vẽ trạng thái nắm — người dùng rê máy,
/// thấy đầu mút chạy theo, và không có cái nút nào để buông.
enum ArMeasureGrabResult: String {
  case grabbed
  case notReady
  case noSuchPoint
  case alreadyGrabbing
}

/// Chuyện gì đã xảy ra với một lời gọi `releasePoint()`.
///
/// * `released` — đã buông, và điểm chốt ở chỗ lượt trúng CUỐI của quãng kéo
/// * `unmoved` — đã buông, và điểm nằm nguyên chỗ cũ: **không khung nào** trong
///   cả quãng nắm bắt được bề mặt
/// * `notGrabbing` — không có gì trong tay (gói đã tự buông, hoặc chưa nắm)
/// * `notReady` — phiên đã dừng; cũng là giá trị của một kênh câm
///
/// `unmoved` tách khỏi `released` vì câu nói với người dùng ngược nhau: một bên
/// là "đã dời, chốt lại khi số đứng yên", một bên là "chưa dời được, chĩa vào
/// chỗ có vân rồi nắm lại". Gộp là để màn báo đã dời cho một cú dời chưa xảy ra.
///
/// `notGrabbing` tách khỏi `notReady` vì cùng lẽ với cặp
/// `noSuchPoint`/`notReady` của `movePoint`: `notGrabbing` là một câu về TRẠNG
/// THÁI của phiên, mà một kênh chết không biết gì về trạng thái ấy.
enum ArMeasureReleaseResult: String {
  case released
  case unmoved
  case notGrabbing
  case notReady
}

/// Kết quả một lượt dán ảnh lên đoạn thẳng.
///
/// `badImage` tách khỏi `notReady` vì hai chuyện khác nhau hẳn về chỗ phải sửa:
/// `notReady` là không có phiên nào (kênh chết, view đã chết), còn `badImage` là
/// phiên còn sống và tấm ảnh app gửi xuống KHÔNG giải mã được. Gộp chúng là để
/// một lỗi dựng ảnh bên Dart đội lốt một lỗi vòng đời.
///
/// **Xoá nhãn (gửi `nil`) là `ok`**, không phải một lỗi: nó là một lệnh hợp lệ,
/// và nó là đường app dùng khi phép đo kết thúc.
enum ArMeasureLabelResult: String {
  case ok
  case notReady
  case badImage
}

// MARK: - Chẩn đoán

/// Tầng mục tiêu mà tia ĐÃ trúng — đọc thẳng từ `ARRaycastResult.target`.
///
/// Ba giá trị đúng bằng `ARRaycastQuery.Target`. `.existingPlaneGeometry` là
/// điểm nằm trên một mặt phẳng ARKit đã xác nhận; `.estimatedPlane` là một mặt
/// phẳng ARKit ĐOÁN ra từ hình học quanh tia (trên máy LiDAR thì đó là lưới
/// thật, nên cùng một chữ mang hai mức tin cậy rất khác nhau — vì thế
/// [ArPointDiagnostics] còn chở kèm mặt phẳng trúng).
/// `.existingPlaneInfinite` là một mặt phẳng ĐÃ dò ra, kéo dài vượt khỏi biên
/// của chính nó — điểm SUY RA, không phải điểm quan sát được. Nó vào danh sách
/// gói bắn ra từ 0.6.0, và không bao giờ đi một mình: mọi lượt trúng ở tầng ấy
/// chở kèm `overshootMm` ([PlaneOvershoot]). Xem [ArMeasureSession.raycastFromReticle].
///
/// `rawValue` **LÀ** hợp đồng, y như `ArMeasureStatus` — và
/// `test/status_contract_test.dart` canh cả ba.
enum ArRaycastTarget: String {
  case existingPlaneGeometry
  case existingPlaneInfinite
  case estimatedPlane
}

/// Trạng thái bám của ARKit tại đúng khoảnh khắc một điểm được chấm.
///
/// Sáu nhánh, KHÔNG gộp năm nhánh `.limited` lại thành một chữ "limited": mỗi
/// nhánh là một giả thuyết khác về vì sao một số đo lệch, và gộp là xoá đúng
/// phần phân biệt được chúng. `.limited(.initializing)` nói "máy chưa ấm",
/// `.limited(.excessiveMotion)` nói "tay đang rê", `.limited(.relocalizing)`
/// nói "hệ toạ độ vừa nối lại" — ba lời giải khác hẳn nhau cho cùng một con số
/// lệch.
///
/// Khác `ArMeasureLimitedReason` ở chỗ: cái kia là thứ NGƯỜI DÙNG đọc (hai lý
/// do có hai lời khuyên), cái này là thứ NGƯỜI ĐIỀU TRA đọc.
///
/// `rawValue` **LÀ** hợp đồng — `test/status_contract_test.dart` canh cả sáu.
enum ArTrackingSnapshot: String {
  case normal
  case limitedInitializing
  case limitedExcessiveMotion
  case limitedInsufficientFeatures
  case limitedRelocalizing
  case notAvailable
}

/// Phương của mặt phẳng mà điểm rơi lên. Đúng bằng `ARPlaneAnchor.Alignment`.
///
/// `rawValue` **LÀ** hợp đồng — `test/status_contract_test.dart` canh cả hai.
enum ArPlaneAlignment: String {
  case horizontal
  case vertical
}

/// Điều kiện MỘT điểm được chấm — ảnh chụp tại đúng khoảnh khắc cú bấm.
///
/// Vì sao lớp này tồn tại: một lượt điều tra dài đã bác sạch mọi giả thuyết về
/// sai lệch số đo, và bác vì cùng một lý do ở MỌI giả thuyết — mẫu bắn lên Dart
/// không mang một mẩu nào về việc phép đo đã diễn ra thế nào. Mọi lời giải khớp
/// mọi số đo, nên không lời giải nào kiểm được.
///
/// Không cái nào ở đây tham gia vào phép tính khoảng cách. Đây là tầng GHI, và
/// nó không được đụng vào thuật toán đo.
///
/// Mọi trường đều tuỳ chọn, và đó là chủ ý: thiếu một khung hình camera, hoặc
/// ARKit trả một giá trị `@unknown`, thì khoá ấy vắng mặt trên dây và Dart đọc
/// ra `null`. Bịa một giá trị mặc định ở đây là dựng ra bằng chứng giả cho đúng
/// cái lượt điều tra mà tầng này sinh ra để phục vụ.
struct ArPointDiagnostics {
  let target: ArRaycastTarget?
  let tracking: ArTrackingSnapshot?

  /// Mili-giây kể từ lời gọi `session.run(...)` gần nhất. Biến duy nhất phân
  /// biệt được giả thuyết "máy chưa ấm".
  let sessionAgeMs: Int?

  /// Khoảng cách từ tâm camera tới điểm chấm, mm.
  let cameraDistanceMm: Double?

  /// Góc của tia so với MẶT PHẲNG trúng, độ. 90° là chĩa vuông góc vào mặt,
  /// 0° là tia lướt sát mặt.
  let rayAngleDeg: Double?

  /// MẶT PHẲNG NÀO — `ARPlaneAnchor.identifier.uuidString` của mặt phẳng điểm
  /// này rơi lên.
  ///
  /// `nil` khi tia trúng một mặt ƯỚC LƯỢNG: tầng ấy không có `ARPlaneAnchor`
  /// nào, và `nil` ở đó là một SỰ THẬT — "không có mặt phẳng" — phải phân biệt
  /// được với "có mặt phẳng, và là một mặt phẳng khác".
  ///
  /// Chỉ để SO SÁNH BẰNG NHAU. Gói không kết luận "hai đầu mút có cùng mặt
  /// phẳng không" — cùng một ranh giới với [overshootMm]: gói trả sự thật đo
  /// được, app quyết.
  ///
  /// Là định danh **lúc chấm**, và không đường nào viết lại nó. Xem
  /// [ArMeasureSession.planeId(of:)].
  let planeId: String?

  /// `nil` khi tia trúng một mặt ƯỚC LƯỢNG — không có `ARPlaneAnchor` nào.
  let planeAlignment: ArPlaneAlignment?
  let planeWidthMm: Double?
  let planeHeightMm: Double?

  /// Điểm này nằm cách đa giác biên của chính mặt phẳng ấy bao xa, mm.
  ///
  /// Chỉ khác `nil` ở tầng `.existingPlaneInfinite` — tức là ở đúng những điểm
  /// SUY RA. Đây là **lai lịch** của một điểm đã chấm, và nó phải đi cùng số đo
  /// tới tận kho: một số đo ngoại suy đọc lại sau một tuần mà trông y hệt một
  /// số đo trên mặt phẳng đã xác nhận thì cái van chỉ hoãn được lỗi một tuần.
  ///
  /// Khác bảy trường trên ở một điểm: chúng là số liệu để NGƯỜI ĐỌC nhìn, còn
  /// cái này là số liệu để MÁY quyết định. Xem [PlaneOvershoot].
  let overshootMm: Double?

  /// Map đã sẵn sàng cho kênh. Khoá vắng mặt = tầng nền không nói được.
  var payload: [String: Any] {
    var map: [String: Any] = [:]
    if let target { map["target"] = target.rawValue }
    if let tracking { map["tracking"] = tracking.rawValue }
    if let sessionAgeMs { map["sessionAgeMs"] = sessionAgeMs }
    if let cameraDistanceMm { map["cameraDistanceMm"] = cameraDistanceMm }
    if let rayAngleDeg { map["rayAngleDeg"] = rayAngleDeg }
    if let planeId { map["planeId"] = planeId }
    if let planeAlignment { map["planeAlignment"] = planeAlignment.rawValue }
    if let planeWidthMm { map["planeWidthMm"] = planeWidthMm }
    if let planeHeightMm { map["planeHeightMm"] = planeHeightMm }
    if let overshootMm { map["overshootMm"] = overshootMm }
    return map
  }
}

/// Một lượt trúng của tia phân tầng: kết quả của ARKit, cộng cái van đi kèm.
///
/// Van và kết quả đi CHUNG một giá trị, không phải hai đường: quãng vượt biên
/// tính được đúng một lần, tại đúng lượt bắn đã sinh ra nó, từ đúng mặt phẳng
/// mà lượt ấy trúng. Trả riêng `ARRaycastResult` rồi đi tìm lại mặt phẳng ở
/// bước sau là đi tìm một thứ ARKit có thể đã thay (mặt phẳng lớn lên, hai mặt
/// nhập một) — và con số ra được vẫn là một con số milimét trông bình thường.
struct ArSurfaceHit {
  let result: ARRaycastResult

  /// Quãng từ điểm chạm tới đa giác biên của mặt phẳng ấy, mm.
  ///
  /// `nil` ở hai tầng đầu, và ở đó `nil` là một sự thật chứ không phải một chỗ
  /// thiếu: điểm nằm TRONG biên (tầng hình học) hoặc trên một mặt ARKit vừa
  /// đoán ra (tầng ước lượng) thì không có biên nào bị vượt.
  ///
  /// Ở tầng ngoại suy nó KHÔNG BAO GIỜ `nil` — [ArMeasureSession.raycastFromReticle]
  /// bỏ hẳn lượt trúng nào không tính được van.
  let overshootMm: Double?
}

/// Một đầu mút đã chấm, kèm LAI LỊCH của nó, để tầng vẽ dùng.
///
/// Vị trí và lai lịch đi chung một giá trị chứ không phải hai mảng song song:
/// hai mảng lệch nhau một ô thì đầu tin được vẽ thành đầu suy ra và ngược lại —
/// im lặng, và lệch đúng về phía nguy hiểm.
struct ArMeasureMark {
  let position: SIMD3<Float>

  /// Điểm này lấy từ một mặt phẳng đã bị KÉO DÀI ra ngoài biên của nó.
  let isExtrapolated: Bool
}

/// Đường ra của một phiên: một map đã sẵn sàng cho `EventChannel`.
///
/// Là protocol chứ không phải closure để phía nhận giữ được **yếu**. Một
/// closure bắt `self` mạnh ở đây là đúng cái vòng giữ view sống mãi mà luật
/// vòng đời số 2 nói tới.
protocol ArMeasureSessionOutput: AnyObject {
  func arMeasureSession(_ session: ArMeasureSession, didProduce sample: [String: Any])

  /// Khung lớp phủ: hai đầu đoạn thẳng đã chiếu xuống toạ độ màn, kèm số đo
  /// đang chạy. Đi kênh RIÊNG, nhịp riêng — xem [ArMeasureSession.refreshOverlay].
  func arMeasureSession(_ session: ArMeasureSession, didProduceOverlay frame: [String: Any])
}

/// Kết quả một lượt dò tia từ tâm ngắm.
///
/// Bốn nhánh, và ba nhánh đầu KHÔNG gộp được vào một `SIMD3<Float>?`: "chưa tới
/// nhịp dò" khác hẳn "vừa dò và trượt". Gộp lại thì mỗi lượt bị giãn nhịp đọc ra
/// một lượt trượt, và tâm ngắm tắt phụt mỗi lần khung hình tới sớm.
private enum ArReticleProbe {
  /// Trạng thái phiên không cho chấm điểm — không dò, và mọi thứ suy ra từ tia
  /// đều hết nghĩa.
  case unavailable

  /// Chưa tới nhịp dò kế tiếp. Giữ nguyên mọi thứ của lượt trước.
  case skipped

  /// Trúng, kèm vị trí trong hệ toạ độ thế giới, TẦNG tia đã trúng, quãng vượt
  /// biên nếu tầng ấy là tầng ngoại suy, GÓC của tia so với mặt phẳng ấy, và
  /// ĐỊNH DANH của chính mặt phẳng ấy.
  ///
  /// Cả năm đi kèm chứ không suy lại sau: chúng chỉ tồn tại trong
  /// `ARRaycastResult` của đúng lượt dò này, và ba tầng mang ba mức tin cậy
  /// khác hẳn nhau — mặt phẳng ARKit đã xác nhận, mặt phẳng nó vừa đoán ra
  /// quanh tia, và một mặt phẳng đã dò được kéo dài ra ngoài biên của nó.
  ///
  /// Góc đi cùng chỗ này chứ không đi một kênh riêng: nó đo trên CÙNG mặt phẳng
  /// mà lượt bắn này trúng, từ CÙNG tư thế camera. Đo lại ở bước sau là đo một
  /// tia khác — tay người dùng đã nhúc nhích — và con số ra được vẫn là một số
  /// độ trông bình thường.
  ///
  /// Định danh cũng vậy, và mạnh hơn: mặt phẳng có thể đã lớn lên hoặc bị GỘP
  /// với mặt khác giữa hai lượt, nên hỏi lại sau là hỏi về một thế giới khác.
  ///
  /// `surface` là CHÍNH kết quả raycast đã sinh ra bốn thứ trên. Nó đi kèm vì
  /// một quãng NẮM cần dựng một `ARAnchor` và một khối chẩn đoán từ đúng lượt
  /// bắn này — xem `ArMeasureSession.stepDrag(now:probe:)`. Bắn một tia thứ hai
  /// để lấy lại nó là hai tia khác nhau trong cùng một khung hình: điểm đi tới
  /// một chỗ, còn tâm ngắm hứa một chỗ khác.
  case hit(
    point: SIMD3<Float>,
    surface: ArSurfaceHit,
    target: ArRaycastTarget?,
    overshootMm: Double?,
    rayAngleDeg: Double?,
    planeId: String?)

  /// Đã dò và không trúng gì.
  case missed
}

/// Một quãng NẮM đang mở: đầu mút nào đang trong tay, và nó đã bám tới đâu.
///
/// **Không đụng vào `ARAnchor` trong suốt quãng kéo.** Dời một anchor nghĩa là
/// `session.remove` cộng `session.add`, và làm việc ấy 60 lần mỗi giây là 60
/// lượt đột biến vào phiên ARKit cho một điểm chưa chốt. Thay vào đó [point]
/// che vị trí của anchor ở tầng ĐỌC ([ArMeasureSession.position(ofPointAt:)]),
/// và anchor chỉ bị thay đúng một lần, ở lúc buông — qua cùng một hàm mà
/// `movePoint(at:)` dùng.
private struct ArDragState {
  /// Chỉ số của điểm đang nắm, trong `anchors`.
  let index: Int

  /// Vị trí ĐANG VẼ, đã làm mượt.
  ///
  /// **Chỉ dùng nửa LÀM MƯỢT của `LivePointFilter`, không dùng nửa quãng ôm.**
  /// Đây là chỗ lật lời chú cũ của `movePoint(at:)` ("dời KHÔNG đi qua bộ lọc
  /// đầu mút sống"), và lời chú ấy vẫn đúng nguyên văn cho cái nó nói về: một
  /// NHÁT dời đặt điểm đúng một lần, nên độ trễ của bộ lọc là một sai số hệ
  /// thống chôn vào một điểm đã chốt, và quãng ôm 100 ms còn cho một lượt TRƯỢT
  /// trả về toạ độ cũ rồi báo `moved`.
  ///
  /// Một quãng KÉO thì khác hẳn ở cả hai vế:
  ///
  /// * Nó đúng là một đầu mút SỐNG — vẽ lại 60 lần mỗi giây từ một tia mới, nên
  ///   nó dính đúng hai dạng nhiễu mà bộ lọc sinh ra để chặn, và người dùng đã
  ///   gọi tên chúng trên máy thật cho đầu sống của đoạn thẳng: *"đặc biệt ở
  ///   đầu mút có thể nhấp nháy liên tục"*. Ba tầng tia được thử theo thứ tự,
  ///   nên hai khung liên tiếp trả về hai BỀ MẶT khác nhau và điểm nhảy hàng
  ///   centimét trong khi tay người dùng đứng yên.
  /// * Quãng ôm không tham gia: [ArMeasureSession.stepDrag(now:probe:)] KHÔNG
  ///   gọi `miss(at:)` bao giờ, nên bộ lọc không có đường nào hết hạn và trả
  ///   `nil`. Tia trượt thì điểm đứng yên — vô thời hạn, cho tới lượt trúng kế
  ///   tiếp hoặc tới lúc buông.
  ///
  /// Và cái giá — độ trễ — không đi vào điểm đã chốt, vì lúc buông gói chốt
  /// [hit] chứ không chốt giá trị này. Xem [ArMeasureSession.releasePoint].
  var filter = LivePointFilter()

  /// Lượt TRÚNG gần nhất của quãng này. `nil` khi chưa khung nào trúng.
  ///
  /// Đây là thứ được chốt lúc buông — **không phải** [filter]. Vệt đã làm mượt
  /// là thứ để NHÌN; chỗ đúng là chỗ tia trúng. Hai thứ ấy chỉ lệch nhau trong
  /// lúc tay còn đang rê (τ = 0,03 s, nên chúng gặp nhau trong khoảng một phần
  /// mười giây sau khi tay dừng), và người dùng phải dừng tay để với tới nút
  /// buông.
  var hit: ArSurfaceHit?

  /// Lai lịch đo tại CHÍNH khung hình đã sinh ra [hit].
  ///
  /// Ghi ở mỗi bước kéo chứ không dựng lại lúc buông, và đây là chỗ đắt nhất
  /// của cả lượt: `rayAngleDeg` và `cameraDistanceMm` đo so với tư thế camera
  /// HIỆN TẠI, nên một khối dựng lại ở lúc buông gán một góc chưa ai bắn cho
  /// một điểm đã đứng yên — một con số độ trông hoàn toàn hợp lệ.
  var diagnostics: ArPointDiagnostics?
}

/// Chặn `ARSCNView` dựng `SCNNode` cho anchor.
///
/// `ARSCNView` tự dựng và NUÔI một `SCNNode` cho mỗi `ARAnchor` của phiên. Với
/// `sceneReconstruction = .mesh` đó là hàng trăm node cho hình học không ai vẽ,
/// cộng một mảng hàng trăm anchor đổ vào callback trên luồng chính.
///
/// Header của Apple nói rõ đường thoát: *"If this method is not implemented, a
/// node will be automatically created. If nil is returned the anchor will be
/// ignored."*
///
/// Gói này KHÔNG vẽ gì — mọi lớp phủ là việc của Flutter — nên trả `nil` cho
/// MỌI anchor, kể cả hai điểm của chính mình. Không có node nào cần dựng, và
/// tia bắn ở [ArMeasureSession.raycastFromReticle] đọc dữ liệu của phiên chứ
/// không đọc cây cảnh SceneKit.
///
/// Là một đối tượng RIÊNG chứ không để `ArMeasureSession` tự nhận vai:
/// `ARSCNViewDelegate` kế thừa `ARSessionObserver`, nên gắn phiên vào đây có
/// thể làm mỗi sự kiện gián đoạn / đổi trạng thái tới hai lần (một đường qua
/// `session.delegate`, một đường qua `sceneView.delegate`). Lớp này không cài
/// phương thức nào của `ARSessionObserver`, nên không có đường thứ hai nào.
final class ArMeasureNodeSuppressor: NSObject, ARSCNViewDelegate {
  func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
    nil
  }
}

/// Hai chấm và đoạn thẳng nối chúng — thứ DUY NHẤT gói này vẽ.
///
/// Vẽ ở tầng SceneKit chứ không đẩy lên Flutter, và đó không phải chuyện tiện
/// tay: hai điểm là toạ độ 3D trong hệ toạ độ của ARKit. Muốn vẽ chúng ở Flutter
/// thì phải chiếu tay xuống toạ độ màn, mỗi khung hình một lần, qua một ma trận
/// camera đi thêm một vòng kênh nền tảng — và bất cứ độ trễ nào của vòng ấy hiện
/// ra thành hai chấm trượt khỏi vật thật mỗi lần máy xoay. Ở đây thì SceneKit
/// chiếu chúng trong cùng lượt vẽ với nền camera, nên chúng dính vào vật.
///
/// Node của lớp này gắn thẳng vào `rootNode`, KHÔNG đi qua
/// `renderer(_:nodeFor:)` — nên [ArMeasureNodeSuppressor] vẫn trả `nil` cho mọi
/// anchor và hai chuyện không đụng nhau.
final class ArMeasureNodes {
  /// Kích thước cố định trong KHÔNG GIAN THẬT, không phải trên màn.
  ///
  /// App Measure của Apple giữ chấm to bằng nhau trên màn bằng cách chia tỉ lệ
  /// theo khoảng cách tới máy ở mỗi khung hình. Ở đây cố ý không làm thế: nó
  /// bắt lớp này chạy mỗi khung hình kể cả lúc không có gì đổi, mà cả tệp này
  /// dựng quanh chuyện KHÔNG chạy mỗi khung hình. Cái giá là chấm trông nhỏ dần
  /// khi lùi xa — chấp nhận được trong tầm đo 0,3–3 m.
  private static let dotRadius: CGFloat = 0.007
  private static let lineRadius: CGFloat = 0.002

  let root = SCNNode()

  private let dots: [SCNNode]

  /// Hình thay thế cho một đầu mút NGOẠI SUY: một vòng rỗng thay cho chấm đặc.
  ///
  /// Dựng sẵn cả hai hình cho mỗi đầu mút rồi chỉ ẩn/hiện, cùng lối với mọi thứ
  /// khác trong lớp này — đổi hình bằng cách dựng lại `SCNGeometry` là cấp phát
  /// trên luồng vẽ, ở đúng nhịp số đo trôi.
  private let rings: [SCNNode]

  private let line: SCNNode

  /// Thứ tự vẽ của tấm ảnh dán, so với đoạn thẳng và hai đầu mút.
  ///
  /// **"Vẽ sau" một mình KHÔNG đủ ở 3D, và đây là chỗ giải nốt vế còn lại.**
  /// Bất biến cũ — *đường kẻ không chạy xuyên viên* — nay phải giữ trong một
  /// cảnh có chiều sâu, nơi thứ tự trên màn do bộ đệm sâu quyết chứ không do
  /// thứ tự gọi vẽ. Hai vế phải đi cùng nhau:
  ///
  /// * mọi vật liệu ở đây **không đọc và không ghi bộ đệm sâu** (xem
  ///   [makeMaterial]), nên bộ đệm sâu không còn tiếng nói nào;
  /// * và khi ấy `renderingOrder` là thứ duy nhất còn quyết, nên nó phải đặt
  ///   TƯỜNG MINH chứ không trông vào mặc định.
  ///
  /// Thiếu vế đầu thì tấm ảnh và đoạn thẳng nằm gần như cùng một độ sâu —
  /// chúng cắt nhau ở đúng trung điểm — và cái vạch sáng chạy ngang tấm ảnh
  /// nhấp nháy theo từng khung hình (z-fighting). Thiếu vế sau thì SceneKit
  /// sắp xếp theo ý nó, và trên máy nó đúng cho tới cái ngày nó không.
  private static let labelRenderingOrder = 10

  /// Node CHA của tấm ảnh: giữ vị trí, hướng và cỡ.
  ///
  /// Tách làm hai tầng vì hình học và biến đổi có nhịp sống khác hẳn nhau: cỡ
  /// và hướng đổi ở MỖI khung hình (`simdScale`, `simdOrientation` — vài phép
  /// gán), còn hình học chỉ đổi khi app gửi xuống một tấm ảnh có tỉ lệ khác.
  /// Gộp một tầng không sai, nhưng nó mời người sau đặt `plane.width` trong
  /// vòng cập nhật — tức dựng lại `SCNGeometry` trên luồng vẽ mỗi khung.
  private let labelPivot = SCNNode()
  private let labelPlane: SCNNode

  /// Cỡ tấm ảnh đang dán, đơn vị **POINT** (đã chia tỉ lệ điểm ảnh).
  ///
  /// `.zero` nghĩa là chưa có ảnh nào — xem [hasLabel].
  private(set) var labelPointSize: CGSize = .zero

  /// Có ảnh để dán hay không. Người gọi đọc nó trước khi bỏ công tính chỗ đứng.
  var hasLabel: Bool { labelPointSize.width > 0 && labelPointSize.height > 0 }

  init() {
    dots = [Self.makeDot(), Self.makeDot()]
    rings = [Self.makeRing(), Self.makeRing()]
    line = Self.makeLine()
    labelPlane = Self.makeLabelPlane()
    for node in dots + rings {
      root.addChildNode(node)
    }
    root.addChildNode(line)
    labelPivot.addChildNode(labelPlane)
    labelPivot.isHidden = true
    root.addChildNode(labelPivot)
    update(points: [], live: nil)
  }

  // MARK: - Tấm ảnh dán trên đoạn

  /// Nhận tấm ảnh app vừa dựng, hoặc `nil` để gỡ nó.
  ///
  /// **Gói không biết trên ảnh viết gì.** Nó nhận một `UIImage` đã mang sẵn tỉ
  /// lệ điểm ảnh (nên `image.size` đã là POINT) và dán nguyên xi. Mọi phông
  /// chữ, màu, bo góc và câu chữ nằm ở app — đó là ranh giới của kho này, và nó
  /// không phải chuyện tiện tay: hệ thiết kế, tệp phông và mọi khái niệm sản
  /// phẩm đều ở bên kia.
  ///
  /// Hình học chỉ dựng lại khi **tỉ lệ** ảnh đổi, không phải mỗi lượt gửi: con
  /// số đo trôi liên tục nên app gửi ảnh mới nhiều lần mỗi giây, mà bề ngang
  /// tấm ảnh thì chỉ đổi khi số chữ đổi.
  func setLabel(image: UIImage?) {
    guard let image, image.size.width > 0, image.size.height > 0 else {
      labelPointSize = .zero
      labelPivot.isHidden = true
      labelPlane.geometry?.firstMaterial?.diffuse.contents = nil
      return
    }

    labelPointSize = image.size
    if let plane = labelPlane.geometry as? SCNPlane {
      // Cao ĐÚNG 1 đơn vị, rộng theo tỉ lệ ảnh: cỡ thật đặt bằng `simdScale`
      // ở [placeLabel], nên hình học không phải biết gì về khoảng cách.
      let aspect = CGFloat(image.size.width / image.size.height)
      if abs(plane.width - aspect) > 1e-4 {
        plane.width = aspect
      }
      plane.firstMaterial?.diffuse.contents = image
    }
  }

  /// Đặt tấm ảnh vào chỗ. [scale] là chiều DỰNG của nó trong không gian thật,
  /// tính bằng mét — xem `LabelPlacement.worldHeight`.
  func placeLabel(position: SIMD3<Float>, orientation: simd_quatf, scale: Float) {
    guard hasLabel, scale.isFinite, scale > 0 else {
      labelPivot.isHidden = true
      return
    }
    labelPivot.simdPosition = position
    labelPivot.simdOrientation = orientation
    labelPivot.simdScale = SIMD3<Float>(repeating: scale)
    labelPivot.isHidden = false
  }

  func hideLabel() {
    labelPivot.isHidden = true
  }

  /// Đặt lại hình theo các điểm đang có — không điểm nào, một, hoặc hai — cộng
  /// một đầu SỐNG tuỳ chọn.
  ///
  /// `live` là giao điểm của tia tâm ngắm ở khung hình này. Nó dựng nên một
  /// ĐOẠN THẲNG và không dựng thêm chấm nào: một chấm nói "đã chấm ở đây", còn
  /// đầu sống thì chưa chấm gì cả. Thứ đánh dấu nó là tâm ngắm của app, đã nằm
  /// sẵn giữa màn.
  ///
  /// Đã đủ hai điểm thì `live` bị bỏ qua — đoạn thẳng nối hai điểm ĐÃ chấm, và
  /// tia tâm ngắm lúc ấy không còn nói về phép đo này nữa.
  ///
  /// Mỗi đầu mút hiện ra ở một trong HAI hình, theo lai lịch của nó: chấm ĐẶC
  /// cho điểm quan sát được, vòng RỖNG cho điểm ngoại suy. Xem [makeRing].
  ///
  /// Không dựng lại node nào — chỉ dời chỗ và ẩn/hiện. Dựng lại `SCNGeometry`
  /// mỗi lượt là cấp phát trên luồng vẽ, và lượt gọi này đi cùng nhịp với số đo
  /// trôi.
  func update(points: [ArMeasureMark], live: SIMD3<Float>?) {
    for index in dots.indices {
      // Ẩn CẢ HAI hình trước rồi mới hiện đúng một cái. Chỉ ẩn cái không dùng
      // thì một đầu mút đổi lai lịch giữa chừng để lại hình cũ nằm nguyên chỗ
      // — hai đầu mút thành ba, và cái thừa nằm đúng chỗ cái thật.
      dots[index].isHidden = true
      rings[index].isHidden = true
      guard index < points.count else { continue }

      let mark = points[index]
      let node = mark.isExtrapolated ? rings[index] : dots[index]
      node.simdPosition = mark.position
      node.isHidden = false
    }

    // Hai đầu của đoạn, theo đúng thứ tự ưu tiên. Không có cặp nào thì KHÔNG
    // vẽ: giữ lại đoạn của lượt trước là để một đoạn thẳng đứng yên trên màn
    // giữa lúc người dùng vẫn đang rê máy, và một đoạn đứng yên đọc ra "đã
    // chấm xong".
    let ends: (SIMD3<Float>, SIMD3<Float>)?
    if points.count >= 2 {
      ends = (points[0].position, points[1].position)
    } else if points.count == 1, let live {
      ends = (points[0].position, live)
    } else {
      ends = nil
    }

    guard let (a, b) = ends else {
      line.isHidden = true
      // Tấm ảnh chú thích ĐOẠN, nên không có đoạn thì không có gì để chú thích.
      // Ẩn ở đây chứ không để người gọi nhớ: lối ra sớm này là chỗ duy nhất mà
      // "vừa còn đoạn, nay hết" đi qua.
      hideLabel()
      return
    }

    let delta = b - a
    let length = simd_length(delta)
    // Hai điểm trùng nhau thì không có hướng nào để xoay hình trụ, và hình trụ
    // dài 0 cũng không vẽ ra gì. Ẩn đi, đừng dựng một quaternion NaN.
    guard length > 1e-5 else {
      line.isHidden = true
      return
    }

    (line.geometry as? SCNCylinder)?.height = CGFloat(length)
    line.simdPosition = (a + b) / 2
    line.simdOrientation = Self.rotation(toward: delta / length)
    line.isHidden = false
  }

  /// Phép xoay từ trục Y (trục dựng của `SCNCylinder`) sang một hướng đã chuẩn hoá.
  ///
  /// Chỗ đáng ngờ là hai đầu NGƯỢC CHIỀU nhau — hướng −Y, tức đo chiều cao từ
  /// trên xuống. Đó là một cách đo bình thường, không phải góc hiếm, và ở đó
  /// trục xoay về mặt toán học là không xác định: một công thức dựng trục bằng
  /// tích có hướng sẽ ra vectơ 0 rồi chuẩn hoá thành NaN, và một node có
  /// transform NaN thì SceneKit bỏ vẽ — im lặng, không lỗi nào nổ.
  ///
  /// Đã ĐO trên macOS 26 (`swift` một tệp, so vectơ Y sau khi xoay với hướng
  /// mong muốn): `simd_quatf(from:to:)` của Apple trả về đúng cho cả −Y, sai số
  /// 0. Nên dùng thẳng nó — nhưng vẫn có lưới: tài liệu của Apple KHÔNG hứa gì
  /// cho trường hợp ngược chiều, và một bản iOS sau đổi ý thì lưới này giữ hình
  /// vẽ được thay vì để nó biến mất.
  private static func rotation(toward direction: SIMD3<Float>) -> simd_quatf {
    let rotation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
    let vector = rotation.vector
    if vector.x.isNaN || vector.y.isNaN || vector.z.isNaN || vector.w.isNaN {
      // Bất cứ trục nào vuông góc với Y cũng đưa +Y về −Y sau nửa vòng.
      return simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
    }
    return rotation
  }

  private static func makeDot() -> SCNNode {
    let sphere = SCNSphere(radius: dotRadius)
    sphere.segmentCount = 16
    sphere.firstMaterial = makeMaterial()
    return SCNNode(geometry: sphere)
  }

  /// Hình của một đầu mút NGOẠI SUY: một vòng rỗng, cùng cỡ với chấm đặc.
  ///
  /// **Khác bằng HÌNH, không khác bằng MÀU**, và đó là một lựa chọn có ba lý do
  /// đo được — đổi màu là cách rẻ hơn hẳn:
  ///
  /// * Cảnh này KHÔNG có đèn nào ([makeMaterial]), nên mọi vật liệu ở đây đều
  ///   tự phát sáng. Một màu thứ hai tự phát sáng trên nền camera đọc ra như
  ///   một BÁO LỖI — đỏ nhất là thế — chứ không như một mức tin cậy thấp hơn.
  ///   Điểm ngoại suy không phải một lỗi; nó là một điểm chấm được, kém chắc.
  /// * Màu là thứ đầu tiên mất đi với người mù màu, và mất hẳn trong một tấm
  ///   ảnh in đen trắng — mà ảnh chụp là thứ người ta giữ lại.
  /// * Hai chấm đặc khác màu chỉ so được khi nhìn thấy CẢ HAI cạnh nhau. Rỗng
  ///   hay đặc thì đọc được trên từng đầu một, kể cả lúc đầu kia ngoài khung.
  ///
  /// Vòng của `SCNTorus` nằm trong mặt X–Z của node, nên nhìn nghiêng nó mỏng
  /// như sợi chỉ và nhìn dọc trục thì nó BIẾN MẤT hẳn. Hai bước dưới đây chữa
  /// đúng chuyện đó: xoay vòng về mặt X–Y (pháp tuyến thành +Z), rồi để
  /// `SCNBillboardConstraint` quay cả node về phía camera ở mỗi khung hình.
  /// Thiếu chúng thì cái nhãn hình học này im lặng vắng mặt ở đúng những góc
  /// ngắm người ta hay đứng — và một đầu ngoại suy trông y hệt không có gì.
  ///
  /// Ràng buộc billboard do SceneKit tự chạy trong lượt vẽ của nó, nên nó không
  /// phá luật "lớp này không chạy mỗi khung hình" của [ArMeasureNodes].
  private static func makeRing() -> SCNNode {
    let torus = SCNTorus(ringRadius: dotRadius, pipeRadius: dotRadius * 0.3)
    torus.ringSegmentCount = 24
    torus.pipeSegmentCount = 6
    torus.firstMaterial = makeMaterial()

    let ring = SCNNode(geometry: torus)
    ring.simdEulerAngles = SIMD3<Float>(.pi / 2, 0, 0)

    // Vòng nằm trong một node CON, và ràng buộc đặt ở node CHA: billboard ghi
    // đè trọn phép xoay của node nó gắn vào, nên đặt cả hai lên cùng một node
    // là phép xoay 90° ở trên bị xoá và vòng lại quay về mặt X–Z.
    let pivot = SCNNode()
    pivot.addChildNode(ring)
    pivot.constraints = [SCNBillboardConstraint()]
    return pivot
  }

  private static func makeLine() -> SCNNode {
    let cylinder = SCNCylinder(radius: lineRadius, height: 0.01)
    cylinder.radialSegmentCount = 12
    cylinder.firstMaterial = makeMaterial()
    return SCNNode(geometry: cylinder)
  }

  /// Tấm phẳng mang ảnh: cao 1 đơn vị, rộng theo tỉ lệ ảnh.
  ///
  /// `SCNPlane` nằm trong mặt X–Y của node với pháp tuyến `+Z`, tâm ở gốc —
  /// đúng hệ mà `LabelPlacement.basis` dựng ra.
  private static func makeLabelPlane() -> SCNNode {
    let plane = SCNPlane(width: 1, height: 1)
    plane.cornerRadius = 0
    plane.firstMaterial = makeLabelMaterial()

    let node = SCNNode(geometry: plane)
    node.renderingOrder = labelRenderingOrder
    return node
  }

  /// Vật liệu của tấm ảnh.
  ///
  /// Dựng riêng chứ không dùng chung [makeMaterial], vì bốn chỗ khác nhau — và
  /// mỗi chỗ chữa một hỏng CÂM:
  ///
  /// * **`diffuse.contents` là tấm ảnh**, không phải một màu. Cùng
  ///   `lightingModel = .constant` với phần còn lại, và cùng lý do: cảnh này
  ///   KHÔNG có đèn nào, nên một vật liệu cần đèn ra màu đen tuyền trên nền
  ///   camera.
  /// * **`wrapS`/`wrapT` = `.clamp`.** Mặc định của SceneKit là `.repeat`, và
  ///   với một tấm ảnh bo góc (tức có alpha ở bốn góc) thì mép đối diện chảy
  ///   ngược vào trong ở hàng điểm ảnh ngoài cùng — một viền mờ chỉ thấy khi
  ///   soi kỹ, và không lỗi nào nổ.
  /// * **`isDoubleSided`.** Phép lật là nửa vòng quanh PHÁP TUYẾN nên mặt trước
  ///   vẫn luôn quay về camera, và về lý thuyết một mặt là đủ. Hai mặt là lưới
  ///   an toàn cho đúng cái khung hình mà `basis` rơi vào nhánh suy biến: mất
  ///   một khung hình có chữ còn hơn mất một khung hình trống trơn.
  /// * **`readsFromDepthBuffer`/`writesToDepthBuffer` tắt**, y như hình đo —
  ///   xem [labelRenderingOrder] về vì sao hai cờ ấy và thứ tự vẽ là MỘT luật
  ///   chứ không phải hai.
  private static func makeLabelMaterial() -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.isDoubleSided = true
    material.diffuse.wrapS = .clamp
    material.diffuse.wrapT = .clamp
    material.diffuse.magnificationFilter = .linear
    material.diffuse.minificationFilter = .linear
    material.diffuse.mipFilter = .linear
    material.readsFromDepthBuffer = false
    material.writesToDepthBuffer = false
    return material
  }

  private static func makeMaterial() -> SCNMaterial {
    let material = SCNMaterial()
    // `.constant` chứ không phải mặc định `.blinn`, và đây là một cái bẫy có
    // thật: phiên đặt `automaticallyUpdatesLighting = false`, nên cảnh KHÔNG có
    // đèn nào. Một vật liệu cần đèn ra màu đen tuyền trên nền camera — vẽ rồi
    // mà trông y hệt chưa vẽ, không lỗi nào nổ.
    material.lightingModel = .constant
    material.diffuse.contents = UIColor.white
    // Không đọc và không ghi bộ đệm sâu: hình đo phải luôn thấy được, không bị
    // lưới LiDAR hay mặt phẳng ARKit dò ra che mất — đúng như app Measure.
    material.readsFromDepthBuffer = false
    material.writesToDepthBuffer = false
    return material
  }
}

/// Một phiên đo AR: sở hữu trọn một `ARSCNView`, một `ARSession`, và hai điểm.
///
/// Mỗi platform view dựng đúng một phiên và giữ nó mạnh. Không có phiên dùng
/// chung, không có singleton — engine Flutter giữ mạnh mọi factory vĩnh viễn,
/// nên bất cứ thứ gì factory giữ thêm là rò không gỡ được.
///
/// **Luồng.** `session.delegateQueue` được đặt tường minh về luồng chính, nên
/// MỌI thứ chạm vào trạng thái của lớp này nằm trên một luồng duy nhất: lệnh từ
/// kênh Flutter vào ở luồng nền tảng (chính), callback ARKit cũng vào luồng
/// chính, và hai hẹn giờ dưới đây cũng đặt trên hàng đợi chính. Không có khoá
/// nào trong tệp này, và đây là lý do.
final class ArMeasureSession: NSObject {
  /// Bề mặt camera trao cho Flutter. Phiên sở hữu nó, không ai khác.
  let sceneView: ARSCNView

  /// Giữ YẾU: plugin sống suốt đời engine, phiên thì chết theo màn AR.
  weak var output: ArMeasureSessionOutput?

  /// Giữ MẠNH, và phải thế: `ARSCNView.delegate` là tham chiếu YẾU (khuôn của
  /// `SCNView`), nên không ai giữ thì nó chết ngay sau `init` và `ARSCNView`
  /// lặng lẽ quay về nếp tự dựng node cho từng anchor.
  private let nodeSuppressor = ArMeasureNodeSuppressor()

  /// Hướng dẫn quét bề mặt — bản của Apple, không phải bản tự vẽ.
  ///
  /// `ARCoachingOverlayView` biết những thứ một lớp phủ tự vẽ không biết: lúc
  /// nào phiên đủ dữ liệu để dừng nhắc, hoạt hình nào ứng với thiếu vân so với
  /// rê quá nhanh, và câu chữ đã dịch sẵn theo ngôn ngữ máy. Gói không dịch gì
  /// cả — chuỗi hiện ra là chuỗi của hệ điều hành.
  private let coachingOverlay = ARCoachingOverlayView()

  /// Hai chấm và đoạn nối, vẽ ở tầng SceneKit.
  ///
  /// Phải vẽ ở đây chứ không ở Flutter: hai điểm là toạ độ 3D trong hệ toạ độ
  /// của ARKit, và chỉ tầng này biết chúng chiếu xuống màn ở đâu sau mỗi lượt
  /// máy xoay. Flutter chỉ nhận được một con số milimét.
  private let measureNodes = ArMeasureNodes()

  /// Đang chờ người dùng trả lời hộp thoại quyền camera.
  ///
  /// Chặn hỏi hai lần: `reset()` bấm liên tiếp trong lúc hộp thoại đang mở sẽ
  /// gọi lại [start], và `requestAccess` lần thứ hai không hiện thêm hộp thoại
  /// nào mà chỉ trả lời muộn — hai lời gọi `run` chồng nhau.
  private var isRequestingCameraAccess = false

  // MARK: - Ngưỡng bắn

  /// Số đo đổi ít hơn ngần này thì không bắn.
  ///
  /// Số đo được tính lại ở MỖI khung hình (xem [session(_:didUpdate frame:)]),
  /// nên không có ngưỡng này thì mỗi khung là một lượt vẽ lại bên Dart — kể cả
  /// khi con số chỉ rung ở chữ số không ai đọc. 0,5 mm nằm **dưới sàn nhiễu**
  /// của chính phép đo (dung sai nhỏ nhất gói này trả ra là ±2 mm trên máy
  /// LiDAR, ±5 mm trên máy thường),
  /// nên ngưỡng này không giấu được cái gì người dùng nhìn thấy — nó chỉ cắt
  /// phần rung mà mắt không đọc nổi.
  private static let minChangeMm = 0.5

  /// Khoảng cách tối thiểu giữa hai lần bắn liên tiếp của cùng một trạng thái.
  ///
  /// ARKit chạy 60 Hz. 15 Hz đã nhanh hơn tốc độ một người đọc kịp một con số
  /// đang đổi, và nó cắt bốn phần năm lưu lượng kênh. Đổi TRẠNG THÁI thì không
  /// bị nhịp này chặn — một chuyển trạng thái muộn 66 ms là một khung hình sai
  /// trên màn.
  private static let minIntervalSeconds = 1.0 / 15.0

  /// Nối lại vị trí sau gián đoạn: quá ngần này mà chưa bám lại được thì bỏ cuộc.
  ///
  /// Spec chốt "không nối lại được thì bỏ hai điểm và về `ready`". Câu hỏi còn
  /// lại là *bao lâu thì gọi là không nối lại được* — ARKit không báo thất bại,
  /// nó chỉ ở lì trong `.limited(.relocalizing)`. Năm giây là quãng một người
  /// còn chịu đứng nhìn màn hình mờ; lâu hơn thì họ đã tự bấm đo lại rồi.
  private static let relocalizationDeadlineSeconds: TimeInterval = 5

  /// Trần nhịp của kênh lớp phủ.
  ///
  /// Rời hẳn [minIntervalSeconds] của kênh trạng thái, và phải rời: lớp phủ nuôi
  /// một lớp VẼ, nên nó cần nhanh; trạng thái và chẩn đoán thì đổi vài giây một
  /// lần. Kéo hai thứ về cùng một nhịp là hỏng theo một trong hai chiều — lớp
  /// phủ giật ở 15 Hz, hoặc mọi người nghe trạng thái phải lọc ba mươi khung mỗi
  /// giây để tìm một thay đổi.
  ///
  /// 30 Hz chứ không phải 60 Hz theo khung hình: đây là một đoạn thẳng và một
  /// con số milimét, không phải một hoạt hình. Nửa số khung của ARKit đã trên
  /// ngưỡng mắt đọc được một vật đang trôi theo tay, và nó cắt một nửa lưu lượng
  /// kênh nền tảng ở đúng quãng ARKit đang tốn nhiều CPU nhất.
  private static let overlayMinIntervalSeconds = 1.0 / 30.0

  // MARK: - Nhịp dò tâm ngắm

  /// Bao lâu bắn một tia thăm dò cho tâm ngắm.
  ///
  /// Lượt dò này KHÔNG dùng chung nhịp với [minIntervalSeconds] vì hai thứ
  /// khác hẳn nhau về giá: bắn một mẫu là ghép một dictionary rồi đẩy qua kênh,
  /// còn dò là chạy tới BA `ARRaycastQuery` thật — một lượt cắt hình học mặt
  /// phẳng đã dò ra, rồi (nếu trượt) một lượt khớp mặt phẳng ước lượng quanh
  /// tia, rồi (nếu vẫn trượt) một lượt cắt mặt phẳng ấy kéo dài vô hạn, kèm
  /// một lượt quét đa giác biên để tính quãng vượt biên.
  ///
  /// Tầng thứ ba chỉ chạy ở đúng cảnh hai tầng đầu đã trượt — tức là ở đúng
  /// cảnh không có gì khác để làm — nên nó không cộng thêm gì vào quãng mà
  /// phép đo đang chạy trơn tru.
  ///
  /// Chọn 10 Hz, không phải 60 Hz theo khung hình:
  ///
  /// * Thứ dò ra là một **giá trị boolean**. Mắt người không phân biệt nổi hai
  ///   lần đổi cách nhau dưới 100 ms, nên 60 Hz mua đúng 0 phần thông tin.
  /// * Nó nằm dưới nhịp bắn 15 Hz đã chốt, nên cờ này KHÔNG BAO GIỜ là thứ làm
  ///   nghẽn kênh: nó bắn được nhiều nhất 10 lần/giây, và thực tế còn ít hơn
  ///   nhiều vì chỉ ĐỔI cờ mới bắn.
  /// * Ngân sách mỗi khung hình còn lại nguyên cho đường tính số đo, đường
  ///   BẮT BUỘC phải chạy đúng nhịp khung hình.
  ///
  /// Chưa đo được trên máy thật ở lượt này — con số chọn theo lập luận trên chứ
  /// không theo một phép đo. Nếu máy thật cho thấy 10 Hz vẫn nặng thì chỗ phải
  /// sửa là đúng hằng số này, không phải cấu trúc quanh nó.
  private static let aimProbeIntervalSeconds: TimeInterval = 1.0 / 10.0

  // Không còn hằng số "ân hạn" nào ở đây, và chỗ trống này là có chủ đích.
  //
  // Bản trước giữ cờ "đã khoá" thêm 0,3 s sau lượt dò trượt đầu tiên, với lý lẽ
  // rằng nó chống nhấp nháy trên bề mặt ranh giới. Lý lẽ ấy sai ở một chỗ đo
  // được: quãng ân hạn NẠP LẠI ở mỗi lượt trúng, nên nó không phải một bộ lọc
  // trễ — nó là một phép HOẶC trải trên cả cửa sổ. Một bề mặt chỉ trúng một lần
  // trong mỗi 0,3 s (tức là 1 trên 3 lượt dò, hoặc 1 trên 18 khung hình ở nhánh
  // dò mỗi khung) vẫn giữ tâm ngắm ở hình "đã khoá" LIÊN TỤC, trong khi phần
  // lớn cú bấm rơi vào những khoảnh khắc tia đang trượt.
  //
  // Đó chính là cảnh máy thật báo về: iPhone 16 Plus (không LiDAR) đo mép bàn
  // trên tấm lót chuột đen phẳng — 130 giây cho điểm thứ nhất, 136 giây cho
  // điểm thứ hai. Người dùng thấy dấu khoá nên bấm, bấm thì trượt, thấy dấu
  // khoá nên bấm lại. Cái nhấp nháy mà hằng số kia đi chữa là THÔNG TIN: nó nói
  // đúng rằng chỗ này chỉ bám được từng lúc.
  //
  // Thứ thay thế nó nằm ở [refreshAimTarget]: cờ lấy MẪU trên lưới
  // [aimProbeIntervalSeconds], và mẫu là kết quả của một lượt raycast thật chứ
  // không phải một lời hứa đã hết hạn còn được gia hạn.

  // MARK: - Hình nón đếm điểm đặc trưng

  /// Nửa góc mở của hình nón quanh tia ngắm, độ.
  ///
  /// **Vì sao một hình NÓN, không phải một hình trụ quanh tia.** Tâm ngắm là
  /// một hình có cỡ cố định trên MÀN, nên "quanh tia ngắm" là một vùng lân cận
  /// theo GÓC, không theo mét: cùng một mảng bề mặt chắn ít góc hơn khi lùi ra
  /// xa, và cảm giác "nằm dưới tâm ngắm" của người dùng đi theo góc chứ không
  /// theo bề rộng thật.
  ///
  /// **Vì sao 10° chứ không phải cỡ của chính tâm ngắm.** Ống kính góc rộng sau
  /// của máy iOS phủ khoảng 60° theo cạnh dài khuôn hình; trên một màn rộng cỡ
  /// 400 pt thì đó là chừng 7 pt cho mỗi độ, nên hình tâm ngắm (vài chục pt)
  /// chắn chưa tới 5°. Một nón bằng đúng tâm ngắm sẽ trả lời câu "ngay dưới
  /// tâm ngắm có gì không" — mà `.estimatedPlane` của ARKit đã trả lời rỗng,
  /// nên đếm lại là ghi cùng một câu trả lời ra lần thứ hai. Phép khớp mặt
  /// phẳng KHÔNG cần điểm nằm dưới tâm ngắm; nó cần điểm nằm trên CÙNG MỘT bề
  /// mặt ở gần đó. Nón vì thế cố ý rộng hơn tâm ngắm.
  ///
  /// **10° là con số làm cho số KHÔNG trở nên dứt khoát.** Đây là một phép đo
  /// để quyết định bỏ hay theo, và nhánh rẻ nhất là nhánh bỏ. Với nón hẹp, một
  /// kết quả 0 còn mơ hồ — nguyên liệu có thể nằm ở 6°. Với nón rộng, 0 nghĩa
  /// là quanh tia thật sự không có gì, và ý tưởng RANSAC chết ngay tại đó
  /// không cần dựng thêm một dòng nào.
  ///
  /// Cái giá của bề rộng ấy phải nói thẳng: ở cự ly làm việc 0,3–1,5 m nón phủ
  /// một mảng bán kính 0,05–0,26 m — đúng cỡ mặt bàn người ta ngắm — nhưng ở
  /// đầu xa của cửa sổ (3 m) nó đã phủ bán kính 0,53 m. Nên một con số CAO chưa
  /// chứng minh nguyên liệu nằm trên bề mặt đang ngắm; nó chỉ nói "chưa được
  /// loại trừ". Một con số THẤP thì kết luận được ngay.
  ///
  /// Chọn theo lập luận trên, chưa nghiệm thu trên máy thật.
  private static let featureConeHalfAngleDegrees: Double = 10

  /// Cửa sổ khoảng cách của phép đếm, mét.
  ///
  /// Nón dựng từ đỉnh camera là VÔ HẠN. Không cắt đầu xa thì "quanh tia" lặng
  /// lẽ thành "đâu đó theo hướng này", và trong một căn phòng thì bức tường
  /// phía sau chiếm trọn phép đếm — đúng con số nói "có nguyên liệu" trong khi
  /// nguyên liệu nằm cách mặt bàn ba mét. 3 m nằm ngoài tầm làm việc của app
  /// (một khung cửa nhìn từ bên kia phòng nhỏ) và nằm trong lòng một phòng ở
  /// bình thường.
  ///
  /// Đầu gần cắt vì chất lượng chứ không vì hình học: điểm đặc trưng thô dựng
  /// bằng phép tam giác theo thời gian, và ở cự ly rất gần thì đường đáy quá
  /// ngắn nên toạ độ trả về phần lớn là nhiễu. Không có gì trong app này đo từ
  /// 20 cm.
  private static let featureRangeNearMeters: Float = 0.2
  private static let featureRangeFarMeters: Float = 3

  /// Hai con số của một lượt đếm. Xem [makeFeatureCensus].
  private struct ArFeatureCensus: Equatable {
    /// Tổng số điểm trong đám mây thô của khung hình này.
    let total: Int

    /// Bao nhiêu trong số ấy nằm trong hình nón quanh tia ngắm.
    let nearRay: Int

    var payload: [String: Any] { ["total": total, "nearRay": nearRay] }
  }

  // MARK: - Thấu kính

  /// Tiêu cự tính bằng ĐIỂM ẢNH, kèm đúng khuôn hình mà nó được biểu diễn trên
  /// đó. Cả hai đọc từ CÙNG một `ARCamera`, trong cùng một lời gọi.
  ///
  /// Có mặt vì app cần một mẫu số: số hạng dung sai của một phép đo AR là
  /// `ε = d · Δu / (fx · sin θ)`. Gói dừng ở việc trả `fx` và `θ` — nó không
  /// tính `ε`, không biết `Δu`, không đặt ngưỡng nào. Cùng ranh giới với
  /// `overshootMm`.
  ///
  /// **Vì sao không nhét vào [videoFormat].** Khối kia đọc `config.videoFormat`
  /// đúng một lần tại `run` — khuôn được XIN. Khối này đọc `ARFrame.camera` —
  /// khuôn đang CHẠY, và là hệ toạ độ điểm ảnh mà `intrinsics` được biểu diễn
  /// trên đó. ARKit không hứa hai thứ ấy bằng nhau, và `fx` còn nhúc nhích theo
  /// lấy nét tự động trong khi khuôn đứng im cả phiên. Trộn chúng là đọc `fx`
  /// trên một bề rộng không phải bề rộng của nó — một phép chia sai mà kết quả
  /// vẫn là một con số milimét bình thường.
  private struct ArCameraIntrinsics {
    /// `ARFrame.camera.intrinsics[0][0]`. Dương, hữu hạn, hoặc `nil`.
    ///
    /// Cột 0 hàng 0 của ma trận nội tại LÀ `fx`. `[0][1]` là hệ số xiên (gần
    /// như luôn bằng 0) và `[1][1]` là `fy` — trên máy iOS hai tiêu cự gần bằng
    /// nhau, nên nhầm cột vẫn cho ra một con số đúng cỡ.
    ///
    /// `0` không đi ra kênh: nó không phải một sự thật ("thấu kính dài không
    /// điểm ảnh" là một câu vô nghĩa), và nó hỏng ở chỗ nguy hiểm nhất — dưới
    /// gạch chia.
    let fx: Double?

    /// `ARFrame.camera.imageResolution`, tính bằng điểm ảnh.
    let width: Int?
    let height: Int?

    init(camera: ARCamera) {
      let rawFx = Double(camera.intrinsics[0][0])
      fx = (rawFx.isFinite && rawFx > 0) ? rawFx : nil

      // `isFinite` trước `Int(...)`, không chỉ `> 0`: `Int(CGFloat.infinity)`
      // là một lượt bẫy (trap) chứ không phải một giá trị lạ, và gói này không
      // được phép ném.
      let size = camera.imageResolution
      width = (size.width.isFinite && size.width > 0) ? Int(size.width) : nil
      height = (size.height.isFinite && size.height > 0) ? Int(size.height) : nil
    }

    var payload: [String: Any] {
      var map: [String: Any] = [:]
      if let fx { map["fx"] = fx }
      if let width { map["width"] = width }
      if let height { map["height"] = height }
      return map
    }
  }

  // MARK: - Trạng thái

  /// Hai điểm đã chấm, theo thứ tự chấm. Nhiều nhất hai.
  private var anchors: [ARAnchor] = []

  /// Điều kiện lúc chấm, khoá theo `identifier` của anchor.
  ///
  /// Khoá theo id chứ KHÔNG theo chỉ số của [anchors], vì chỉ số không sống nổi
  /// qua hai đường đã có sẵn trong lớp này: [adoptUpdatedAnchors] thay ĐỐI
  /// TƯỢNG anchor mỗi lượt ARKit chỉnh hệ toạ độ (id giữ nguyên), và
  /// `didRemove` bỏ một anchor ở giữa. Cả hai làm lệch một ánh xạ theo chỉ số
  /// mà không có lỗi nào nổ — chẩn đoán của điểm 1 gắn sang điểm 2, và số in ra
  /// vẫn trông hợp lý.
  ///
  /// Map thì KHÔNG có thứ tự, nên thứ tự trong mẫu luôn đọc từ [anchors] —
  /// xem [publish].
  private var pointDiagnostics: [UUID: ArPointDiagnostics] = [:]

  /// Mốc thời gian của lời gọi `session.run(...)` gần nhất. `nil` là chưa chạy.
  ///
  /// Neo vào `run` chứ không vào `init`: `reset()` và lượt bỏ cuộc nối lại vị
  /// trí đều dựng lại hệ toạ độ từ đầu, và tuổi phiên phải đếm lại từ đó thì
  /// mới nói được gì về "máy chưa ấm".
  private var sessionStartedAt: TimeInterval?

  /// Trạng thái bám gần nhất ARKit báo. `nil` là chưa có callback nào.
  private var trackingState: ARCamera.TrackingState?

  /// Đã từng bám được lần nào chưa.
  ///
  /// `.notAvailable` **trước** lần bám đầu tiên là "đang khởi động", sau đó mới
  /// là "mất bám". Không phân biệt thì T8 chớp lên ngay lúc mở camera.
  private var hasTrackedOnce = false

  /// Lỗi dính: ARKit đã dừng phiên, chỉ `reset()` mới gỡ.
  private var failure: ArMeasureStatus?

  /// Lỗi đang dính có gỡ được không. Chỉ có nghĩa khi [failure] khác `nil`.
  ///
  /// `unsupportedConfiguration` và `sensorUnavailable` (và cả máy không chạy
  /// nổi `ARWorldTrackingConfiguration`) là hỏng VĨNH VIỄN: không lượt rê máy
  /// nào gỡ được, và `reset()` chỉ dựng lại đúng cái lỗi ấy. Gộp chúng vào
  /// `trackingLost` trần thì màn mời người dùng "rê máy chậm và đều" mãi mãi.
  private var failureIsRecoverable = true

  private var isPaused = false
  private var isInterrupted = false
  private var isStopped = false

  private var relocalizationWatch: DispatchWorkItem?
  private var trailingEmit: DispatchWorkItem?

  /// Tia bắn từ tâm ngắm ĐANG trúng gì. `nil` là không trúng gì cả.
  ///
  /// Đây là thứ duy nhất nói trước cho người dùng biết cú bấm sắp tới sẽ đặt
  /// được điểm hay rơi vào chỗ trống — và nói ở BA mức, không phải hai: trúng
  /// mặt phẳng đã xác nhận, trúng mặt phẳng ARKit vừa đoán ra, không trúng gì.
  /// Cờ `aimLocked` cũ suy ra từ đây (`!= nil`), nên hai thứ không thể lệch.
  /// Xem [refreshAimTarget].
  private var aimTarget: ArRaycastTarget?

  /// Quãng vượt biên của tia ĐANG ngắm, mm. `nil` ở mọi tầng trừ ngoại suy.
  ///
  /// Lấy mẫu CÙNG lượt, CÙNG lưới nhịp với [aimTarget], và phải thế: hai thứ
  /// này đọc chung một câu — "đang ngắm vào chỗ suy ra, và suy ra xa ngần này".
  /// Câu ấy chỉ đúng khi cả hai nói về cùng một lượt raycast.
  private var aimOvershootMm: Double?

  /// Góc của tia ĐANG ngắm so với mặt phẳng nó trúng, độ. `nil` là không trúng
  /// gì — không có mặt phẳng nào để đo góc so với nó.
  ///
  /// Lấy mẫu CÙNG lượt, CÙNG lưới nhịp với [aimTarget] và [aimOvershootMm], và
  /// phải thế: ba con số đọc chung một câu về một lượt bắn.
  ///
  /// **Khác cái van ở một chỗ, và chỗ ấy là lý do trường này tồn tại riêng**:
  /// van chỉ có nghĩa ở tầng ngoại suy, còn góc có nghĩa ở MỌI tầng. Một tia
  /// sượt 4° vào một mặt phẳng ARKit đã xác nhận vẫn là một tia sượt 4°, và
  /// dung sai của nó nở ra đúng như thế — `sin θ` nằm ở mẫu số của số hạng dung
  /// sai mà app dựng lên. Gộp góc vào lối gác của van là tắt cảnh báo sượt ở
  /// đúng cái tầng người ta tin nhất.
  private var aimRayAngleDeg: Double?

  /// Định danh mặt phẳng tia ĐANG ngắm trúng. `nil` là không có mặt phẳng nào —
  /// tia trượt, hoặc trúng một mặt ƯỚC LƯỢNG.
  ///
  /// Lấy mẫu CÙNG lượt, CÙNG lưới nhịp với ba trường trên: bốn thứ chỉ có nghĩa
  /// khi chúng nói về cùng một lượt raycast.
  ///
  /// **Khác cái van, và khác cả góc**: van chỉ có nghĩa ở tầng ngoại suy, góc
  /// có nghĩa ở mọi tầng CÓ mặt phẳng, còn định danh có nghĩa ở đúng những tầng
  /// có `ARPlaneAnchor` — tức là hai tầng, không phải ba. Tầng ước lượng không
  /// neo mặt phẳng nó vừa đoán ra vào đâu cả, và `nil` ở đó là sự thật.
  ///
  /// Xem [planeId(of:)] để biết vì sao nó là định danh LÚC BẮN.
  private var aimPlaneId: String?

  /// Lần LẤY MẪU cờ ngắm gần nhất, để giãn nhịp đổi hình tâm ngắm.
  ///
  /// Mốc RIÊNG, không mượn [lastAimProbeAt]: ở nhánh đang có đoạn thẳng sống,
  /// [probeReticle] dò mỗi khung hình và nhích mốc kia theo từng khung, nên
  /// mượn nó là cửa sổ không bao giờ đóng — tức là tâm ngắm đổi hình 60
  /// lần/giây.
  private var lastAimSampleAt: TimeInterval = 0

  /// Lần dò gần nhất CHẠY, để giãn nhịp dò.
  private var lastAimProbeAt: TimeInterval = 0

  /// Đầu SỐNG của đoạn thẳng — vị trí tia tâm ngắm đang trúng, đã lọc theo
  /// thời gian. Xem [LivePointFilter].
  ///
  /// Nó KHÔNG bị lưới lấy mẫu 10 Hz của [aimTarget] chặn, và không được bị:
  /// tầng nói một TRẠNG THÁI ("bấm được rồi"), còn cái này nói một VỊ TRÍ, và
  /// một vị trí lấy mẫu ở 10 Hz thì giật sáu khung một bước.
  ///
  /// **Nhưng nó cũng không còn là tia THÔ của từng khung, và đó là lượt sửa của
  /// `0.9.1`.** Bản trước ghi thẳng kết quả raycast vào đây và xoá ngay ở lượt
  /// trượt đầu tiên, với lý lẽ "giữ lại vị trí cũ dù chỉ một nhịp là vẽ một
  /// đoạn thẳng tới chỗ không còn gì". Lý lẽ ấy đúng cho một quãng DÀI và sai
  /// cho một khung: trên máy thật, chuỗi trúng-trượt xen kẽ ở 60 khung/s không
  /// đọc ra "tia đang trượt" mà đọc ra một cái NHÁY ở đúng đầu mút. Quãng ôm
  /// 100 ms của bộ lọc nuốt cái nháy ấy và vẫn buông trước khi mắt kịp đọc đoạn
  /// thẳng thành "đã chấm xong".
  ///
  /// [probeReticle] là chỗ DUY NHẤT bơm mẫu vào bộ lọc này; [clearAnchors] là
  /// chỗ duy nhất buông cứng.
  private var livePoint = LivePointFilter()

  /// Quãng NẮM đang mở, hoặc `nil` khi không có gì trong tay.
  ///
  /// Bộ lọc RIÊNG, không dùng chung với [livePoint], và đó không phải một lượt
  /// dọn cho gọn: hai thứ ấy sống cùng lúc được. Đầu sống của đoạn thẳng chạy
  /// khi có ĐÚNG một điểm, còn một điểm đã chấm là một điểm nắm được — nên
  /// `grabPoint(at: 0)` lúc đầu B còn sống là một cảnh hợp lệ, và ở đó hai bộ
  /// lọc nhận cùng một mẫu nhưng KHÁC luật buông: đầu sống hết hạn ôm sau 100
  /// ms, đầu đang nắm thì không bao giờ.
  private var drag: ArDragState?

  /// Phép đếm điểm đặc trưng của khung hình đã sinh ra lượt lấy mẫu ngắm gần
  /// nhất. `nil` là chưa đếm lượt nào, hoặc ARKit không giao đám mây điểm.
  ///
  /// **Đây là một PHÉP ĐO, không phải một tính năng**, và nó phục vụ đúng một
  /// câu hỏi đang treo: khi [raycastFromReticle] trượt liên tục, quanh tia có
  /// nguyên liệu để tự khớp một mặt phẳng hay không. Không có gì trong đây quay
  /// lại đụng vào phép đo khoảng cách, vào tâm ngắm, hay vào cách chấm điểm.
  ///
  /// Ghi ở [refreshAimTarget], cùng lượt và cùng lưới nhịp với [aimTarget]:
  /// hai con số chỉ có nghĩa khi chúng nói về CÙNG một khung hình với tầng tia.
  ///
  /// Chỉ đếm khung hình HIỆN TẠI, không tích luỹ và không giữ lịch sử. Cộng dồn
  /// theo thời gian là một quyết định riêng, và nó chỉ đáng bàn sau khi con số
  /// một-khung nói xong.
  private var featureCensus: ArFeatureCensus?

  /// Khung lớp phủ bắn ra gần nhất — để chặn bắn lại y hệt, và để phát lại cho
  /// người nghe tới muộn.
  private var lastOverlayFrame: [String: Any]?

  /// Mốc lần bắn lớp phủ gần nhất, để giãn nhịp 30 Hz.
  private var lastOverlayEmitAt: TimeInterval = 0

  /// Tấm ảnh dán có đang LẬT nửa vòng hay không.
  ///
  /// Chỗ NHỚ duy nhất của luật trễ ở `LabelPlacement.isFlipped` — hàm ấy thuần,
  /// và trạng thái đi vào rồi đi ra bằng tham số. Một biến nhớ chôn trong hàm
  /// biến nó thành thứ không kiểm được bằng `swiftc`.
  private var labelFlipped = false

  /// Quãng dò để ĐO phép chiếu quanh trung điểm, mét.
  ///
  /// Hai điểm cách trung điểm đúng quãng này theo trục X và trục Y của tấm ảnh,
  /// chiếu xuống màn, cho ra hai thứ không suy được từ đâu khác: **góc màn** của
  /// trục X (đầu vào của phép lật) và **số point mỗi mét** ở đúng khoảng cách ấy
  /// (mẫu số của luật cỡ).
  ///
  /// Đo bằng chính `projectPoint` chứ không suy từ trường nhìn và cỡ khung ngắm:
  /// phép chiếu của view đã gánh sẵn hướng giao diện và tỉ lệ khung, và nó là
  /// con số duy nhất trong tệp này đã được đối chiếu với máy thật (xem
  /// [projectToScreen]). Một công thức dựng tay từ `projectionTransform` phải
  /// đoán lại cả hai thứ ấy, và đoán sai thì chữ lộn ngược ở một hướng cầm máy.
  ///
  /// Hai centimét: ở 3 m nó còn tách ra vài point — đủ để góc và độ dài đọc
  /// được — còn ở cự ly gần thì nó vẫn đủ ngắn để phép chiếu chưa kịp cong.
  private static let labelProbeMetres: Float = 0.02

  /// Khuôn hình ARKit đang CHẠY, đã sẵn sàng cho kênh. `nil` là chưa `run` lần
  /// nào. Xem [makeConfiguration] và [runSession].
  private var videoFormat: [String: Any]?

  /// Thấu kính của khung hình gần nhất. `nil` là chưa có khung nào.
  ///
  /// Khác [videoFormat] ở nhịp: khuôn hình đọc MỘT lần tại `run`, còn con số
  /// này đọc lại ở MỖI khung hình — gói bật lấy nét tự động, nên tiêu cự nhúc
  /// nhích theo cự ly lấy nét trong suốt phiên. Xem [ArCameraIntrinsics].
  private var cameraIntrinsics: ArCameraIntrinsics?

  private var lastStatus: ArMeasureStatus?
  private var lastLimitedReason: ArMeasureLimitedReason?
  private var lastAimTarget: ArRaycastTarget?
  private var lastAimOvershootMm: Double?
  private var lastAimRayAngleDeg: Double?
  private var lastAimPlaneId: String?
  private var lastFeatureCensus: ArFeatureCensus?
  /// Đầu mút đang nắm ở lượt bắn TRƯỚC — mốc của bộ nén.
  ///
  /// Mọi đường ĐỔI nó hôm nay đều `publish(force: true)`, nên dòng này trông
  /// thừa. Nó không thừa: "đều force" là một tính chất của SÁU chỗ gọi, không
  /// phải của trường này, và chỗ thứ bảy quên `force` sẽ làm cái nút buông trên
  /// màn đóng băng ở giá trị cũ — một cái nút nói dối, không lỗi nào nổ.
  private var lastGrabbedPointIndex: Int?
  private var lastMm: Double?
  private var lastEmitAt: TimeInterval = 0

  /// Mẫu bắn ra gần nhất, để phát lại cho người nghe tới muộn.
  private var lastSample: [String: Any]?

  // MARK: - Vòng đời

  init(frame: CGRect) {
    sceneView = ARSCNView(frame: frame)
    super.init()

    sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Gói KHÔNG vẽ chữ: mọi con số, mọi nhãn là việc của Flutter. Thứ DUY NHẤT
    // nó vẽ là hai chấm và đoạn nối ([measureNodes]) — vì chỉ tầng này biết
    // chúng nằm đâu trong không gian.
    sceneView.debugOptions = []
    sceneView.automaticallyUpdatesLighting = false
    // Và không dựng node nào cho anchor — xem [ArMeasureNodeSuppressor].
    sceneView.delegate = nodeSuppressor

    // Bề mặt này chỉ để NHÌN. Mọi thao tác — chấm, hoàn tác, đóng — là nút
    // Flutter nằm đè lên trên, nên `ARSCNView` không được nhận cú chạm nào:
    // tắt hẳn tương tác thì `hitTest` của UIKit không bao giờ dừng ở đây và
    // chạm rơi thẳng xuống lớp Flutter.
    //
    // Cái giá: nút "Reset" mà [coachingOverlay] hiện lúc đang nối lại vị trí
    // cũng không bấm được. Chấp nhận có chủ đích — phiên tự bỏ cuộc sau
    // [relocalizationDeadlineSeconds] và app có lệnh `reset` riêng, nên không
    // có đường nào cụt.
    sceneView.isUserInteractionEnabled = false

    sceneView.scene.rootNode.addChildNode(measureNodes.root)

    coachingOverlay.session = sceneView.session
    // `.anyPlane` chứ không `.horizontalPlane`: cấu hình bật dò cả mặt ngang
    // lẫn mặt đứng ([makeConfiguration]), và người đo tường thì mặt ngang
    // không bao giờ tới — hướng dẫn sẽ nhắc mãi một thứ đã không cần nữa.
    coachingOverlay.goal = .anyPlane
    // Apple tự bật lúc phiên chưa sẵn sàng và tự tắt khi dò xong. Không có lối
    // rẽ nào của gói tốt hơn cái đó.
    coachingOverlay.activatesAutomatically = true
    coachingOverlay.frame = sceneView.bounds
    coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    coachingOverlay.isUserInteractionEnabled = false
    sceneView.addSubview(coachingOverlay)

    sceneView.session.delegate = self
    // `ARSession.delegate` là một tham chiếu YẾU, nên dòng trên không dựng vòng.
    sceneView.session.delegateQueue = .main

    start()
  }

  deinit {
    // Lưới an toàn thứ hai, không phải đường chính. iOS không có callback
    // dispose cho platform view — `FlutterPlatformView` chỉ có đúng một phương
    // thức `view()` — nên đường chính là lệnh kênh `dispose` gọi từ
    // `State.dispose()` bên Dart. Nếu Dart quên, engine cũng sẽ thả view ở một
    // lúc nào đó và camera tắt tại đây.
    stopSessionOnly()
  }

  /// Dừng hẳn. Gọi từ lệnh kênh `dispose`.
  func stop() {
    guard !isStopped else { return }
    // Đường buông AN TOÀN, và là đường cuối cùng còn chạy được: sau dòng dưới
    // mọi lệnh đều trả `notReady`. Buông ở đây để điểm được chốt đúng một lần
    // theo đúng một luật, thay vì biến mất cùng phiên.
    releasePoint()
    isStopped = true
    stopSessionOnly()
    output = nil
  }

  /// Phần dừng dùng được cả từ `deinit` (không chạm vào `isStopped`/`output`
  /// để `deinit` không phải giả định gì về thứ tự).
  private func stopSessionOnly() {
    relocalizationWatch?.cancel()
    relocalizationWatch = nil
    trailingEmit?.cancel()
    trailingEmit = nil
    // Gỡ hướng dẫn khỏi phiên TRƯỚC khi dừng phiên: để nguyên thì nó còn theo
    // dõi một phiên đã tắt và tự bật lên trên một bề mặt không còn ai nhìn.
    coachingOverlay.activatesAutomatically = false
    coachingOverlay.setActive(false, animated: false)
    coachingOverlay.session = nil
    sceneView.session.delegate = nil
    sceneView.delegate = nil
    sceneView.session.pause()
  }

  // MARK: - Cấu hình ARKit: MỘT đường cho mọi máy

  /// Không có nhánh riêng cho máy LiDAR.
  ///
  /// Cách chia "máy thường dùng plane, máy LiDAR dùng mesh" là sai: `.mesh` chỉ
  /// **thêm** một nguồn hình học, nó không thay `planeDetection`. Và raycast
  /// phân tầng ở [raycastFromReticle] chạy y hệt trên cả hai loại máy — LiDAR
  /// chỉ đổi *ý nghĩa* của `.estimatedPlane`: cắt vào lưới thay vì cắt vào mặt
  /// phẳng suy từ điểm đặc trưng.
  private func makeConfiguration() -> ARWorldTrackingConfiguration {
    let config = ARWorldTrackingConfiguration()
    config.planeDetection = [.horizontal, .vertical]

    // Đặt TƯỜNG MINH dù đúng bằng mặc định hiện nay của Apple.
    //
    // Đây là cờ duy nhất trong cả cấu hình mà tắt đi thì việc dò khó hẳn lên ở
    // đúng cái tầm gói này đo. Tầm đo là 0,3–3 m; ở đầu gần của tầm ấy, một
    // tiêu cự khoá ở vô cực cho ra ảnh nhoè, và ARKit rút điểm đặc trưng từ ảnh
    // nhoè thì gần như không rút được gì — tức là đúng cái hỏng "bấm mà không
    // có điểm nào" mà bản này đi sửa.
    //
    // Mặc định không phải hợp đồng: nó không nằm trong bất cứ lời hứa nào của
    // Apple, và một dòng ở đây rẻ hơn nhiều so với việc phát hiện ra nó đã đổi.
    config.isAutoFocusEnabled = true

    if #available(iOS 13.4, *),
      ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    {
      config.sceneReconstruction = .mesh
    }

    // Chọn khuôn hình: **nhịp khung cao nhất trước, rồi mới tới điểm ảnh.**
    // Tiêu chí nằm ở `VideoFormatChoice`, không nằm ở đây — xem CHANGELOG
    // 0.9.0 cho lý lẽ, và 0.4.0 với 0.4.1 cho tiêu chí trước nó.
    //
    // Ba câu đủ để không ai đọc nhầm lịch sử này theo bất kỳ chiều nào:
    //
    // * 0.4.0 chọn khuôn NHIỀU ĐIỂM ẢNH NHẤT, dán nhãn phép thử chưa nghiệm
    //   thu, và tự ghi trước điều kiện hoàn nguyên: *nhịp khung tụt mà thời
    //   gian chờ không giảm thì bỏ*. Lượt máy thật: nhịp tụt còn 30, **nhưng
    //   quãng chờ co từ 130 s xuống 7,8 s**. Điều kiện KHÔNG đạt.
    // * Nên lượt này **không phải** hoàn nguyên theo tiêu chí ấy. Nó đổi vì một
    //   triệu chứng MỚI mà tiêu chí ấy không nói tới: đoạn thẳng **giật khi rê
    //   máy**. Đoạn thẳng vẽ trong SceneKit, nên nó chỉ mượt được bằng nhịp
    //   khung — 30 khung/s là 33 ms mỗi bước nhảy.
    // * Và đây KHÔNG phải một kết luận về phân giải. Không ai đo được rằng phân
    //   giải cao phản tác dụng; phép thử 0.4.0 vẫn lẫn biến với lượt sửa tâm
    //   ngắm đi cùng bản dựng. Lượt này chỉ xếp lại thứ tự khi hai thứ cãi nhau.
    //
    // Phép chọn nằm ở một tệp KHÔNG nhập ARKit vì `ARVideoFormat` không dựng
    // được bằng tay và `supportedVideoFormats` là danh sách của cái máy đang
    // chạy — tiêu chí viết thẳng trên nó chỉ kiểm được bằng cách cầm đúng máy
    // có đúng danh sách cần thử. Rút ba con số ra là thứ cho nó một ca kiểm
    // SỐ (`test/video_format_choice_test.dart`), và một ca kiểm đọc-chữ không
    // phân biệt nổi hai tiêu chí này: cùng tên hàm, cùng danh sách vào, và cả
    // hai đều trả về một khuôn có thật của máy.
    //
    // Danh sách RỖNG trả `nil` và `if let` bỏ qua — máy ảo hay một bản iOS sau
    // không khai khuôn nào thì cấu hình giữ nguyên mặc định. Phòng hờ nằm trong
    // chính phép chọn, không phải một nhánh riêng ai đó quên.
    //
    // Chọn ra CHỈ SỐ rồi mới lấy `formats[best]`: tra ngược từ ba con số là mở
    // chỗ cho một lỗi câm, vì hai mục cùng bề ngang, bề cao và nhịp vẫn có thể
    // là hai `ARVideoFormat` khác nhau.
    let formats = ARWorldTrackingConfiguration.supportedVideoFormats
    if let best = VideoFormatChoice.indexOfBest(
      among: formats.map {
        VideoFormatCandidate(
          width: Int($0.imageResolution.width),
          height: Int($0.imageResolution.height),
          fps: $0.framesPerSecond)
      })
    {
      config.videoFormat = formats[best]
    }

    // Có hai cờ nữa trông như "bật cho AR chạy tốt hơn", và cả hai CỐ Ý không
    // được bật — không cái nào chạm tới việc dò mặt phẳng hay việc bắn tia,
    // tức là không cái nào làm tia trúng thêm một lần nào:
    //
    // * `environmentTexturing` dựng probe ánh sáng để vật ảo phản chiếu được
    //   cảnh thật. Gói vẽ đúng hai quả cầu và một hình trụ, tất cả bằng vật
    //   liệu `.constant` KHÔNG nhận đèn (xem `ArMeasureNodes.makeMaterial`) —
    //   không có gì để phản chiếu, và cái giá là bộ nhớ với GPU cho một texture
    //   không ai lấy mẫu.
    //
    // * `frameSemantics` — `.sceneDepth` chỉ MỞ RA `ARFrame.sceneDepth` cho app
    //   tự đọc; raycast của ARKit đã ăn lưới LiDAR qua `sceneReconstruction` ở
    //   trên rồi, và lớp này không đọc bản đồ sâu ở đâu cả.
    //   `.personSegmentation` là che khuất người trước vật ảo — gói không có
    //   vật ảo nào cần che, và nó chạy một mạng phân đoạn mỗi khung hình.
    //
    // Ghi ra đây vì "bật thêm cho chắc" là phản xạ tự nhiên khi tia đang trượt,
    // và `test/native_surface_contract_test.dart` ghim cả hai lại.
    return config
  }

  private func start(options: ARSession.RunOptions = []) {
    guard !isStopped else { return }
    guard ARWorldTrackingConfiguration.isSupported else {
      // Gói không có trạng thái "máy không chạy được ARKit" — app phải hỏi
      // `isAvailable()` TRƯỚC khi dựng view. Tới được đây nghĩa là app bỏ qua
      // bước ấy, và thứ trung thực nhất còn lại là báo mất bám — kèm cờ nói
      // rằng nó VĨNH VIỄN, vì máy này sẽ không bao giờ chạy được ARKit.
      failure = .trackingLost
      failureIsRecoverable = false
      publish(force: true)
      return
    }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      break

    case .denied, .restricted:
      // Không gọi `run` khi biết chắc sẽ bị từ chối: `run` trong tình trạng này
      // cho ra một màn đen câm, còn ARKit thì báo lỗi muộn hơn nhiều.
      //
      // KHÔNG đặt `failureIsRecoverable = false`: `cameraUnauthorized` đã là
      // một trạng thái riêng, và app đã biết chính xác phải làm gì với nó
      // (mở Cài đặt). Cờ ấy chỉ để cứu những lỗi đội lốt `trackingLost`.
      failure = .cameraUnauthorized
      failureIsRecoverable = true
      publish(force: true)
      return

    case .notDetermined:
      // LẦN CHẠY ĐẦU TIÊN trên một máy thật đi qua đúng nhánh này, và bản trước
      // gộp nó chung với `.authorized` rồi gọi thẳng `run`.
      //
      // Gọi thẳng `run` lúc chưa xác định quyền có hiện hộp thoại — ARKit tự
      // xin — nhưng nó bắt việc dựng đường ống camera phụ thuộc vào một lượt
      // cấp quyền xảy ra SAU khi `run` đã chạy. Không có hợp đồng nào của Apple
      // nói ARKit sẽ dựng lại đường ống ấy khi người dùng bấm Cho phép, và
      // không có callback nào của phiên báo là nó đã không dựng: `didFailWith`
      // im, trạng thái bám im. Bề mặt AR thì TRONG SUỐT khi SceneKit chưa vẽ
      // khung nào (đo được: đặt `scene.background.contents` một màu đặc mà
      // không có phiên thì màu ấy KHÔNG hiện) — nên thứ người dùng thấy là nền
      // của chính app họ, và ở app này nền ấy màu đen.
      //
      // Xin quyền TRƯỚC, chạy phiên SAU: sau lời gọi này quyền chỉ còn hai
      // đường, và cả hai đều có đường ra rõ ràng.
      requestCameraAccess(then: options)
      return

    @unknown default:
      break
    }

    runSession(options: options)
  }

  /// Hỏi quyền camera rồi mới chạy phiên.
  ///
  /// Trả lời tới trên một hàng đợi bất kỳ của AVFoundation, nên phải nhảy về
  /// luồng chính: mọi thứ khác trong lớp này chạy ở đó, và không có khoá nào.
  private func requestCameraAccess(then options: ARSession.RunOptions) {
    guard !isRequestingCameraAccess else { return }
    isRequestingCameraAccess = true
    // Trong lúc hộp thoại mở, trạng thái vẫn là `initializing`: chưa từ chối,
    // chưa hỏng, chỉ là chưa chạy. Bắn ra để màn có một khung hình để vẽ thay
    // vì đứng ở "chưa có mẫu nào".
    publish(force: true)

    AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
      // `[weak self]` chứ không phải một tham chiếu mạnh: hộp thoại có thể đứng
      // đó lâu hơn màn AR, và giữ mạnh ở đây là giữ cả `ARSCNView` sống qua
      // lượt người dùng thoát ra.
      DispatchQueue.main.async {
        guard let self, !self.isStopped else { return }
        self.isRequestingCameraAccess = false
        guard granted else {
          self.failure = .cameraUnauthorized
          self.failureIsRecoverable = true
          self.publish(force: true)
          return
        }
        self.runSession(options: options)
      }
    }
  }

  private func runSession(options: ARSession.RunOptions) {
    failure = nil
    failureIsRecoverable = true

    let config = makeConfiguration()
    // Đọc khuôn hình TỪ cấu hình sau khi đã gán, không phải từ khuôn vừa chọn:
    // hai thứ ấy khác nhau đúng ở cái ca đáng quan tâm nhất — danh sách rỗng,
    // phép gán không xảy ra, và máy đang chạy khuôn mặc định. Báo cáo khuôn
    // mình MUỐN thay vì khuôn đang CHẠY là bịa ra bằng chứng cho chính phép thử
    // sinh ra nó.
    let format = config.videoFormat
    videoFormat = [
      "width": Int(format.imageResolution.width),
      "height": Int(format.imageResolution.height),
      "fps": format.framesPerSecond,
    ]

    sceneView.session.run(config, options: options)
    // Mốc tuổi phiên đặt ngay tại đây, cùng lượt với `run`. Xem
    // [sessionStartedAt] vì sao không đặt ở `init`.
    sessionStartedAt = CACurrentMediaTime()
    publish(force: true)
  }

  // MARK: - Lệnh

  /// Chấm một điểm tại con trỏ giữa màn.
  ///
  /// Trả **lý do** chứ không phải một `Bool`, vì cả ba đường "không đặt được
  /// điểm nào" đều có một câu khác nhau để nói với người dùng — xem
  /// [ArMeasurePlaceResult].
  ///
  /// Vì sao là giá trị trả về chứ không phải một trạng thái bắn ra: raycast
  /// trượt **không đổi trạng thái gì cả** — phiên vẫn `ready`, vẫn đúng như một
  /// giây trước. Bắn `ready` thêm một lần nữa để nói "vừa rồi trượt" là gửi một
  /// tin không phân biệt được với một lần bám lại bình thường, và tầng Dart
  /// không có cách nào tách hai chuyện ấy. Giá trị trả về đi thẳng về đúng cú
  /// chạm đã gây ra nó, nên app rung/nháy được ngay tại chỗ.
  func placePoint() -> ArMeasurePlaceResult {
    guard !isStopped else { return .notReady }

    // Thứ tự ba lượt kiểm dưới đây LÀ hợp đồng, vì mỗi lượt sinh ra một lời
    // khuyên khác nhau và chỉ đúng một lời khuyên được nói ra.
    //
    // "Đã đủ hai điểm" đi TRƯỚC "chưa sẵn sàng": khi đã có hai điểm thì việc
    // phải làm là Chốt hoặc Hoàn tác, và câu ấy đúng bất kể ARKit đang bám tốt
    // hay đang rung. Đảo lại thì nửa giây rung tay biến "đã đo xong" thành
    // "chờ phiên bám lại", và người dùng ngồi đợi một thứ đã tới từ lâu.
    guard anchors.count < 2 else { return .alreadyComplete }

    // Cùng lời gác với [movePoint(at:)] và với lượt dò tâm ngắm, qua CÙNG một
    // hàm: tia chỉ có nghĩa khi ARKit đang bám bình thường. `.measured` không
    // tới được đây — lời gác `anchors.count < 2` ở trên đã chặn — nên chỗ này
    // không đổi hành vi; nó chỉ bỏ đi bản chép thứ tư của một luật.
    guard Self.reticleIsMeaningful(currentStatus()) else { return .notReady }
    guard let hit = raycastFromReticle() else { return .missed }
    let transform = hit.result.worldTransform

    // `ARAnchor` chứ không phải `simd_float3` thuần — nhưng KHÔNG phải vì
    // anchor tự đi theo lượt tinh chỉnh. Nó không hứa thế: `transform` là
    // readonly, tài liệu của `ARAnchor` khuyên "nếu vật ảo di chuyển thì bỏ
    // anchor cũ và thêm anchor mới", và mọi chỗ Apple tài liệu hoá việc anchor
    // tự cập nhật đều gọi tên một LỚP CON (`ARPlaneAnchor`, `ARGeoAnchor`).
    //
    // Anchor ở đây làm đúng một việc: nói cho ARKit biết mình quan tâm chỗ
    // này, để nó giữ chỗ ấy qua các lượt chỉnh hệ toạ độ. Còn việc ĐỌC LẠI thì
    // đi đường khác — [session(_:didUpdate frame:)] lấy transform từ chính
    // khung hình, nên nếu ARKit có trao một đối tượng anchor khác thì mình
    // thấy, và nếu nó không trao gì thì cũng không có gì đứng im chờ mãi.
    let anchor = ARAnchor(name: "headless_ar_measure.point", transform: transform)
    anchors.append(anchor)
    // Ghi điều kiện NGAY tại cú bấm, không dựng lại sau. `hit` chỉ sống trong
    // lời gọi này, và trạng thái bám thì đổi trước khi mẫu kế tiếp bắn đi.
    pointDiagnostics[anchor.identifier] = makeDiagnostics(for: hit)
    sceneView.session.add(anchor: anchor)

    publish(force: true)
    return .placed
  }

  /// Dời điểm thứ [index] tới chỗ tia tâm ngắm ĐANG trúng.
  ///
  /// Vì sao lệnh này tồn tại, nguyên văn lượt máy thật: *"khi chọn xong 2 đầu
  /// thì hiện ra nút cộng trừ, tuy nhiên nó gây confuse cho user khi thay đổi
  /// số mà điểm trên màn hình không đổi"*. Một cái nút chỉnh CON SỐ trong khi
  /// HÌNH đứng im là hai lời khai về cùng một đoạn thẳng trên cùng một màn. Lệnh
  /// này đổi chiều nhân quả: người dùng dời cái điểm, và con số đổi VÌ hình đổi.
  ///
  /// **Thứ tự bốn lượt kiểm dưới đây LÀ hợp đồng**, cùng một luật với
  /// [placePoint]: mỗi lượt sinh ra một câu khác nhau và chỉ đúng một câu được
  /// nói ra.
  ///
  /// `noSuchPoint` đi TRƯỚC `notReady` vì cùng lẽ với `alreadyComplete` ở
  /// [placePoint]: "điểm ấy không tồn tại" là một câu về dữ liệu của APP, đúng
  /// bất kể ARKit đang bám tốt hay đang rung. Đảo lại thì nửa giây rung tay
  /// biến nó thành "chờ phiên bám lại", và app đợi một thứ sẽ không bao giờ tới
  /// — chờ bao lâu cũng không làm điểm số 5 mọc ra.
  ///
  /// **Chỉ số hợp lệ là chỉ số trỏ vào một điểm ĐANG CÓ**, không phải "phải đủ
  /// hai điểm". Một điểm thì `0`; hai điểm thì `0` và `1`; chưa chấm gì thì
  /// không chỉ số nào. Gói không biết app bày cái nút dời ra lúc nào, và một
  /// điểm đã chấm là một điểm đã chấm dù đầu kia còn đang chạy theo tâm ngắm.
  ///
  /// **Tia trượt thì KHÔNG đụng gì tới phép đo.** Lời gác raycast đứng trước
  /// mọi phép đột biến, và nó đứng đó có chủ đích: cách viết "gỡ điểm cũ ra rồi
  /// chấm lại" đọc rất tự nhiên và chạy đúng ở mọi lượt trúng, nhưng ở lượt
  /// trượt nó xoá mất một đầu mà người dùng đã chấm đúng — để đổi lấy một thao
  /// tác KHÔNG xảy ra, đúng lúc họ chỉ định nhích nó đi vài milimét.
  ///
  /// **Điểm mới mang lai lịch MỚI, cả khối.** `makeDiagnostics(for:)` chạy trên
  /// lượt trúng NÀY, và khối cũ bị gỡ khỏi map. Không có đường nào chép một
  /// khối chẩn đoán sang khoá khác: một điểm dời sang mặt phẳng khác mà vẫn
  /// khai định danh, tầng tia và van của cú bấm trước làm mọi tín hiệu trung
  /// thực của gói nói dối — và nói dối bằng những con số trông hoàn toàn hợp lệ.
  ///
  /// **KHÔNG đi qua `livePoint`**, y như [placePoint]. Bộ lọc phục vụ một điểm
  /// được VẼ LẠI 60 lần mỗi giây; điểm dời được đặt đúng một lần cho mỗi cú
  /// chạm. Cái giá của bộ lọc là độ trễ (10,8 mm ở nhịp rê 0,48 m/s) — một sai
  /// số hệ thống không có chỗ trong một điểm đã chốt — và quãng ôm 100 ms của
  /// nó còn tệ hơn ở đây: nó sẽ cho một lượt TRƯỢT trả về toạ độ cũ, và lệnh
  /// báo `moved` cho một cú dời chưa xảy ra.
  ///
  /// `ARAnchor` MỚI chứ không sửa anchor cũ tại chỗ: `ARAnchor.transform` là
  /// readonly, và tài liệu của Apple bảo bỏ anchor cũ rồi thêm anchor mới.
  /// Anchor cũ được gỡ khỏi phiên — không gỡ là để lại một anchor mồ côi cho
  /// mỗi lượt dời, và nó tích lại IM LẶNG vì `ArMeasureNodeSuppressor` không
  /// dựng node cho anchor nào.
  ///
  /// Mảng `anchors` được sửa TRƯỚC lời gọi `remove`, cùng lối với [undoPoint]:
  /// `session(_:didRemove:)` sẽ nổ sau đó với định danh CŨ, và lúc ấy định danh
  /// ấy không còn trong mảng nên lượt gọi thành một phép rỗng. Đảo lại là điểm
  /// vừa dời bị chính callback ấy xoá đi.
  func movePoint(at index: Int) -> ArMeasureMoveResult {
    guard !isStopped else { return .notReady }
    // Một lệnh dời trong lúc đang NẮM là app đang đi hai đường cùng lúc. Buông
    // trước, rồi mới dời: bỏ quãng nắm lại phía sau là để đầu mút tiếp tục bám
    // theo tia SAU cú dời, và người dùng thấy điểm mình vừa đặt lại trôi đi.
    releasePoint()
    guard anchors.indices.contains(index) else { return .noSuchPoint }
    guard Self.reticleIsMeaningful(currentStatus()) else { return .notReady }
    guard let hit = raycastFromReticle() else { return .missed }

    replacePoint(at: index, with: hit, diagnostics: makeDiagnostics(for: hit))

    // `force` vì đây là một lượt ĐỔI TRẠNG THÁI, cùng lối với [placePoint] và
    // [undoPoint]: số đo phải đổi NGAY ở cú chạm, không đợi nhịp 15 Hz và không
    // đợi con số nhích quá 0,5 mm. Người dùng vừa dời một đầu mà con số đứng im
    // nửa giây là dựng lại đúng cái hiểu nhầm lệnh này sinh ra để đóng.
    publish(force: true)
    return .moved
  }

  /// Chốt điểm thứ [index] vào chỗ của một lượt trúng, kèm khối lai lịch của
  /// chính lượt ấy.
  ///
  /// **Một hàm, HAI chỗ gọi** — một nhát [movePoint(at:)], và cú buông ở cuối
  /// một quãng kéo ([releasePoint]). Hai bản chép lệch nhau thì một đường gỡ
  /// anchor cũ còn đường kia quên, hoặc một đường thay khối chẩn đoán còn đường
  /// kia để nguyên khối của lần chấm trước — và cả hai hỏng CÂM.
  ///
  /// `ARAnchor` MỚI chứ không sửa anchor cũ tại chỗ: `ARAnchor.transform` là
  /// readonly, và tài liệu của Apple bảo bỏ anchor cũ rồi thêm anchor mới.
  /// Anchor cũ được gỡ khỏi phiên — không gỡ là để lại một anchor mồ côi cho
  /// mỗi lượt chốt, và nó tích lại IM LẶNG vì `ArMeasureNodeSuppressor` không
  /// dựng node cho anchor nào.
  ///
  /// Mảng `anchors` được sửa TRƯỚC lời gọi `remove`, cùng lối với [undoPoint]:
  /// `session(_:didRemove:)` sẽ nổ sau đó với định danh CŨ, và lúc ấy định danh
  /// ấy không còn trong mảng nên lượt gọi thành một phép rỗng. Đảo lại là điểm
  /// vừa chốt bị chính callback ấy xoá đi.
  ///
  /// Lai lịch nhận từ NGOÀI chứ không tự dựng, và đó là cả điểm của tham số
  /// `diagnostics`: ở cú buông, khối đúng là khối đã đo tại khung hình sinh ra
  /// `hit` — không phải khối dựng lại ở lúc buông, khi camera đã ở một tư thế
  /// khác. Xem [ArDragState.diagnostics].
  private func replacePoint(
    at index: Int, with hit: ArSurfaceHit, diagnostics: ArPointDiagnostics
  ) {
    let old = anchors[index]
    let moved = ARAnchor(
      name: "headless_ar_measure.point", transform: hit.result.worldTransform)

    anchors[index] = moved
    pointDiagnostics.removeValue(forKey: old.identifier)
    pointDiagnostics[moved.identifier] = diagnostics

    sceneView.session.remove(anchor: old)
    sceneView.session.add(anchor: moved)
  }

  // MARK: - Nắm, kéo, buông

  /// Mở một quãng NẮM trên điểm thứ [index].
  ///
  /// Từ khung hình kế tiếp, điểm ấy bám theo giao điểm của tia tâm ngắm — mỗi
  /// khung hình, trong CÙNG lượt dò mà tâm ngắm đã chạy ([stepDrag(now:probe:)]).
  /// Không có lượt raycast thứ hai nào, và không có lượt gọi kênh nào: cả quãng
  /// kéo sống ở tầng Swift.
  ///
  /// **Vì sao không để app tự gọi [movePoint(at:)] liên tục.** Nó cho ra đúng
  /// hình ấy trên màn, nên nó không có triệu chứng nào ngoài hoá đơn pin: 30
  /// lượt qua kênh nền mỗi giây, 30 lượt gỡ-và-thêm `ARAnchor` vào phiên ARKit,
  /// và 30 `ArMeasureMoveResult` không ai đọc.
  ///
  /// **Thứ tự bốn lượt kiểm LÀ hợp đồng**, cùng luật với [placePoint] và
  /// [movePoint(at:)]: mỗi lượt sinh một câu khác nhau và chỉ một câu được nói.
  /// `alreadyGrabbing` đi TRƯỚC `noSuchPoint` vì nó là câu đúng hơn về việc
  /// người dùng phải làm tiếp — buông cái đang cầm — và nó đúng bất kể chỉ số
  /// mới trỏ vào đâu.
  func grabPoint(at index: Int) -> ArMeasureGrabResult {
    guard !isStopped else { return .notReady }
    guard drag == nil else { return .alreadyGrabbing }
    guard anchors.indices.contains(index) else { return .noSuchPoint }
    guard Self.reticleIsMeaningful(currentStatus()) else { return .notReady }

    drag = ArDragState(index: index)
    // `force` vì app dựng cả giao diện "đang nắm" trên trường `grabbedPointIndex`
    // của mẫu, và một cái nút buông tới sau nửa giây là một cái nút đọc ra như
    // hỏng.
    publish(force: true)
    return .grabbed
  }

  /// Đóng quãng nắm đang mở và CHỐT điểm.
  ///
  /// **Chốt lượt trúng CUỐI của quãng kéo**, không chốt vệt đã làm mượt mà mắt
  /// vừa nhìn theo, và không bắn một tia mới ở đúng khung hình buông. Ba lối,
  /// và hai lối kia đều hỏng:
  ///
  /// * Chốt vệt đã làm mượt: vị trí và lai lịch lệch nhau đúng bằng độ trễ của
  ///   bộ lọc. Kéo qua ranh giới hai mặt phẳng rồi buông ngay là một điểm ĐỨNG
  ///   trên mặt bàn mà KHAI định danh của sàn — đúng dạng nói dối bằng những
  ///   con số hợp lệ mà cả tầng chẩn đoán sinh ra để chặn.
  /// * Bắn một tia mới ở lúc buông: một khung trượt ở đúng khoảnh khắc ấy vứt
  ///   cả quãng kéo hai giây, và điểm nhảy ngược về chỗ trước khi nắm.
  ///
  /// **Lai lịch là của chỗ CUỐI, cả khối**, và nó được ghi tại chính khung hình
  /// đã đặt điểm tới chỗ ấy — xem [ArDragState.diagnostics]. Dựng lại ở đây là
  /// gán một góc tia chưa ai bắn cho một điểm đã đứng yên.
  ///
  /// `@discardableResult` vì phần lớn chỗ gọi là các đường buông AN TOÀN (dừng
  /// phiên, tạm dừng, gián đoạn, một lệnh khác dời điểm), và ở đó không ai đọc
  /// kết quả — nhưng chúng vẫn phải đi qua đúng hàm này để điểm được chốt đúng
  /// một lần, theo đúng một luật.
  @discardableResult
  func releasePoint() -> ArMeasureReleaseResult {
    guard !isStopped else { return .notReady }
    guard let state = drag else { return .notGrabbing }
    drag = nil

    // Không khung nào trúng trong cả quãng, hoặc điểm đã biến mất giữa chừng
    // (ARKit bỏ anchor): điểm nằm nguyên chỗ cũ, và `unmoved` nói đúng thế.
    // KHÔNG gộp vào `released` — một câu "đã dời" cho một cú dời chưa xảy ra là
    // đúng dạng lời nói dối mà cả họ enum này sinh ra để chặn.
    guard anchors.indices.contains(state.index),
      let hit = state.hit,
      let diagnostics = state.diagnostics
    else {
      publish(force: true)
      return .unmoved
    }

    replacePoint(at: state.index, with: hit, diagnostics: diagnostics)
    publish(force: true)
    return .released
  }

  /// Một bước của quãng kéo: đầu mút đang nắm bám theo lượt dò của khung này.
  ///
  /// **Không bắn tia.** [probeReticle] đã bắn đúng một lần cho khung hình này,
  /// và kết quả truyền vào qua [probe]. Bắn lần thứ hai là hai tia khác nhau
  /// trong cùng một khung: điểm đi tới một chỗ, tâm ngắm hứa một chỗ khác.
  ///
  /// **Tia TRƯỢT thì đầu mút ĐỨNG YÊN** — hàm trả về sớm và không đụng gì.
  /// Nguyên văn lời đặt hàng: *"một cái thước dây không rơi mất đầu khi tay che
  /// mất vạch"*. Đặc biệt KHÔNG gọi `filter.miss(at:)`: quãng ôm của bộ lọc hết
  /// hạn sau 100 ms và trả `nil`, và `nil` ở đây nghĩa là
  /// [position(ofPointAt:)] rơi về vị trí `ARAnchor` CŨ — tức đầu mút nhảy
  /// ngược về chỗ trước khi nắm, giữa lúc tay người dùng vẫn đang giữ nó.
  ///
  /// App KHÔNG mất tin "tia đang trượt": nó đi ra ngoài nguyên vẹn và đúng nhịp
  /// qua `aimTarget`/`aimLocked` — và `measured` nằm trong [reticleIsMeaningful]
  /// từ 0.10.0, nên hai trường ấy còn nói được suốt quãng kéo. Đây là lý do gói
  /// không thêm một trường thứ hai để báo "đang nắm mà tia trượt".
  ///
  /// Trả `true` khi đã bước — chỗ gọi dùng nó để `publish`, vì số đo đổi ở mỗi
  /// bước mà KHÔNG có anchor nào đổi, nên không đường nào khác kích được lượt
  /// bắn ấy. Bộ nén của [publish] vẫn giữ nguyên trần 15 Hz và ngưỡng 0,5 mm.
  private func stepDrag(now: TimeInterval, probe: ArReticleProbe) -> Bool {
    guard var state = drag else { return false }
    guard case .hit(_, let surface, _, _, _, _) = probe else { return false }

    let column = surface.result.worldTransform.columns.3
    state.filter.hit(
      SIMD3<Float>(column.x, column.y, column.z), at: now)
    state.hit = surface
    // Ghi lai lịch ở MỖI bước, không đợi lúc buông — xem [ArDragState.diagnostics].
    state.diagnostics = makeDiagnostics(for: surface)
    drag = state
    return true
  }

  /// Vị trí ĐANG VẼ của điểm thứ [index].
  ///
  /// Một chỗ đọc DUY NHẤT cho cả hình vẽ ([currentMarks]) lẫn con số
  /// ([currentDistanceMm]). Hai phép tra chép tay lệch nhau thì hình bám theo
  /// tia trong khi con số tính trên `ARAnchor` chưa đổi — đúng cái "số và hình
  /// nói hai chuyện khác nhau" mà cả đường dời đầu mút sinh ra để đóng, chỉ lật
  /// ngược chiều.
  ///
  /// Chỉ điểm ĐANG NẮM mới có vị trí che; mọi điểm khác đọc thẳng từ anchor.
  private func position(ofPointAt index: Int) -> SIMD3<Float> {
    if let drag, drag.index == index, let point = drag.filter.point {
      return point
    }
    let column = anchors[index].transform.columns.3
    return SIMD3<Float>(column.x, column.y, column.z)
  }

  /// Bỏ điểm chấm gần nhất. Không có điểm nào thì không làm gì.
  ///
  /// Không trả về gì, khác với [placePoint]: app đã biết nó đang có mấy điểm
  /// (từ chính luồng trạng thái), nên "hoàn tác lúc chưa có điểm nào" là một
  /// chuyện app tự chặn được, còn "raycast trượt" thì không.
  func undoPoint() {
    // Buông TRƯỚC khi bỏ điểm: nếu điểm bị bỏ chính là điểm đang nắm thì chỉ số
    // trong tay trỏ vào một chỗ trống ngay sau dòng dưới, và nếu không phải nó
    // thì quãng nắm vẫn phải kết thúc — người dùng vừa bấm một lệnh đổi danh
    // sách điểm, và giữ tay lại trên một danh sách vừa đổi là giữ một thứ họ
    // không còn đang nhìn.
    releasePoint()
    guard !isStopped, let last = anchors.popLast() else { return }
    pointDiagnostics.removeValue(forKey: last.identifier)
    sceneView.session.remove(anchor: last)
    publish(force: true)
  }

  /// Bỏ hết điểm và dựng lại hệ toạ độ từ đầu.
  func reset() {
    guard !isStopped else { return }
    cancelRelocalizationWatch()
    clearAnchors()
    isInterrupted = false
    isPaused = false
    hasTrackedOnce = false
    trackingState = nil
    failure = nil
    start(options: [.resetTracking, .removeExistingAnchors])
  }

  /// Tạm dừng camera, GIỮ hai điểm.
  func pause() {
    guard !isStopped, !isPaused else { return }
    // Đường buông AN TOÀN. Màn rời khỏi mắt người dùng thì tâm ngắm không còn
    // trong tay họ nữa; giữ quãng nắm qua một quãng không ai điều khiển là để
    // lượt `resume` kéo đầu mút tới một chỗ chưa ai ngắm.
    releasePoint()
    isPaused = true
    cancelRelocalizationWatch()
    sceneView.session.pause()
    publish(force: true)
  }

  /// Chạy lại sau [pause], không xoá gì.
  func resume() {
    guard !isStopped, isPaused else { return }
    isPaused = false
    if !anchors.isEmpty {
      // Giữ `interrupted` cho tới khi ARKit báo bám lại được. Không giữ thì có
      // một quãng — từ lúc `run` tới lúc callback trạng thái đầu tiên tới —
      // mà `trackingState` còn là giá trị CŨ, tức `.normal`, và phiên bắn ra
      // một con số tính trên một hệ toạ độ chưa nối lại xong.
      isInterrupted = true
      beginRelocalizationWatch()
    }
    // KHÔNG `.resetTracking`: chạy lại không kèm cờ ấy thì ARKit cố nối lại
    // đúng hệ toạ độ cũ, và hai điểm còn nguyên chỗ.
    start(options: [])
  }

  /// Phát lại mẫu gần nhất cho một người nghe vừa gắn vào.
  ///
  /// Kênh sự kiện gắn sau khi platform view đã dựng xong, nên không có dòng này
  /// thì màn đứng trắng cho tới lần ARKit đổi trạng thái kế tiếp — có thể là
  /// vài giây.
  /// Dán một tấm ảnh lên đoạn thẳng, hoặc gỡ nó ra khi [png] là `nil`.
  ///
  /// **Gói không biết trên ảnh viết gì**, và đó là ranh giới của kho này chứ
  /// không phải một chỗ chưa làm xong: hệ thiết kế, tệp phông và mọi khái niệm
  /// sản phẩm nằm ở app. Gói nhận một tấm ảnh cùng tỉ lệ điểm ảnh của nó, rồi
  /// dán lên một node nằm giữa đoạn — xem `LabelPlacement`.
  ///
  /// [pixelRatio] là số điểm ảnh trên một point của tấm ảnh (2 hay 3 trên máy
  /// Retina). Nó vào thẳng `UIImage(data:scale:)`, nên `image.size` sau đó đã là
  /// POINT — và cỡ point mới là thứ luật cỡ nói chuyện. Truyền 1 cho một ảnh
  /// `@3x` là dán một tấm ảnh to gấp ba trên màn.
  ///
  /// Không bao giờ ném. Ảnh không giải mã được thì nhãn ĐANG CÓ còn nguyên —
  /// gỡ nó là để một lỗi dựng ảnh nhất thời xoá mất con số trên màn.
  func setLabel(png: Data?, pixelRatio: Double) -> ArMeasureLabelResult {
    guard !isStopped else { return .notReady }

    guard let png, !png.isEmpty else {
      measureNodes.setLabel(image: nil)
      return .ok
    }

    let scale = pixelRatio.isFinite && pixelRatio > 0 ? CGFloat(pixelRatio) : 1
    guard let image = UIImage(data: png, scale: scale) else { return .badImage }

    measureNodes.setLabel(image: image)
    return .ok
  }

  func replayLastSample() {
    guard !isStopped else { return }
    if let sample = lastSample {
      output?.arMeasureSession(self, didProduce: sample)
    } else {
      publish(force: true)
    }
  }

  // MARK: - Chụp khung hình

  /// Ghi ảnh của CẢNH hiện tại ra một tệp JPEG trong thư mục TẠM, và trả đường
  /// dẫn của nó. Không có gì để ghi thì trả `nil`.
  ///
  /// **Ảnh của CẢNH, không phải khung camera thuần.** Đây là một lượt LẬT so
  /// với 0.3.0–0.12.0, và lý do lật nằm ở chỗ khác đã đổi: đường kẻ, hai chấm
  /// và viên số nay đều là node trong cảnh này. Nên `snapshot()` cho ra đúng
  /// thứ người dùng vừa nhìn **theo định nghĩa**, chứ không theo một phép dựng
  /// lại ở tầng Dart từ toạ độ đã chiếu.
  ///
  /// Lý lẽ cũ — "khung phải THUẦN vì con số nằm ở lớp phủ Dart" — chết cùng
  /// lúc với lớp phủ ấy. Nó để lại một bản cài THỨ HAI của cùng một phép vẽ ở
  /// app, với bộ lỗi riêng và với ca kiểm sinh ra chỉ để canh hai bản không
  /// trôi khỏi nhau.
  ///
  /// **Ba thứ KHÔNG lọt vào ảnh, và cả ba vì cùng một lẽ.** Hồng tâm và vành
  /// sáng đầu mút do app vẽ ở tầng Flutter; hướng dẫn quét bề mặt
  /// (`ARCoachingOverlayView`) là một **subview** của `sceneView`. `snapshot()`
  /// dựng CẢNH qua bộ dựng hình của SceneKit và không đi qua `drawHierarchy`,
  /// nên cây UIView nằm ngoài khuôn ảnh. Cảnh chỉ chứa `measureNodes.root`.
  ///
  /// **Cỡ ảnh đổi, và đó là một đánh đổi đã chốt.** `snapshot()` dựng ở cỡ
  /// KHUNG NGẮM nhân hệ số điểm ảnh của view — chừng 3,6 triệu điểm ảnh trên
  /// một iPad @2x, thay cho 8,3 triệu của khuôn hình camera. Đổi lấy đúng thứ
  /// đang thấy. Và tỉ lệ point → điểm ảnh giữ nguyên như cũ, nên toạ độ mà
  /// kênh lớp phủ bắn ra (point) vẫn quy sang toạ độ ảnh bằng đúng một phép
  /// nhân.
  ///
  /// **Luồng chính.** `SCNView.snapshot()` đọc thẳng bộ dựng hình của view.
  /// Gọi từ luồng khác không ném lỗi nào — nó trả một tấm ảnh đen, hoặc phá
  /// lượt dựng hình đang chạy.
  func captureFrame() -> String? {
    if Thread.isMainThread { return captureSceneOnMain() }
    return DispatchQueue.main.sync(execute: captureSceneOnMain)
  }

  /// Thân của [captureFrame], đã đứng trên luồng chính.
  private func captureSceneOnMain() -> String? {
    // `currentFrame` là cổng LIVENESS, không phải nguồn điểm ảnh: phiên chưa
    // chạy thì `snapshot()` vẫn trả về một tấm ảnh — đen kịt — và một tệp đen
    // trông y hệt một tệp thật cho tới lúc mở ra xem.
    guard !isStopped, sceneView.session.currentFrame != nil else { return nil }

    let viewport = sceneView.bounds.size
    guard viewport.width > 0, viewport.height > 0 else { return nil }

    guard
      let image = Self.bakedUp(sceneView.snapshot()),
      let data = Self.jpegData(from: image)
    else { return nil }

    // Thư mục TẠM, và tên ngẫu nhiên. Gói không biết app muốn cất ảnh ở đâu,
    // cũng không biết app muốn đặt tên thế nào — chỗ lưu thật và cái tên mang
    // mốc thời gian là việc của app, và app phải xoá tệp này sau khi hợp ảnh.
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ar-frame-\(UUID().uuidString).jpg")
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      // Không ném: đây là giá trị trả về của một cú bấm nút.
      return nil
    }
    return url.path
  }

  /// Dựng một lần rồi dùng lại: `CIContext` mang theo cả một đường ống Metal,
  /// và dựng nó ở mỗi cú bấm là một quãng khựng nhìn thấy được.
  private static let renderContext = CIContext(options: nil)

  /// Nướng hướng của một `UIImage` vào điểm ảnh và trả `CGImage` của nó.
  ///
  /// `snapshot()` trả `.up` trên mọi máy đã thử, nên nhánh thứ hai gần như
  /// không chạy. Nó vẫn phải có: một `UIImage` mang hướng khác đi thẳng qua
  /// `.cgImage` là **rụng mất phép xoay** — ảnh vẫn ra, vẫn đúng tỉ lệ, chỉ
  /// nằm nghiêng. Đây đúng là dạng hỏng mà luật "không dựa cờ EXIF" nhắm tới,
  /// chỉ khác cửa vào.
  ///
  /// `format.scale = image.scale` chứ không để mặc định: mặc định của
  /// `UIGraphicsImageRendererFormat()` lấy hệ số của MÀN CHÍNH, không lấy của
  /// tấm ảnh.
  private static func bakedUp(_ image: UIImage) -> CGImage? {
    if image.imageOrientation == .up { return image.cgImage }

    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    format.opaque = true
    return UIGraphicsImageRenderer(size: image.size, format: format)
      .image { _ in image.draw(at: .zero) }
      .cgImage
  }

  /// Nén JPEG. Không đổi cỡ, không xoay — cả hai đã xong trước khi vào đây.
  private static func jpegData(from image: CGImage) -> Data? {
    let ci = CIImage(cgImage: image)
    guard !ci.extent.isEmpty else { return nil }

    let space = ci.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
    guard let space else { return nil }
    // KHÔNG truyền `kCGImagePropertyOrientation`: phép xoay đã nằm trong điểm
    // ảnh, và một cờ hướng cộng thêm là một lượt xoay THỨ HAI ở trình xem nào
    // chịu đọc nó.
    return renderContext.jpegRepresentation(of: ci, colorSpace: space, options: [:])
  }

  // MARK: - Raycast phân tầng

  /// Bắn tia từ con trỏ giữa màn.
  ///
  /// Ba tầng, và **thứ tự LÀ hợp đồng**:
  ///
  /// 1. `.existingPlaneGeometry` — điểm nằm trong đa giác biên của một mặt
  ///    phẳng ARKit **đã xác nhận**. Chắc nhất, nhưng chỉ có khi mặt ấy đã dò
  ///    ra tới chỗ đang ngắm.
  /// 2. `.estimatedPlane` — ARKit đoán một mặt phẳng từ hình học quanh tia.
  ///    Trên máy LiDAR tầng này cắt vào lưới thật nên nó chắc hơn hẳn — cùng
  ///    một dòng mã, khác nhau ở dưới.
  /// 3. `.existingPlaneInfinite` — một mặt phẳng đã dò ra, **kéo dài vượt khỏi
  ///    biên của chính nó**. Điểm SUY RA, không phải điểm quan sát được.
  ///
  /// **Tầng ba là một lượt LẬT quyết định.** Bản trước cấm hẳn nó, và lý do ấy
  /// vẫn đúng nguyên văn: nó kéo dài mặt bàn xuyên qua cái iPad và trả về một
  /// điểm ở CAO ĐỘ MẶT BÀN, hoặc chĩa vào tường xa thì trả một điểm đâu đó dọc
  /// mặt sàn kéo dài — "một con số trông bình thường mà sai là dạng hỏng tệ
  /// nhất của gói này". Thứ đổi là ba chữ *trông bình thường*: lượt trúng ở
  /// tầng ba nay **chỉ được nhận khi nó tự khai được** quãng ra ngoài biên, và
  /// quãng ấy đi lên Dart cùng tầng tia. Vài chục mm là mép bàn mà biên chưa
  /// mọc tới; hàng trăm mm tới hàng mét là đúng cảnh hỏng ấy, và nó tự lộ.
  ///
  /// Dữ kiện ép phải lật: trên máy thật, đám mây điểm đặc trưng của cả khung
  /// hình chỉ có 26 điểm, có lúc 2; quanh tia có 1, có lúc 0 (phép đo của
  /// 0.5.0). Không đủ nguyên liệu cho bất kỳ phép khớp mặt phẳng nào, nên lựa
  /// chọn thật không phải "ngoại suy hay đo đúng" mà là "ngoại suy có nhãn hay
  /// không đo được".
  ///
  /// **Thêm vào CUỐI, không đổi hai tầng đầu.** Một mặt phẳng vô hạn trúng ở
  /// gần như mọi hướng, nên đưa nó lên trước là hai tầng kia không bao giờ được
  /// thử tới nữa — cả gói lặng lẽ chuyển sang đo bằng điểm suy ra.
  ///
  /// Trả về CẢ `ARRaycastResult` chứ không phải mỗi `worldTransform`: kết quả
  /// còn chở `target` (tầng nào đã trúng) và `anchor` (mặt phẳng nào, nếu có),
  /// và đây là chỗ DUY NHẤT hai thứ ấy tồn tại. Vứt chúng ở đây thì tầng chẩn
  /// đoán mất đúng hai trường phân biệt "mặt phẳng ARKit đã xác nhận" với "mặt
  /// phẳng nó đoán ra" — mà không lỗi nào nổ, vì mọi thứ còn lại vẫn chạy.
  private func raycastFromReticle() -> ArSurfaceHit? {
    let bounds = sceneView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let reticle = CGPoint(x: bounds.midX, y: bounds.midY)

    let targets: [ARRaycastQuery.Target] = [
      .existingPlaneGeometry, .estimatedPlane, .existingPlaneInfinite,
    ]
    for target in targets {
      guard let query = sceneView.raycastQuery(from: reticle, allowing: target, alignment: .any)
      else { continue }
      guard let hit = sceneView.session.raycast(query).first else { continue }

      // Hai tầng đầu: điểm QUAN SÁT được. Không có biên nào bị vượt, nên `nil`
      // ở đây là một sự thật chứ không phải một chỗ chưa tính.
      if target != .existingPlaneInfinite {
        return ArSurfaceHit(result: hit, overshootMm: nil)
      }

      // Tầng ba chỉ được NHẬN khi nó tự khai được. Ba điều kiện, và trượt bất
      // cứ điều nào thì lượt trúng này bị BỎ — trả về `nil`, tức là một lượt
      // trượt, tức là tâm ngắm nói thẳng "chưa bấm được".
      //
      // Đây cũng là chỗ luật "KHÔNG ngoại suy khi chưa dò được mặt phẳng nào"
      // được thi hành, và nó được thi hành một cách CHÍNH XÁC chứ không gần
      // đúng: không có mặt phẳng thì không có `ARPlaneAnchor` để kéo dài, nên
      // `hit.anchor` rỗng và lượt trúng rơi ngay tại đây. Một lời chặn thứ hai
      // đi đếm mặt phẳng của phiên trước khi bắn vừa tốn hơn vừa nói một câu
      // KHÁC — "phiên có mặt phẳng nào đó" chứ không phải "lượt trúng NÀY có
      // một mặt phẳng để đo biên".
      //
      // Nhận nó với `overshootMm` bằng `nil` là dựng lại đúng cảnh mà bản trước
      // cấm: một điểm suy ra, không nhãn, và không ai biết nó suy ra xa tới đâu.
      let column = hit.worldTransform.columns.3
      guard
        Self.raycastTarget(of: hit) == .existingPlaneInfinite,
        let plane = hit.anchor as? ARPlaneAnchor,
        let overshootMm = PlaneOvershoot.millimetres(
          worldPoint: SIMD3<Float>(column.x, column.y, column.z),
          planeTransform: plane.transform,
          boundaryVertices: plane.geometry.boundaryVertices)
      else { return nil }

      return ArSurfaceHit(result: hit, overshootMm: overshootMm)
    }
    return nil
  }

  // MARK: - Ghi lại điều kiện lúc chấm

  /// Ảnh chụp điều kiện của MỘT cú chấm. Xem [ArPointDiagnostics].
  ///
  /// Chạy đúng một lần cho mỗi điểm, ngay sau khi tia trúng — không phải mỗi
  /// khung hình. Không có gì trong đây quay lại đụng vào phép đo.
  /// Tầng mà một lượt raycast đã trúng, đọc THẲNG từ kết quả.
  ///
  /// Suy từ thứ tự vòng lặp ở [raycastFromReticle] là chép lại một sự thật ARKit
  /// đã nói ra sẵn, và bản chép rời khỏi bản gốc ngay lượt đầu ai đó đổi danh
  /// sách tầng mục tiêu.
  ///
  /// Một hàm dùng chung, không phải hai lượt `switch` chép ra hai chỗ: cùng một
  /// phép dịch phục vụ chẩn đoán của một điểm ĐÃ chấm và tầng của tia ĐANG
  /// ngắm. Hai bản chép lệch nhau thì dải chẩn đoán và tâm ngắm nói hai chuyện
  /// khác nhau về cùng một lượt raycast — và không lỗi nào nổ.
  private static func raycastTarget(of hit: ARRaycastResult) -> ArRaycastTarget? {
    switch hit.target {
    case .existingPlaneGeometry: return .existingPlaneGeometry
    case .existingPlaneInfinite: return .existingPlaneInfinite
    case .estimatedPlane: return .estimatedPlane
    @unknown default: return nil
    }
  }

  /// ĐỊNH DANH của mặt phẳng một lượt raycast đã trúng. `nil` là không có mặt
  /// phẳng nào.
  ///
  /// **Vì sao trường này tồn tại, và vì sao nó không suy được từ thứ đã có.**
  /// Hai cảnh hỏng trên máy thật, cả hai lọt qua sạch chín trường chẩn đoán:
  ///
  /// 1. Điểm cuối lơ lửng trên tường nằm trên mặt phẳng MẶT BÀN kéo dài gần hai
  ///    mét (`overshootMm` +1946), nên `planeAlignment` của nó vẫn `horizontal`
  ///    y hệt điểm đầu.
  /// 2. Điểm bị bắt xuống dưới chân bàn rơi lên mặt SÀN, vì lúc ấy mặt bàn chưa
  ///    được dò. Sàn và mặt bàn ĐỀU ngang.
  ///
  /// Phương giống nhau, tầng giống nhau, bề rộng không nói được gì. Mọi phép
  /// suy từ chúng trả lời "cùng mặt phẳng" ở đúng hai cảnh phải phân biệt.
  ///
  /// **Trả `uuidString` ĐẦY ĐỦ, không rút gọn.** Giá trị này chỉ để SO SÁNH
  /// BẰNG NHAU, nên rút gọn nghe có vẻ vô hại — nhưng thứ mua được là vài chục
  /// byte mỗi mẫu, còn cái giá là một xác suất đụng độ: hai mặt phẳng khác nhau
  /// đọc ra một giá trị, và app kết luận "cùng mặt phẳng" ở đúng chỗ nó phải
  /// kêu. Không lỗi nào nổ, và chuỗi in ra vẫn trông hợp lệ.
  ///
  /// **Là định danh LÚC BẮN, và không đường nào viết lại nó.** ARKit GỘP mặt
  /// phẳng: hai `ARPlaneAnchor` nhập một, anchor bị nuốt đi qua `didRemove`,
  /// nên một định danh lưu từ lúc chấm có thể trỏ vào một mặt phẳng không còn
  /// tồn tại. Gói KHÔNG đuổi theo lượt gộp, và đây là lý do:
  ///
  /// * ARKit không nói mặt phẳng bị nuốt đã nhập vào mặt phẳng NÀO.
  ///   `session(_:didRemove:)` chỉ nói "cái này mất rồi". Dựng lại ánh xạ ấy
  ///   đòi một phép đoán hình học (mặt phẳng sống sót nào bao lấy mặt phẳng
  ///   cũ), và một cú đoán sai in ra đúng chữ "cùng mặt phẳng" mà cả trường này
  ///   sinh ra để chặn — một câu trả lời sai IM LẶNG, tệ hơn hẳn một câu trả
  ///   lời cũ mà trung thực.
  /// * [adoptUpdatedAnchors] KHÔNG cùng một chuyện, và chỗ khác nhau chính là
  ///   lý do: nó thay ĐỐI TƯỢNG anchor cho CÙNG một `identifier` mà chính ARKit
  ///   trao lại — không có phép đoán nào. Đuổi theo lượt gộp là bịa ra một ánh
  ///   xạ danh tính ARKit chưa bao giờ nói.
  /// * Chiều sai cũng khác nhau. Để nguyên thì sau một lượt gộp, hai điểm trên
  ///   thứ vật lý là MỘT mặt bàn có thể khai hai định danh — app báo động nhầm,
  ///   và người dùng thấy được để bỏ qua. Đuổi theo lượt gộp mà đoán sai thì
  ///   app im lặng nói "cùng mặt phẳng", đúng cái hỏng đã xảy ra hai lần trên
  ///   máy thật.
  private static func planeId(of hit: ARRaycastResult) -> String? {
    (hit.anchor as? ARPlaneAnchor)?.identifier.uuidString
  }

  /// Góc giữa một tia ngắm và MẶT PHẲNG nó trúng, độ. `nil` là không đo được.
  ///
  /// Một hàm dùng chung, không phải hai lượt tính chép ra hai chỗ: cùng một
  /// phép đo phục vụ chẩn đoán của một điểm ĐÃ chấm và cảnh báo sượt của tia
  /// ĐANG ngắm. Hai bản chép lệch nhau thì cảnh báo hiện lên ở một góc còn dải
  /// chẩn đoán của đúng cú bấm ấy ghi một góc khác — cả hai đều là số độ hợp
  /// lệ, và không ai soi ra được. Cùng một luật với [raycastTarget(of:)] và với
  /// [PlaneOvershoot].
  ///
  /// `asin` chứ không `acos`: `dot` cho góc so với PHÁP TUYẾN, mà thứ đọc được
  /// bằng mắt — và thứ số hạng dung sai của app cần — là góc so với MẶT PHẲNG.
  /// Hai góc bù nhau, nên nhầm ở đây in 63° ra thành 27°: một con số vẫn hợp
  /// lệ, vẫn nằm trong 0–90, và không có gì nói ra là mình đang đọc nhầm cái
  /// nào.
  ///
  /// Nhận VỊ TRÍ camera chứ không nhận `ARCamera`: phép tính này không cần biết
  /// khung hình nào, và chỗ gọi nào cũng đã có sẵn một vị trí trong tay. Hàm
  /// tĩnh, không đụng trạng thái của phiên.
  private static func rayAngleDeg(
    from cameraPosition: SIMD3<Float>, hitTransform: simd_float4x4
  ) -> Double? {
    let hitColumn = hitTransform.columns.3
    let toHit =
      SIMD3<Float>(hitColumn.x, hitColumn.y, hitColumn.z) - cameraPosition
    let distance = simd_length(toHit)
    guard distance > 0 else { return nil }

    // Trục Y của transform mà raycast trả về LÀ pháp tuyến bề mặt (hợp đồng
    // của `ARRaycastResult`).
    let n = hitTransform.columns.1
    let normal = simd_normalize(SIMD3<Float>(n.x, n.y, n.z))
    let direction = toHit / distance
    let cosToNormal = min(1, max(0, abs(simd_dot(direction, normal))))
    let radians = asin(cosToNormal)
    guard radians.isFinite else { return nil }
    return Double(radians) * 180 / .pi
  }

  private func makeDiagnostics(for hit: ArSurfaceHit) -> ArPointDiagnostics {
    let target = Self.raycastTarget(of: hit.result)

    let hitColumn = hit.result.worldTransform.columns.3
    let hitPosition = SIMD3<Float>(hitColumn.x, hitColumn.y, hitColumn.z)

    var cameraDistanceMm: Double?
    var rayAngleDeg: Double?
    // Đọc khung hình hiện tại rồi THẢ ngay: giữ một `ARFrame` là chặn ARKit
    // giao khung mới. `ARCamera` lấy ra không giữ khung.
    if let camera = sceneView.session.currentFrame?.camera {
      let camColumn = camera.transform.columns.3
      let cameraPosition = SIMD3<Float>(camColumn.x, camColumn.y, camColumn.z)
      let distance = simd_length(hitPosition - cameraPosition)
      if distance.isFinite {
        cameraDistanceMm = Double(distance) * 1000
      }
      // Cùng MỘT phép tính với góc của tia đang ngắm — xem [rayAngleDeg(from:hitTransform:)].
      rayAngleDeg = Self.rayAngleDeg(
        from: cameraPosition, hitTransform: hit.result.worldTransform)
    }

    // Định danh mặt phẳng, qua CÙNG hàm mà tia đang ngắm dùng — không cast lại
    // tại chỗ. Cùng một luật với [raycastTarget(of:)] và [rayAngleDeg]: hai bản
    // chép lệch nhau thì tâm ngắm và dải chẩn đoán khai hai mặt phẳng khác nhau
    // cho cùng một lượt raycast, và cả hai đều là một chuỗi trông hợp lệ.
    let planeId = Self.planeId(of: hit.result)

    var planeAlignment: ArPlaneAlignment?
    var planeWidthMm: Double?
    var planeHeightMm: Double?
    // Không có `ARPlaneAnchor` nghĩa là tia trúng một mặt ƯỚC LƯỢNG. Ba khoá
    // dưới đây vắng mặt trên dây, và Dart đọc ra "không có mặt phẳng".
    if let plane = hit.result.anchor as? ARPlaneAnchor {
      switch plane.alignment {
      case .horizontal: planeAlignment = .horizontal
      case .vertical: planeAlignment = .vertical
      @unknown default: planeAlignment = nil
      }
      if #available(iOS 16.0, *) {
        planeWidthMm = Double(plane.planeExtent.width) * 1000
        planeHeightMm = Double(plane.planeExtent.height) * 1000
      } else {
        // `extent` đã bị Apple đánh dấu lỗi thời từ iOS 16 (cảnh báo lúc dịch
        // là có chủ đích, không phải sót). Deployment target của gói là iOS
        // 13, nên đây là đường DUY NHẤT còn lại cho iOS 13–15.
        planeWidthMm = Double(plane.extent.x) * 1000
        planeHeightMm = Double(plane.extent.z) * 1000
      }
    }

    var sessionAgeMs: Int?
    if let sessionStartedAt {
      sessionAgeMs = Int((CACurrentMediaTime() - sessionStartedAt) * 1000)
    }

    return ArPointDiagnostics(
      target: target,
      tracking: currentTrackingSnapshot(),
      sessionAgeMs: sessionAgeMs,
      cameraDistanceMm: cameraDistanceMm,
      rayAngleDeg: rayAngleDeg,
      planeId: planeId,
      planeAlignment: planeAlignment,
      planeWidthMm: planeWidthMm,
      planeHeightMm: planeHeightMm,
      // Chép LẠI cái van đã tính ở [raycastFromReticle], không tính lần thứ
      // hai: mặt phẳng có thể đã lớn lên hoặc nhập với mặt khác giữa hai lượt,
      // và một con số tính lại từ biên MỚI gán cho một cú bấm CŨ vẫn là một con
      // số milimét trông bình thường.
      overshootMm: hit.overshootMm
    )
  }

  /// Trạng thái bám THÔ của ARKit, không nén qua tám trạng thái sản phẩm.
  ///
  /// [currentStatus] cố ý đổ `.excessiveMotion` và `.insufficientFeatures` vào
  /// chung một `needsMotion`, và đổ `.relocalizing` sang `interrupted` — đúng
  /// cho màn hình, sai cho một lượt điều tra. Ở đây giữ nguyên sáu nhánh.
  private func currentTrackingSnapshot() -> ArTrackingSnapshot? {
    guard let trackingState else { return nil }
    switch trackingState {
    case .normal:
      return .normal
    case .notAvailable:
      return .notAvailable
    case .limited(let reason):
      switch reason {
      case .initializing: return .limitedInitializing
      case .excessiveMotion: return .limitedExcessiveMotion
      case .insufficientFeatures: return .limitedInsufficientFeatures
      case .relocalizing: return .limitedRelocalizing
      @unknown default: return nil
      }
    }
  }

  // MARK: - Tâm ngắm

  /// Dò xem tia từ tâm ngắm đang trúng gì, và ghi lại vị trí trúng.
  ///
  /// Chỗ DUY NHẤT bơm mẫu vào [livePoint]. Hai thứ đọc lượt dò này —
  /// [refreshAimTarget] lấy ra một tầng, [refreshOverlay] lấy ra một vị trí —
  /// nhưng chỉ có MỘT lượt raycast mỗi khung hình, và đó là chủ đích: raycast là
  /// việc thật, không phải đọc một biến.
  ///
  /// Vì sao lớp này cần một lượt dò riêng, tách khỏi lúc bấm: máy thật báo về
  /// một cái nút không làm gì. Người dùng chĩa vào màn iPad đen bóng ở cự ly
  /// gần — bề mặt tệ nhất có thể cho ARKit, phản chiếu và gần như không có điểm
  /// đặc trưng — bấm "Chấm điểm", và không có điểm, không thông báo, không rung.
  /// Tia trượt THẬT, nhưng người dùng không có đường nào biết được chuyện đó:
  /// họ chỉ thấy một cái nút chết. App Measure của Apple giải đúng bài này bằng
  /// cách cho con trỏ tự nói — nó đổi hình khi bắt được bề mặt, và người ta rê
  /// máy tới khi nó khoá rồi mới bấm.
  ///
  /// Dò bằng ĐÚNG [raycastFromReticle] mà [placePoint] dùng, không phải một tia
  /// gần giống. Kết quả này là một lời hứa về cú bấm sắp tới; hai tia khác nhau
  /// là một lời hứa hão, và nó hỏng theo đúng kiểu tệ nhất — tâm ngắm khoá lại,
  /// người dùng bấm, không có gì xảy ra.
  /// `frame` là khung hình ĐÃ sinh ra lượt gọi này, truyền thẳng vào chứ không
  /// đọc lại `session.currentFrame` bên trong: góc tia đo so với tư thế camera,
  /// và nó phải là tư thế của đúng khung hình mà lượt bắn này diễn ra trên đó.
  /// Đọc lại là dựa vào một giả định đúng nhưng không ai canh — rằng ARKit đã
  /// đặt xong khung mới trước khi gọi vào delegate.
  private func probeReticle(now: TimeInterval, frame: ARFrame) -> ArReticleProbe {
    // Ngoài ba trạng thái bám bình thường thì cú bấm tới không đặt nổi điểm nào
    // dù tia có trúng hay không. KHÔNG dò: một lượt raycast ở đây là công đổ đi.
    //
    // `.measured` NẰM TRONG danh sách từ 0.10.0 — xem [reticleIsMeaningful].
    // Lời gác cũ cắt đúng quãng mà `movePoint` cần tâm ngắm nói được nhất.
    let status = currentStatus()
    guard Self.reticleIsMeaningful(status) else {
      // Qua quãng ôm chứ không xoá cứng, và chỗ này là chỗ nó đáng giá nhất:
      // `needsMotion` chớp lên vì nửa giây rung tay, mà rung tay là đúng thứ
      // xảy ra trong lúc rê máy tìm điểm thứ hai. [coordinatesAreTrustworthy]
      // đã cố ý KHÔNG cho `needsMotion` ẩn hình vẽ, vì "cho hình biến mất từng
      // nhịp như thế còn khó đọc hơn" — xoá thẳng ở đây là dựng lại đúng cái
      // nhấp nháy ấy qua cửa sau, cho riêng đầu sống.
      //
      // Quãng ôm 100 ms cố ý KHÔNG phủ nổi một quãng `needsMotion` dài: ở đó
      // đoạn thẳng nên biến mất thật.
      livePoint.miss(at: now)
      return .unavailable
    }

    // Đúng MỘT điểm đã chấm nghĩa là đang có một đoạn thẳng SỐNG trên màn, và
    // đầu kia của nó là chính kết quả tia này. Ở đó nhịp 10 Hz đọc ra một đoạn
    // giật sáu khung một bước, nên lượt dò chạy mỗi khung hình — và CHỈ ở đó.
    // Quãng còn lại, thứ duy nhất tia này nuôi là một cờ boolean, và mắt người
    // không đọc nổi quá mười lần mỗi giây.
    let hasLiveSegment = anchors.count == 1
    // Đang NẮM một đầu mút thì nó cũng là một đầu sống, và nó cần đúng thứ mà
    // nhánh trên cần: mỗi khung hình. Ở `measured` lưới 10 Hz cắt nó xuống sáu
    // khung một bước, và một đầu mút bị kéo mà chỉ nhích 10 lần mỗi giây đọc ra
    // đúng cái "nhích được một khoảng" mà cả cặp lệnh nắm/buông đi bỏ.
    guard hasLiveSegment || drag != nil
      || now - lastAimProbeAt >= Self.aimProbeIntervalSeconds
    else { return .skipped }
    lastAimProbeAt = now

    guard let hit = raycastFromReticle() else {
      // Trượt đi qua quãng ÔM của bộ lọc, không xoá thẳng — xem [LivePointFilter].
      //
      // Bản trước xoá ngay, và lý lẽ của nó vẫn đúng ở chỗ nó nhắm tới: giữ
      // một vị trí cũ LÂU là vẽ một đoạn thẳng tới chỗ không còn gì, đứng yên
      // giữa lúc người dùng vẫn đang rê máy, đọc ra "đã chấm xong". Nhưng một
      // KHUNG không phải một quãng lâu, và cái giá của lời xoá ngay ấy đã được
      // người dùng gọi tên trên máy thật: ở 60 khung/s, chuỗi trúng-trượt xen
      // kẽ đọc ra một cái nháy liên tục ở đầu mút.
      //
      // Cái nháy không nói ra thông tin nào; nó chỉ trông như hỏng. Còn thông
      // tin "tia đang trượt" thì vẫn đi ra ngoài, nguyên vẹn và ĐÚNG NHỊP, qua
      // `aimTarget` ở [refreshAimTarget] — nên quãng ôm này không nuốt mất một
      // lời cảnh báo nào.
      livePoint.miss(at: now)
      return .missed
    }

    let column = hit.result.worldTransform.columns.3
    let point = SIMD3<Float>(column.x, column.y, column.z)
    // Vào bộ lọc, KHÔNG vẽ thẳng: ba tầng tia được thử theo thứ tự, nên hai
    // khung liên tiếp trả về hai BỀ MẶT khác nhau được — và cả hai đều báo
    // "trúng". Điểm nhảy hàng centimét mà không có gì trong `target` bắt buộc
    // phải đổi theo. Phần `point` trả về dưới đây vẫn là mẫu THÔ: nó nuôi tầng
    // chẩn đoán, và một con số chẩn đoán đã làm mượt là một con số nói dối.
    livePoint.hit(point, at: now)

    let camColumn = frame.camera.transform.columns.3
    return .hit(
      point: point,
      // Kết quả THÔ của chính lượt bắn này đi kèm, cho quãng nắm — xem
      // [ArReticleProbe.hit] và [stepDrag(now:probe:)].
      surface: hit,
      target: Self.raycastTarget(of: hit.result),
      overshootMm: hit.overshootMm,
      rayAngleDeg: Self.rayAngleDeg(
        from: SIMD3<Float>(camColumn.x, camColumn.y, camColumn.z),
        hitTransform: hit.result.worldTransform),
      // Định danh của mặt phẳng ĐANG bị ngắm, đọc từ chính lượt bắn này qua
      // cùng một hàm mà `makeDiagnostics` dùng. Hỏi lại ở bước sau là hỏi về
      // một thế giới khác: ARKit có thể đã cho mặt phẳng ấy lớn lên, hoặc đã
      // GỘP nó với mặt khác, giữa hai lượt.
      planeId: Self.planeId(of: hit.result))
  }

  /// Đếm điểm đặc trưng thô của một khung hình: tổng, và số nằm quanh tia ngắm.
  ///
  /// **PHÉP ĐO, không phải một bước của phép đo khoảng cách.** Nó tồn tại để
  /// trả lời một câu hỏi đang treo: cảnh làm [raycastFromReticle] trả `nil`
  /// liên tục — bàn gỗ phủ tấm lót chuột đen phẳng lì, tường trơn, trong nhà
  /// buổi tối — có còn nguyên liệu để tự khớp một mặt phẳng không. Câu hỏi ấy
  /// đáng hỏi vì `.estimatedPlane` VỀ BẢN CHẤT đã là "khớp mặt phẳng từ điểm
  /// đặc trưng quanh tia", và nó trả rỗng. Nếu quanh tia cũng không có điểm nào
  /// thì không có gì để dựng, và một tầng khớp mặt phẳng tự viết cũng sẽ trả về
  /// đúng cái rỗng ấy, chỉ tốn hơn.
  ///
  /// Trả `nil` khi ARKit không giao đám mây điểm. `nil` và `total: 0` là HAI
  /// chuyện, và cả phép đo nằm ở chỗ phân biệt chúng: `0` là "có đám mây, đám
  /// mây rỗng" — một sự thật đóng được quyết định; `nil` là "không hỏi được".
  /// Đổ chung là xoá đúng câu trả lời.
  ///
  /// Không giữ `frame` lại quá lời gọi này, và không giữ `ARPointCloud`: giữ
  /// một `ARFrame` là chặn ARKit giao khung mới. Chỉ hai `Int` đi ra.
  ///
  /// O(n) với vài phép nhân vô hướng mỗi điểm, n tới hàng nghìn — nên nó phải
  /// chạy trên lưới nhịp của [refreshAimTarget], không phải mỗi khung hình.
  private func makeFeatureCensus(from frame: ARFrame) -> ArFeatureCensus? {
    guard let cloud = frame.rawFeaturePoints else { return nil }
    let points = cloud.points
    guard !points.isEmpty else { return ArFeatureCensus(total: 0, nearRay: 0) }

    let transform = frame.camera.transform
    let originColumn = transform.columns.3
    let origin = SIMD3<Float>(originColumn.x, originColumn.y, originColumn.z)
    // Camera ARKit nhìn theo −Z CỦA CHÍNH NÓ: cột 2 của transform là +Z, nên
    // trục ngắm là cột ấy đảo dấu. Lấy nhầm cột (hay quên dấu trừ) dựng ra một
    // cái nón chĩa đi chỗ khác — nó vẫn đếm ra số, số ấy vẫn đổi khi rê máy, và
    // không có gì trên màn nói rằng nó đang đếm ở một hướng khác hướng ngắm.
    let forwardColumn = transform.columns.2
    let forward = simd_normalize(
      SIMD3<Float>(-forwardColumn.x, -forwardColumn.y, -forwardColumn.z))

    // So `dot(d, forward) >= cos(nửa góc) * |d|` thay vì chia `dot` cho `|d|`:
    // cùng một bất đẳng thức, bớt một phép chia mỗi điểm, và không có đường
    // chia cho không.
    let cosHalfAngle = Float(cos(Self.featureConeHalfAngleDegrees * .pi / 180))

    var nearRay = 0
    for point in points {
      let toPoint = point - origin
      let range = simd_length(toPoint)
      guard range >= Self.featureRangeNearMeters,
        range <= Self.featureRangeFarMeters
      else { continue }
      if simd_dot(toPoint, forward) >= cosHalfAngle * range { nearRay += 1 }
    }

    return ArFeatureCensus(total: points.count, nearRay: nearRay)
  }

  /// Cập nhật [aimTarget] và [featureCensus] theo lượt dò của khung hình này.
  ///
  /// Trả `true` khi một trong hai ĐỔI — người gọi dùng nó để khỏi bắn khi không
  /// có gì mới.
  ///
  /// **Hai thứ, MỘT lượt lấy mẫu, và đó là điều kiện để chúng có nghĩa.** Cả
  /// phép đếm sinh ra để đọc được một câu duy nhất: "tia trượt, mà quanh nó có
  /// bằng này điểm". Câu ấy chỉ đúng khi tầng tia và phép đếm nói về CÙNG một
  /// khung hình. Cho phép đếm một mốc riêng — kể cả một mốc chạy đúng nhịp 10 Hz
  /// ấy — là hai lưới lệch pha, và dải chẩn đoán ghép một lượt trượt của khung
  /// này với một phép đếm của khung khác. Không lỗi nào nổ, và con số đọc ra vẫn
  /// hợp lý.
  ///
  /// **Không có quãng ân hạn nào.** Tầng ở đây LUÔN là kết quả của một lượt
  /// raycast thật, cũ nhiều nhất một nhịp lấy mẫu. Bản trước giữ cờ "đã khoá"
  /// thêm 0,3 s sau lượt trượt đầu tiên và nạp lại quãng ấy ở mỗi lượt trúng,
  /// nên trên một bề mặt chỉ bám được từng lúc, tâm ngắm nói "khoá" liên tục
  /// trong khi phần lớn cú bấm trượt — xem chỗ hằng số ấy từng nằm.
  ///
  /// Thứ duy nhất còn lại là một lưới LẤY MẪU ở [aimProbeIntervalSeconds]. Nó
  /// không kéo dài lời hứa nào; nó chỉ chặn tâm ngắm đổi hình nhanh hơn mắt đọc
  /// được. Lưới ấy cần thiết vì ở nhánh đang có đoạn thẳng sống [probeReticle]
  /// dò MỖI khung hình, và một hình đổi 60 lần mỗi giây thì không đọc ra trạng
  /// thái nào — nhấp nháy ở 10 Hz thì đọc được, và nó là THÔNG TIN: chỗ này chỉ
  /// bám được từng lúc, hãy chĩa sang chỗ khác.
  private func refreshAimTarget(
    now: TimeInterval, frame: ARFrame, probe: ArReticleProbe
  ) -> Bool {
    let wasTarget = aimTarget
    let wasOvershoot = aimOvershootMm
    let wasRayAngle = aimRayAngleDeg
    let wasPlaneId = aimPlaneId
    let wasCensus = featureCensus

    switch probe {
    case .unavailable:
      // Không đợi nhịp nào: trạng thái phiên đã nói thẳng rằng cú bấm tới không
      // đặt nổi điểm nào. Xoá mốc để lượt dò kế tiếp lấy mẫu được ngay.
      //
      // Phép đếm đi cùng: nó là số liệu VỀ một lượt ngắm, và ở đây không có
      // lượt ngắm nào. Giữ con số của lượt trước là để trên dải chẩn đoán một
      // phép đếm gán cho một khoảnh khắc nó không nói về.
      aimTarget = nil
      aimOvershootMm = nil
      aimRayAngleDeg = nil
      aimPlaneId = nil
      featureCensus = nil
      lastAimSampleAt = 0
    case .skipped:
      break
    case .hit(_, _, let target, let overshootMm, let rayAngleDeg, let planeId):
      guard now - lastAimSampleAt >= Self.aimProbeIntervalSeconds else { break }
      lastAimSampleAt = now
      // Trúng mà ARKit trả một tầng lạ (một giá trị thêm ở bản iOS sau) vẫn là
      // TRÚNG: cờ `aimLocked` suy từ `!= nil` nên nó phải khác `nil`. Rơi về
      // `.estimatedPlane` — mức tin cậy THẤP hơn — chứ không phải mức cao: đoán
      // thấp thì cùng lắm là mời người dùng ngắm kỹ hơn, đoán cao là hứa một
      // thứ chưa ai kiểm.
      aimTarget = target ?? .estimatedPlane
      // Van gác theo TẦNG ĐÃ CHỐT ở dòng trên, không theo `target` thô. Ở
      // nhánh tầng lạ vừa nói, tầng chốt lại thành `.estimatedPlane` — và một
      // quãng vượt biên gắn vào một tầng không phải tầng ngoại suy đọc ra một
      // câu vô nghĩa mà vẫn có số.
      aimOvershootMm = aimTarget == .existingPlaneInfinite ? overshootMm : nil
      // Góc thì KHÔNG gác theo tầng, và đó là chỗ nó khác cái van ngay trên:
      // một tia sượt 4° vào một mặt phẳng đã xác nhận vẫn là một tia sượt 4°.
      // Nó chỉ đòi một điều — có trúng một mặt phẳng nào đó để mà đo góc so với
      // nó — và nhánh này chính là nhánh ấy.
      aimRayAngleDeg = rayAngleDeg
      // Định danh cũng KHÔNG gác theo tầng, và cũng khác góc: nó tự vắng mặt ở
      // tầng ước lượng vì tầng ấy không có `ARPlaneAnchor` nào để mà khai tên.
      // Thêm một lời gác theo tầng ở đây là nói cùng một câu hai lần, và lần
      // thứ hai sẽ lệch đi ở lượt đầu ai đó đổi bảng tầng.
      aimPlaneId = planeId
      featureCensus = makeFeatureCensus(from: frame)
    case .missed:
      guard now - lastAimSampleAt >= Self.aimProbeIntervalSeconds else { break }
      lastAimSampleAt = now
      aimTarget = nil
      aimOvershootMm = nil
      aimRayAngleDeg = nil
      aimPlaneId = nil
      // Đếm cả ở nhánh TRƯỢT, và đây mới là nhánh phép đo sinh ra để phục vụ:
      // cảnh đang điều tra là một chuỗi trượt không dứt. Chỉ đếm lúc trúng là
      // đo đúng cái cảnh không cần đo.
      featureCensus = makeFeatureCensus(from: frame)
    }

    // Góc nằm trong phép so này, và nó phải nằm: lượt gọi này là cái quyết định
    // `publish` có chạy hay không, nên một con số không được so ở đây thì bộ nén
    // của `publish` không bao giờ được nhìn thấy nó. Cảnh cụ thể: người dùng
    // đứng yên một chỗ và chỉ NGHIÊNG máy — tầng tia không đổi (vẫn cùng mặt
    // phẳng), van không đổi, trạng thái không đổi.
    // Định danh nằm trong phép so này, và nó KHÔNG thừa dù ba thứ trên đã có
    // mặt. Cảnh cụ thể là chính cảnh hỏng đã đo được trên máy thật: người dùng
    // rê tia từ MẶT BÀN xuống SÀN. Hai mặt phẳng khác nhau, nhưng cả hai đều
    // `horizontal`, cả hai đều ở tầng `existingPlaneGeometry`, van `nil` ở cả
    // hai, và cầm máy cùng một độ nghiêng thì góc tia cũng bằng nhau. Thứ DUY
    // NHẤT đổi là định danh — không so ở đây thì lượt gọi này trả `false`, và
    // `publish` không bao giờ được nhìn thấy nó.
    return wasTarget != aimTarget || wasOvershoot != aimOvershootMm
      || wasRayAngle != aimRayAngleDeg || wasPlaneId != aimPlaneId
      || wasCensus != featureCensus
  }

  // MARK: - Trạng thái và số đo

  private func currentStatus() -> ArMeasureStatus {
    if let failure { return failure }
    if isPaused || isInterrupted { return .interrupted }

    guard let trackingState else { return .initializing }
    switch trackingState {
    case .notAvailable:
      return hasTrackedOnce ? .trackingLost : .initializing
    case .limited(let reason):
      switch reason {
      case .initializing:
        return .initializing
      case .relocalizing:
        return .interrupted
      case .excessiveMotion, .insufficientFeatures:
        // Cả hai đều là "máy đang không cho ARKit thứ nó cần", và cả hai đều
        // gỡ bằng ĐÚNG một hành động: rê máy chậm và đều quanh vật. Trong tám
        // trạng thái đã chốt, đây là chỗ ít sai nhất — `trackingLost` thì kéo
        // cả màn sang T8 vì nửa giây rung tay, mà `.excessiveMotion` tự khỏi
        // ngay khi người ta chậm lại.
        return .needsMotion
      @unknown default:
        return .needsMotion
      }
    case .normal:
      switch anchors.count {
      case 0: return .ready
      case 1: return .firstPointPlaced
      default: return .measured
      }
    }
  }

  /// Một lượt bắn tia từ tâm ngắm CÒN có nghĩa ở trạng thái này hay không.
  ///
  /// Ba trạng thái, và chúng đúng bằng nhánh `.normal` của [currentStatus] —
  /// nói cách khác: **tia chỉ có nghĩa khi ARKit đang bám bình thường**. Ở
  /// `initializing`, `needsMotion`, `interrupted`, `trackingLost` và
  /// `cameraUnauthorized` thì hệ toạ độ chưa hoặc không còn đáng tin, nên một
  /// lượt raycast ở đó là công đổ đi.
  ///
  /// **`.measured` vào danh sách này từ 0.10.0, và đó là một lượt LẬT.** Trước
  /// đó lời gác viết tay ở ba chỗ là `ready || firstPointPlaced`, với lý lẽ "hai
  /// điểm đã đủ thì tâm ngắm hết nghĩa — không còn gì để chấm". Lý lẽ ấy chết
  /// cùng lúc [movePoint(at:)] ra đời: ở `measured` vẫn còn một cú bấm đặt được
  /// một điểm. Để tâm ngắm câm ở đó là bắt người dùng biết mình đang ngắm vào
  /// chỗ trống bằng cách BẤM — đúng cái nút chết mà cờ `aimLocked` sinh ra để
  /// chặn.
  ///
  /// **Một hàm, ba chỗ gọi** — lượt dò ở [probeReticle], lời gác cuối ở
  /// [publish], và chính [movePoint(at:)]. Ba bản chép lệch nhau thì tâm ngắm
  /// khoá trong khi lệnh dời trả `notReady`, hoặc ngược lại: lệnh chạy được
  /// trong khi tâm ngắm nói không có gì để bấm. Cả hai chiều đều là một cái nút
  /// nói dối, và không lỗi nào nổ.
  ///
  /// **Cái giá phải nói thẳng:** ở `measured`, kênh trạng thái từ nay không còn
  /// im. Lượt dò chạy 10 Hz và `makeFeatureCensus` đổi gần như mỗi lượt, nên một
  /// phiên nằm yên ở `measured` bắn tới 10 mẫu/giây thay vì gần như không bắn
  /// gì. Trần vẫn là trần cũ ([aimProbeIntervalSeconds]); thứ đổi là SÀN, và nó
  /// đổi ở một trạng thái mà app hay đứng lâu. Đây là giá của việc tâm ngắm còn
  /// nói được ở đúng quãng người dùng đang chỉnh một đầu mút.
  private static func reticleIsMeaningful(_ status: ArMeasureStatus) -> Bool {
    status == .ready || status == .firstPointPlaced || status == .measured
  }

  /// Lý do phụ đi kèm `needsMotion`. `nil` ở mọi trạng thái khác.
  ///
  /// Cùng một trạng thái, hai lời khuyên ngược nhau — xem [ArMeasureLimitedReason].
  private func currentLimitedReason() -> ArMeasureLimitedReason? {
    guard currentStatus() == .needsMotion else { return nil }
    guard let trackingState, case .limited(let reason) = trackingState else { return nil }
    switch reason {
    case .excessiveMotion:
      return .excessiveMotion
    case .insufficientFeatures:
      return .insufficientFeatures
    default:
      // `.initializing` và `.relocalizing` không bao giờ tới được đây (chúng ra
      // trạng thái khác), và một lý do ARKit thêm sau này thì mình chưa có câu
      // nào đúng để nói — im lặng tốt hơn đoán bừa.
      return nil
    }
  }

  /// Vị trí và LAI LỊCH các điểm đã chấm, theo thứ tự chấm.
  ///
  /// Vị trí đọc từ chính `anchors` — cùng nguồn với [currentDistanceMm], nên
  /// hình vẽ và con số không bao giờ nói hai chuyện khác nhau.
  ///
  /// Lai lịch đọc từ khối chẩn đoán đã ghi NGAY LÚC BẤM, không dò lại bằng một
  /// tia mới: tầng của một điểm chỉ tồn tại trong `ARRaycastResult` của đúng cú
  /// bấm sinh ra nó. Dò lại lúc vẽ là hỏi một câu KHÁC — "chỗ này BÂY GIỜ là
  /// tầng gì" — rồi trả lời nó như thể đó là lai lịch của cú bấm cũ.
  private func currentMarks() -> [ArMeasureMark] {
    anchors.indices.map { index in
      let anchor = anchors[index]
      return ArMeasureMark(
        // Qua [position(ofPointAt:)] chứ không đọc thẳng `anchor.transform`:
        // một điểm ĐANG NẮM nằm ở chỗ tia vừa trúng, không ở chỗ anchor của nó
        // — anchor chỉ được thay ở lúc buông.
        position: position(ofPointAt: index),
        isExtrapolated:
          pointDiagnostics[anchor.identifier]?.target == .existingPlaneInfinite)
    }
  }

  /// Khoảng cách giữa hai điểm, tính bằng milimét. `nil` khi chưa đủ hai điểm.
  ///
  /// Đọc vị trí qua CÙNG hàm mà [currentMarks] dùng. Hai phép tra chép tay lệch
  /// nhau là con số đứng im suốt quãng kéo trong khi hình đã chạy theo tia —
  /// đúng cái hiểu nhầm mà cả đường dời đầu mút sinh ra để đóng, chỉ lật ngược.
  private func currentDistanceMm() -> Double? {
    guard anchors.count == 2 else { return nil }
    return distanceMm(from: position(ofPointAt: 0), to: position(ofPointAt: 1))
  }

  /// Khoảng cách giữa hai điểm bất kỳ, milimét.
  ///
  /// Một hàm chứ không phải hai dòng chép hai chỗ, vì chỗ thứ hai gọi nó là
  /// [refreshOverlay] — con số ĐANG CHẠY dưới nhãn nổi. Hai công thức rời nhau
  /// là hai con số khác nhau về cùng một đoạn thẳng, trên cùng một màn, và
  /// người dùng là người duy nhất thấy chúng cạnh nhau.
  private func distanceMm(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Double {
    Double(simd_distance(a, b)) * 1000
  }

  /// Hệ toạ độ hiện tại còn đáng tin không.
  ///
  /// Ẩn ở đúng ba trạng thái mà nó không còn đáng tin: hai chấm vẫn nằm nguyên
  /// chỗ cũ trong một hệ toạ độ đã trôi thì chúng chỉ vào sai vật, mà trông vẫn
  /// như đang chỉ đúng. `needsMotion` KHÔNG nằm trong danh sách: nó chớp lên vì
  /// nửa giây rung tay, và cho hình biến mất từng nhịp như thế còn khó đọc hơn.
  ///
  /// Một hàm dùng chung cho CẢ hình vẽ 3D lẫn khung lớp phủ. Hai cổng rời nhau
  /// là lúc đoạn thẳng SceneKit biến mất trong khi nhãn Flutter còn lơ lửng
  /// giữa màn với một con số — hoặc ngược lại.
  private func coordinatesAreTrustworthy() -> Bool {
    let status = currentStatus()
    return status != .interrupted && status != .trackingLost
      && status != .cameraUnauthorized
  }

  /// Dung sai ± của một quãng, tính bằng milimét.
  ///
  /// Máy LiDAR đo bằng thời gian bay của ánh sáng nên sai số gần như không phụ
  /// thuộc quãng; máy thường suy quãng từ thị sai giữa các khung hình nên sai
  /// số nở theo quãng. Hai công thức dưới là **giả định**, chốt lại bằng nghiệm
  /// thu trên máy thật — nhưng chúng phải có sẵn ở đây, vì một con số không kèm
  /// dung sai là một lời hứa về độ mịn mà cảm biến không có.
  private func toleranceMm(forMm mm: Double) -> Double {
    var hasSceneDepth = false
    if #available(iOS 13.4, *) {
      hasSceneDepth = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    return hasSceneDepth ? max(2, mm * 0.005) : max(5, mm * 0.015)
  }

  // MARK: - Lớp phủ

  /// Chiếu một điểm thế giới xuống toạ độ MÀN, đơn vị **point**.
  ///
  /// **Không đổi đơn vị ở đây, và lần này là có bằng chứng.**
  /// `SCNSceneRenderer.projectPoint` trả toạ độ theo hệ của **view**, và hệ ấy
  /// ĐÃ là point. Toạ độ đi thẳng ra, không nhân và không chia.
  ///
  /// Từ `0.2.0` tới `0.9.0` chỗ này CHIA cho `contentScaleFactor`, với lý lẽ
  /// "`projectPoint` trả pixel của lớp vẽ". Người viết lượt ấy tự khai là không
  /// chắc và ghi sẵn triệu chứng nếu sai: *"nhãn lệch khỏi đoạn đúng một hệ số
  /// nguyên (2 hoặc 3)"*. Triệu chứng ấy đã tới, trên hai máy, với đúng hai hệ
  /// số ấy:
  ///
  /// * **iPhone 16 Plus (@3x)**, đo trên ảnh chụp màn hình: đường kẻ ở
  ///   `y ≈ 480 pt`, hộp số ở `y ≈ 175 pt`. `480 / 3 ≈ 160`, cộng quãng nhãn
  ///   đặt phía trên đường kẻ (~15 pt), ra đúng 175.
  /// * **iPad Air M3 (@2x)**: nhãn nằm góc trên bên trái trong khi trung điểm
  ///   đoạn ở giữa màn — chia đôi toạ độ giữa màn ra đúng góc phần tư ấy.
  ///
  /// Hai máy, hai hệ số, một công thức. Cả tệp này nay cùng một hệ:
  /// `sceneView.bounds` (tâm ngắm bắn tia) là point, phép chiếu này là point,
  /// và từ `0.13.0` [captureFrame] không đụng tới `contentScaleFactor` nữa —
  /// `SCNView.snapshot()` tự dựng ở hệ số điểm ảnh của view, nên phép đổi đơn
  /// vị point → điểm ảnh nằm trong chính nó chứ không nằm ở một phép nhân tay.
  ///
  /// `nil` khi điểm nằm ngoài khối nhìn — chủ yếu là **sau lưng camera**. Phép
  /// chiếu vẫn trả về một toạ độ x, y trông hoàn toàn hợp lệ cho những điểm ấy:
  /// nó đi qua gốc, nên điểm sau lưng rơi xuống một chỗ đối xứng phía trước, và
  /// không có gì trong hai con số nói ra điều đó. Thứ nói ra là z —
  /// `projectPoint` cho z = 0 ở mặt phẳng cắt gần và z = 1 ở mặt phẳng cắt xa,
  /// nên ngoài [0, 1] là ngoài khối nhìn.
  ///
  /// Toạ độ ÂM thì KHÔNG bị loại: một đầu đoạn thẳng ra ngoài mép màn trong khi
  /// đầu kia còn trong khung là chuyện thường ở tầm đo gần, và đoạn nối tới nó
  /// vẫn cắt qua khung hình. "Ngoài mép màn" và "sau lưng camera" là hai chuyện
  /// khác nhau, và z là thứ duy nhất tách được chúng.
  private func projectToScreen(_ world: SIMD3<Float>) -> CGPoint? {
    let projected = sceneView.projectPoint(SCNVector3(world))
    guard projected.z >= 0, projected.z <= 1 else { return nil }
    guard projected.x.isFinite, projected.y.isFinite else { return nil }

    return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
  }

  /// Cập nhật hình vẽ 3D và bắn khung lớp phủ.
  ///
  /// Hai việc trong một hàm vì chúng phải nói CÙNG một chuyện: đoạn thẳng
  /// SceneKit và nhãn Flutter nằm chồng lên nhau trên màn, và người dùng là
  /// người duy nhất thấy chúng cạnh nhau. Tách ra hai đường là mở chỗ cho một
  /// đường ẩn hình còn đường kia vẫn vẽ nhãn.
  ///
  /// Nhịp: hình vẽ 3D cập nhật MỖI lượt gọi (nó là mấy phép gán vị trí, không
  /// qua kênh nào); khung lớp phủ thì bị chặn ở [overlayMinIntervalSeconds].
  ///
  /// Không có "phát bù" như [publish]: nguồn kích hoạt của lớp phủ là khung
  /// hình, và khi khung hình ngừng tới thì cũng không còn gì sống để vẽ. Mọi
  /// đường ĐỔI TRẠNG THÁI đều đi qua `publish(force: true)`, và nó chuyển
  /// `force` thẳng xuống đây.
  private func refreshOverlay(now: TimeInterval, force: Bool) {
    guard !isStopped else { return }

    let trustworthy = coordinatesAreTrustworthy()
    let placed = trustworthy ? currentMarks() : []
    // Đầu sống chỉ có nghĩa khi đã chấm ĐÚNG một điểm. Không điểm nào thì không
    // có gì để nối tới nó; đủ hai điểm thì đoạn thẳng đã nối hai điểm thật.
    let live = placed.count == 1 ? livePoint.point : nil

    measureNodes.update(points: placed, live: live)

    // Khung lớp phủ chỉ chở TOẠ ĐỘ, không chở lai lịch, và đó là chủ ý: lai
    // lịch đã đi trên kênh trạng thái (`aimTarget` cho đầu sống, `diagnostics`
    // cho từng điểm đã chấm). Nhân bản nó sang đây là dựng một đường thứ hai
    // nói cùng một chuyện, và hai đường ấy lệch nhau được — mỗi kênh có nhịp
    // riêng, nên chúng lệch pha THẬT chứ không chỉ trên lý thuyết.
    var frame: [String: Any] = [:]
    let a = placed.first?.position
    let b = placed.count >= 2 ? placed[1].position : live

    // Tấm ảnh dán đi CHUNG lượt này với hình vẽ và khung lớp phủ, cùng lẽ với
    // hai thứ kia: nó là một node trong cùng cảnh ấy, và bốn trường nó bắn lên
    // Dart nói về CHÍNH cái node vừa được đặt — không phải một phép tính thứ hai
    // chạy sau ở tầng khác.
    for (key, value) in refreshLabel(a: a, b: b) { frame[key] = value }

    if let a, let projected = projectToScreen(a) {
      frame["ax"] = Double(projected.x)
      frame["ay"] = Double(projected.y)
    }
    if let b, let projected = projectToScreen(b) {
      frame["bx"] = Double(projected.x)
      frame["by"] = Double(projected.y)
    }
    // Nói về TRẠNG THÁI của phép đo — "mới có một điểm, đầu kia còn chạy theo
    // máy" — chứ không nói `bx`/`by` có mặt hay không. Vẫn TRUE ở những khung mà
    // tia trượt và đầu B không có toạ độ nào: lúc ấy người vẽ vẫn cần biết mình
    // đang ở giữa một phép đo chứ không phải trước một số đã chốt.
    //
    // Chỉ gửi khi TRUE, cùng lối với `aimLocked`: thiếu khoá nghĩa là "hai điểm
    // đã chốt", đúng mặc định bên Dart.
    if placed.count == 1 {
      frame["bIsLive"] = true
    }
    // Đo trong KHÔNG GIAN 3D, không đo trên màn — nên nó vẫn có giá trị khi một
    // trong hai đầu không chiếu được xuống màn. Hai điểm vẫn có thật; chỉ là
    // không nhìn thấy.
    if let a, let b {
      frame["distanceMm"] = distanceMm(from: a, to: b)
    }

    if !force, now - lastOverlayEmitAt < Self.overlayMinIntervalSeconds { return }
    // Khung y hệt khung trước thì không bắn. Nó cắt hai thứ cùng lúc: dòng khung
    // RỖNG 30 lần/giây suốt quãng người dùng còn đang tìm điểm đầu tiên, và lượt
    // bắn trùng khi một khung hình vừa đổi trạng thái vừa gọi `publish`.
    if let last = lastOverlayFrame, (last as NSDictionary).isEqual(to: frame) { return }

    lastOverlayEmitAt = now
    lastOverlayFrame = frame
    output?.arMeasureSession(self, didProduceOverlay: frame)
  }

  /// Đặt tấm ảnh dán vào chỗ, và trả về bốn trường nói ra chỗ nó ĐÃ đứng.
  ///
  /// **Vì sao tấm ảnh phải là một node chứ không phải một lớp vẽ ở Flutter.**
  /// Đoạn thẳng và hai chấm dính vào THẾ GIỚI: dựng một lần, rồi ARKit cập nhật
  /// tư thế camera mỗi khung. Một con số vẽ lại từ toạ độ đã chiếu — ở tầng
  /// khác, theo nhịp khác (kênh lớp phủ 30 Hz so với SceneKit 60 Hz) — GIẬT so
  /// với chính đoạn thẳng nó nằm trên, không bao giờ là một phần của đoạn, và
  /// biến mất khi một đầu rơi ra sau lưng camera trong khi SceneKit vẫn vẽ phần
  /// đoạn còn trong khối nhìn. Ba triệu chứng, một lỗi kiến trúc.
  ///
  /// **Bốn trường trả về là để ẢNH CHỤP dựng lại đúng hình ấy.** `captureFrame`
  /// trả một khung THUẦN, nên app phải vẽ lại đoạn, hai chấm và con số bằng
  /// canvas của nó. Không có bốn trường này thì app phải tự chiếu trung điểm và
  /// tự đoán góc — tức dựng lại chính cái tầng vừa bị bỏ, và hai phép tính chép
  /// tay lệch nhau thì tấm ảnh mang một con số ở chỗ khác thứ người dùng vừa
  /// nhìn.
  ///
  /// Trả về rỗng nghĩa là **không có nhãn trên màn**: chưa có ảnh nào, chưa có
  /// đoạn nào, hay trung điểm nằm ngoài khối nhìn. Node cũng bị ẩn ở đúng những
  /// đường ấy — không để lại một transform cũ chờ hiện ra sai chỗ.
  private func refreshLabel(a: SIMD3<Float>?, b: SIMD3<Float>?) -> [String: Any] {
    guard measureNodes.hasLabel,
      let a, let b,
      let camera = sceneView.pointOfView?.simdWorldPosition
    else {
      measureNodes.hideLabel()
      return [:]
    }

    let midpoint = (a + b) / 2
    let segment = b - a
    let toCamera = camera - midpoint

    // Hệ trục CHƯA lật, dựng trước: phép lật đọc góc MÀN của chính trục X, nên
    // phải có một trục X để chiếu đã. Dựng lại hệ trục sau khi biết cờ lật rẻ
    // hơn hẳn việc đoán ngược — đây là vài phép nhân vô hướng.
    let plain = LabelPlacement.basis(
      segment: segment, toCamera: toCamera, flipped: false)

    let probe = Self.labelProbeMetres
    guard let centre = projectToScreen(midpoint),
      let alongX = projectToScreen(midpoint + plain.x * probe),
      let alongY = projectToScreen(midpoint + plain.y * probe)
    else {
      measureNodes.hideLabel()
      return [:]
    }

    let deltaX = SIMD2<Double>(
      Double(alongX.x - centre.x), Double(alongX.y - centre.y))
    labelFlipped = LabelPlacement.isFlipped(
      screenDelta: deltaX, wasFlipped: labelFlipped)

    let basis =
      labelFlipped
      ? LabelPlacement.basis(segment: segment, toCamera: toCamera, flipped: true)
      : plain

    // Số POINT mỗi mét ở đúng khoảng cách này, ĐO chứ không suy — xem
    // [labelProbeMetres].
    let deltaY = SIMD2<Double>(
      Double(alongY.x - centre.x), Double(alongY.y - centre.y))
    let pointsPerMetre = simd_length(deltaY) / Double(probe)

    let distance = Double(simd_distance(camera, midpoint))
    let height = LabelPlacement.worldHeight(
      pointHeight: Double(measureNodes.labelPointSize.height),
      pointsPerMetre: pointsPerMetre,
      distanceMetres: distance)
    guard height > 0 else {
      measureNodes.hideLabel()
      return [:]
    }

    measureNodes.placeLabel(
      position: midpoint,
      orientation: LabelPlacement.orientation(basis),
      scale: Float(height))

    // Góc MÀN của trục X ĐÃ lật, độ, cùng chiều với `Canvas.rotate` của Flutter
    // (trục y đi xuống, dương theo chiều kim đồng hồ). Cộng nửa vòng chứ không
    // chiếu lại trục X đã lật: hai phép ấy cho cùng một số, và phép sau tốn
    // thêm một lượt `projectPoint` mỗi khung hình.
    var rotation = atan2(deltaX.y, deltaX.x) * 180 / Double.pi
    if labelFlipped { rotation += 180 }
    rotation = rotation.truncatingRemainder(dividingBy: 360)
    if rotation > 180 { rotation -= 360 }
    if rotation <= -180 { rotation += 360 }

    return [
      "lx": Double(centre.x),
      "ly": Double(centre.y),
      "lrot": rotation,
      "lscale": LabelPlacement.screenScale(distanceMetres: distance),
    ]
  }

  /// Phát lại khung lớp phủ gần nhất cho một người nghe vừa gắn vào.
  ///
  /// Cùng lý lẽ với [replayLastSample], mạnh hơn một bậc: lớp phủ KHÔNG bắn lại
  /// một khung y hệt khung trước, nên một người nghe tới muộn trong lúc máy nằm
  /// yên có thể đợi vô thời hạn.
  func replayLastOverlay() {
    guard !isStopped, let frame = lastOverlayFrame else { return }
    output?.arMeasureSession(self, didProduceOverlay: frame)
  }

  // MARK: - Bắn

  private func publish(force: Bool = false) {
    guard !isStopped else { return }

    trailingEmit?.cancel()
    trailingEmit = nil

    let status = currentStatus()
    let now = CACurrentMediaTime()

    // Vẽ TRƯỚC mọi nhánh nén ở dưới. Hình phải bám hai điểm ngay cả ở những
    // lượt con số không đáng gửi đi (đổi dưới 0,5 mm, hoặc chưa tới nhịp 15 Hz)
    // — để nó rơi vào nhánh nén thì đoạn thẳng giật theo nhịp KÊNH thay vì theo
    // khung hình, và mắt đọc ra ngay.
    //
    // Lớp phủ đi cùng chỗ này, và `force` truyền thẳng xuống: mọi đường gọi
    // `publish(force: true)` là một đường ĐỔI TRẠNG THÁI (chấm, hoàn tác, tạm
    // dừng, hỏng phiên), và ở đó khung lớp phủ phải đi ngay chứ không đợi nhịp.
    refreshOverlay(now: now, force: force)

    let limitedReason = currentLimitedReason()
    // Số đo chỉ đi kèm khi hệ toạ độ còn đáng tin. Mất bám hay đang gián đoạn
    // thì hai điểm vẫn còn đó, nhưng khoảng cách giữa chúng đã không còn nghĩa
    // — spec gọi đây là "che con số đang trôi".
    let mm = status == .measured ? currentDistanceMm() : nil

    // Tầng ngắm chỉ có nghĩa ở ba trạng thái mà một lượt bắn tia còn có nghĩa —
    // xem [reticleIsMeaningful], và chú ý `.measured` NẰM TRONG đó từ 0.10.0.
    // [refreshAimTarget] đã xoá nó ở mọi trạng thái khác, nhưng nó chỉ chạy khi
    // CÓ khung hình — mà `publish` còn được gọi từ những đường không có khung
    // hình nào (lỗi phiên, `pause`, mất quyền camera). Chặn thêm một lượt ở đây
    // thì không còn đường nào để một tầng cũ lọt ra ngoài kênh.
    let aimTarget = Self.reticleIsMeaningful(status) ? self.aimTarget : nil
    // Cờ SUY RA từ tầng, không phải một biến thứ hai. Hai nguồn cho cùng một
    // lượt raycast là hai thứ lệch nhau được, và người dùng là người duy nhất
    // thấy chúng cạnh nhau.
    let aimLocked = aimTarget != nil
    // Van gác theo chính `aimTarget` VỪA CHẶN ở trên, không gác lại theo
    // `status`: hai lời chặn rời nhau là mở đúng một khe cho một quãng vượt
    // biên đi ra kênh mà không có tầng nào đi kèm — một con số nói về một tầng
    // mà mẫu ấy không hề nhắc tới.
    let aimOvershootMm = aimTarget != nil ? self.aimOvershootMm : nil
    // Góc gác theo cùng một `aimTarget` VỪA CHẶN, và chỉ theo nó: điều kiện là
    // "có trúng một mặt phẳng nào đó", không phải "trúng tầng ngoại suy". Đây
    // là chỗ duy nhất góc và van đi khác đường, và nó là chủ đích — xem
    // [aimRayAngleDeg]. Gác góc theo tầng ngoại suy là tắt cảnh báo sượt ở đúng
    // cái tầng người ta tin nhất.
    let aimRayAngleDeg = aimTarget != nil ? self.aimRayAngleDeg : nil
    // Định danh gác theo cùng một `aimTarget` VỪA CHẶN, y như góc: điều kiện là
    // "lượt bắn này có trúng gì không". Nó tự vắng mặt ở tầng ước lượng vì tầng
    // ấy không có `ARPlaneAnchor` — không cần một lời gác thứ hai theo tầng, và
    // thêm vào là dựng một nguồn sự thật thứ hai về chuyện đã có một chỗ lo.
    let aimPlaneId = aimTarget != nil ? self.aimPlaneId : nil

    // Cùng lời chặn, cùng lý do: [refreshAimTarget] đã xoá phép đếm ở mọi
    // trạng thái khác, nhưng nó chỉ chạy khi CÓ khung hình, còn `publish` tới
    // được từ những đường không có khung nào (lỗi phiên, `pause`, mất quyền
    // camera). Một phép đếm cũ lọt ra ngoài kênh ở đó là hai con số gán cho một
    // khoảnh khắc không có lượt ngắm nào.
    let featureCensus = Self.reticleIsMeaningful(status) ? self.featureCensus : nil

    // Đầu mút đang nắm. KHÔNG gác theo `status`, khác hẳn ba khối trên, và đó
    // là chủ đích: ba khối kia suy từ một lượt raycast, nên chúng hết nghĩa lúc
    // tia hết nghĩa. Quãng nắm thì không — nó là một trạng thái của PHIÊN, và
    // app dựng cả giao diện "đang nắm đầu A, bấm đây để buông" lên trường này.
    // Gác nó theo trạng thái là cái nút buông biến mất ở đúng lúc phiên rung
    // tay, và người dùng không có đường nào thoát khỏi quãng nắm.
    let grabbedPointIndex = drag?.index

    // `limitedReason` và `aimTarget` nằm trong điều kiện gộp cùng `status`, và
    // cả hai vì cùng một lý do: bộ nén ở dưới neo vào "số đo đổi quá 0,5 mm",
    // mà cả hai khoá này đổi ĐƯỢC trong khi số đo không đổi một chút nào.
    //
    // Với `aimTarget` thì còn mạnh hơn thế: lúc nó đổi, phần lớn thời gian
    // **chưa có điểm nào**, nên `mm` là `nil` và nhánh dưới `return` thẳng.
    // Không đưa nó lên đây thì lượt bắt được bề mặt đầu tiên — đúng cái tín
    // hiệu bảo người dùng bấm được rồi — bị nuốt trọn, và tâm ngắm câm đúng lúc
    // nó cần nói.
    //
    // So theo TẦNG chứ không theo cờ: một lượt đổi từ `estimatedPlane` sang
    // `existingPlaneGeometry` không đổi cờ một chút nào, mà đó là đúng lượt tâm
    // ngắm phải đổi hình.
    //
    // Cái giá là tầng đổi thì bỏ qua cả nhịp 15 Hz. Chấp nhận được vì trần đã
    // bị chặn từ chỗ khác: cờ chỉ lấy mẫu trên lưới 10 Hz
    // ([aimProbeIntervalSeconds]), nên nó bắn được nhiều nhất 10 lần/giây và
    // thực tế còn ít hơn nhiều — chỉ ĐỔI mới bắn.
    // Phép đếm nằm trong điều kiện gộp vì một lẽ MẠNH HƠN cả `aimTarget`, và
    // nó là lẽ khiến cả phép đo dùng được: ở đúng cảnh đang điều tra — phòng
    // trơn, tia trượt liên tục — `status` đứng im ở `ready`, `limitedReason`
    // là `nil`, `aimTarget` là `nil`, `mm` là `nil`, nên nhánh dưới `return`
    // thẳng và `publish` KHÔNG BAO GIỜ chạy. Để phép đếm ngoài điều kiện này
    // thì hai con số mới không bao giờ tới Dart ở đúng cảnh chúng sinh ra để
    // đo, và dải chẩn đoán im lặng đọc y hệt "chưa dựng xong".
    //
    // **Cái giá phải nói thẳng**: khác `aimTarget` (đổi vài lần mỗi phiên),
    // phép đếm đổi gần như mỗi lượt lấy mẫu, nên quãng người dùng đang ngắm giờ
    // bắn tới 10 mẫu/giây thay vì im lặng. Trần 10 Hz đã có sẵn từ
    // [aimProbeIntervalSeconds] và không vượt qua được, nhưng SÀN thì đã khác:
    // kênh trạng thái từ nay không còn im khi không có gì xảy ra. Đây là giá
    // của một bản ĐO, và nó ra cùng lúc với phép đo — bỏ phép đo là sàn ấy trở
    // lại y như cũ.
    // Định danh mặt phẳng vào đây từ 0.8.0, và nó KHÔNG đi nhờ được ba khoá
    // ngắm kia: cảnh nó sinh ra để bắt là cảnh mà chúng đều đứng im. Người dùng
    // rê tia từ MẶT BÀN xuống SÀN — hai mặt phẳng khác nhau, cùng `horizontal`,
    // cùng tầng `existingPlaneGeometry`, van `nil` ở cả hai, và cầm máy cùng độ
    // nghiêng thì góc bằng nhau. `featureCensus` không đỡ được: tài liệu của
    // chính nó nói nó là phép đo có hạn dùng và sẽ rời gói, và ngày ấy một định
    // danh không nằm ở đây sẽ đóng băng ở mặt phẳng của lượt đầu — đúng lỗi mà
    // cái van đã trả giá một lần, chỉ khác kiểu dữ liệu.
    // Van nằm trong điều kiện gộp vì một lẽ RIÊNG, không phải để cho đủ bộ:
    // khi tia đứng ở tầng ngoại suy và người dùng rê máy ra xa mép bàn, `status`
    // đứng im, `limitedReason` là `nil`, `aimTarget` KHÔNG đổi (vẫn ngoại suy),
    // và `mm` là `nil` khi chưa chấm điểm nào. Thứ duy nhất đổi là chính con số
    // này. Để nó ngoài điều kiện thì van đóng băng ở giá trị của lượt đầu — 30
    // mm — trong khi tia đã trôi ra hai mét: một cái van báo AN TOÀN đúng lúc
    // nó phải kêu, và như thế còn tệ hơn không có van nào.
    //
    // Không thêm sàn bắn nào: `featureCensus` đã đổi gần như mỗi lượt lấy mẫu
    // từ 0.5.0, nên trần 10 Hz vẫn là trần cũ và sàn thì đã mất từ bản ấy.
    //
    // Góc tia vào điều kiện này từ 0.7.0, và nó KHÔNG thừa dù phép đếm đang kéo
    // gần như mọi mẫu đi cùng: `ArFeatureCensus` là một phép đo có hạn dùng —
    // tài liệu của chính nó nói nó biến mất cùng lúc câu hỏi ấy được trả lời.
    // Ngày nó ra khỏi gói, một góc tia không nằm ở đây sẽ đóng băng ở giá trị
    // của lượt đầu trong khi người dùng vẫn đang nghiêng máy: đúng lỗi mà cái
    // van đã trả giá một lần, chỉ khác con số.
    //
    // `fx` thì CỐ Ý không vào đây, ngược hẳn với góc. Lấy nét tự động làm nó
    // nhúc nhích gần như mỗi khung hình, nên đưa vào là biến kênh trạng thái
    // thành một cái vòi 60 Hz vì một con số không ai nhìn theo thời gian thực —
    // app đọc nó một lần để đặt vào công thức. Nó đi nhờ mọi mẫu đã được bắn, y
    // như khối `video`.
    if !force, status == lastStatus, limitedReason == lastLimitedReason,
      aimTarget == lastAimTarget, featureCensus == lastFeatureCensus,
      grabbedPointIndex == lastGrabbedPointIndex,
      aimOvershootMm == lastAimOvershootMm,
      aimRayAngleDeg == lastAimRayAngleDeg,
      aimPlaneId == lastAimPlaneId
    {
      guard let mm else { return }
      if let last = lastMm, abs(mm - last) < Self.minChangeMm { return }

      let waited = now - lastEmitAt
      if waited < Self.minIntervalSeconds {
        // Trễ nhịp thì HẸN LẠI, không bỏ. Bỏ thẳng thì lượt đổi cuối cùng —
        // đúng lượt con số đứng lại, tức tín hiệu để người dùng bấm chốt — có
        // thể không bao giờ tới Dart.
        //
        // Khung hình tới đều 60 Hz nên phần lớn thời gian cái hẹn này bị chính
        // khung sau huỷ và đặt lại ở đúng cùng một mốc (`lastEmitAt + nhịp`),
        // rồi tới mốc ấy thì bắn thẳng. Nó là lưới an toàn cho lúc khung hình
        // NGỪNG tới giữa chừng — phiên bị `pause`, hoặc gián đoạn — chứ không
        // còn là đường chính như hồi bắn theo sự kiện.
        let work = DispatchWorkItem { [weak self] in self?.publish(force: true) }
        trailingEmit = work
        DispatchQueue.main.asyncAfter(
          deadline: .now() + (Self.minIntervalSeconds - waited), execute: work)
        return
      }
    }

    // Số đo và trạng thái đi trong CÙNG MỘT khung.
    //
    // Hợp đồng của spec là "bắn `ArMeasurement` trước, trạng thái `measured`
    // sau", để màn không rơi vào một khung trống giữa hai nhịp. Ở đây nó được
    // thoả bằng một cách mạnh hơn: không tồn tại khoảnh khắc nào Dart thấy
    // `measured` mà chưa thấy số, vì `measured` theo định nghĩa là "hai điểm và
    // đang bám" — tức là `mm` luôn tính được, và nó nằm ngay trong map này.
    var sample: [String: Any] = ["status": status.rawValue]
    if let limitedReason {
      sample["limitedReason"] = limitedReason.rawValue
    }
    // Chỉ gửi khi FALSE. Thiếu khoá nghĩa là "còn gỡ được" — đúng mặc định bên
    // Dart, và đúng hành vi của mọi bản trước khoá này.
    if failure != nil, !failureIsRecoverable {
      sample["recoverable"] = false
    }
    // Cùng lối với `recoverable`, ngược chiều: chỉ gửi khi TRUE. Thiếu khoá
    // nghĩa là "chưa bám" — đúng mặc định bên Dart, đúng hình tâm ngắm an toàn
    // (rỗng, còn phải rê tiếp), và đúng hành vi của mọi bản trước khoá này.
    if aimLocked {
      sample["aimLocked"] = true
    }
    // Tầng đi CÙNG cờ, không thay nó. Cờ là mặt cũ của gói và một app đã dựng
    // trên nó không phải sửa gì; tầng là mặt mới, và người nhận nào cần ba mức
    // thì đọc nó. Vắng khoá này nghĩa là "tầng nền không nói" — cùng một chỗ
    // rơi với "tia không trúng gì", và đúng thế: cả hai đều là không có tầng
    // nào để bày.
    if let aimTarget {
      sample["aimTarget"] = aimTarget.rawValue
    }
    // Cái van, đo trên tia ĐANG ngắm. Chỉ có mặt ở tầng ngoại suy, và vắng mặt
    // ở hai tầng kia là một SỰ THẬT chứ không phải một chỗ chưa tính: điểm nằm
    // trong biên thật, hoặc trên một mặt ARKit vừa đoán ra, thì không có biên
    // nào bị vượt. Bù 0 ở đó là nói "đã đo, và bằng không" — một khẳng định
    // khác hẳn, và nó xoá đúng thứ phân biệt ba tầng.
    if let aimOvershootMm {
      sample["aimOvershootMm"] = aimOvershootMm
    }
    // Góc của tia ĐANG ngắm. Có mặt ở MỌI tầng, vắng mặt chỉ khi tia không
    // trúng gì — lúc ấy không có mặt phẳng nào để đo góc so với nó, và `nil` là
    // một sự thật chứ không phải một chỗ chưa tính. Bù 0 ở đó là nói "tia lướt
    // sát mặt", đúng cái câu nguy hiểm nhất trường này biết nói.
    if let aimRayAngleDeg {
      sample["aimRayAngleDeg"] = aimRayAngleDeg
    }
    // Định danh mặt phẳng của tia ĐANG ngắm. Vắng mặt ở HAI đường, và cả hai
    // đều là sự thật: tia không trúng gì, hoặc tia trúng một mặt ƯỚC LƯỢNG —
    // tầng ấy không neo mặt phẳng nó vừa đoán ra vào đâu, nên không có gì để
    // khai tên. Bù một giá trị giả ở đó là dựng ra đúng kết luận "cùng mặt
    // phẳng" mà trường này sinh ra để chặn.
    //
    // Gói dừng ở đây: nó trả định danh, KHÔNG kết luận "hai đầu mút có cùng
    // mặt phẳng không". Cùng ranh giới với `aimOvershootMm`.
    if let aimPlaneId {
      sample["aimPlaneId"] = aimPlaneId
    }
    // Đầu mút đang nắm. Vắng khoá nghĩa là KHÔNG nắm gì — đúng mặc định bên
    // Dart, và đúng hành vi của mọi bản trước cặp lệnh này.
    //
    // Đi ra ngoài chứ không để app tự nhớ từ giá trị trả về của `grabPoint`:
    // gói TỰ buông ở những đường app không gây ra — gián đoạn, `pause`,
    // `reset`, `dispose`, một lệnh khác dời điểm, hay ARKit bỏ chính cái anchor
    // đang nắm. App nhớ một mình thì sau những lượt ấy nó còn vẽ "đang nắm đầu
    // A" cho một quãng đã kết thúc, và cái nút buông không buông gì cả.
    if let grabbedPointIndex {
      sample["grabbedPointIndex"] = grabbedPointIndex
    }
    // Chẩn đoán đi kèm mọi mẫu có ít nhất MỘT điểm, và nó nằm ở đây — TRƯỚC
    // `if let mm` — chứ không nằm trong đó. Nhét vào trong là chỉ gửi khi đã đủ
    // hai điểm, mà điểm ĐẦU mới là chỗ giả thuyết "chấm sai điểm đầu" phải
    // kiểm: người dùng chấm điểm một trên một mặt ước lượng lúc phiên còn
    // `.limited(.initializing)` rồi mới rê máy sang điểm hai.
    //
    // Thứ tự đọc từ [anchors] — thứ tự CHẤM — chứ không từ `pointDiagnostics`:
    // `Dictionary.values` không có thứ tự, và hai điểm đổi chỗ ngẫu nhiên giữa
    // các lượt bắn thì cả dải chẩn đoán nói dối mà không lỗi nào nổ.
    //
    // Map rỗng cho một anchor không có chẩn đoán (đường này không tới được:
    // `placePoint` ghi ngay lúc thêm anchor, và `movePoint` ghi ngay lúc thay
    // anchor) — giữ CHỖ chứ không rút ngắn danh sách, vì rút ngắn là điểm hai
    // trượt lên chỗ điểm một.
    //
    // Không cần đưa vào bộ nén ở trên: chẩn đoán chỉ đổi khi [anchors] đổi hoặc
    // khi phiên `run` lại, và cả hai đường đều `publish(force: true)`.
    //
    // Khuôn hình đi CÙNG khối này nhưng KHÔNG đi cùng điều kiện: nó là chuyện
    // của cả phiên chứ không phải của một điểm, và nó phải đọc được khi chưa có
    // điểm nào — đó đúng là lúc người ta cần biết vì sao chưa chấm nổi điểm nào.
    var diagnostics: [String: Any] = [:]
    if !anchors.isEmpty {
      diagnostics["points"] = anchors.map {
        pointDiagnostics[$0.identifier]?.payload ?? [:]
      }
    }
    if let videoFormat {
      diagnostics["video"] = videoFormat
    }
    // Thấu kính: cùng khối, và KHÔNG gác theo trạng thái — khác hẳn tầng ngắm
    // và phép đếm. Nó nói về cái MÁY, không nói về một lượt ngắm, và app cần nó
    // nhất ở hai chỗ mà lối gác kia sẽ cắt mất: lúc đã đủ hai điểm (để tính
    // dung sai của con số vừa chốt) và lúc chưa chấm nổi điểm nào.
    //
    // Map rỗng thì không gửi khoá: ba ô cùng hỏng là "không đọc được thấu
    // kính", và một khối rỗng đọc ra "đã đọc, và rỗng".
    if let cameraIntrinsics {
      let payload = cameraIntrinsics.payload
      if !payload.isEmpty {
        diagnostics["camera"] = payload
      }
    }
    // Phép đếm điểm đặc trưng: cùng khối, cùng lý do với khuôn hình — chuyện
    // của KHUNG HÌNH chứ không của một điểm, và phải đọc được lúc chưa chấm nổi
    // điểm nào, vì đó đúng là lúc câu hỏi nó sinh ra để trả lời đang được hỏi.
    if let featureCensus {
      diagnostics["features"] = featureCensus.payload
    }
    if !diagnostics.isEmpty {
      sample["diagnostics"] = diagnostics
    }
    if let mm {
      sample["mm"] = mm
      sample["tolMm"] = toleranceMm(forMm: mm)
      // ĐÂY LÀ HẰNG SỐ, KHÔNG PHẢI KẾT QUẢ ĐO: hít cạnh CHƯA ĐƯỢC TÍNH ở bất
      // cứ đâu trong gói (nó nằm sau một cờ tắt cho tới khi đo được tỉ lệ trúng
      // trên máy thật). Trường vẫn gửi để khuôn dây không đổi lúc nó vào.
      //
      // Nhắc thẳng ra vì ngay bên trên nó bây giờ là cả một tầng chẩn đoán toàn
      // dữ liệu THẬT: một `false` nằm giữa những con số thật đọc y hệt một phép
      // đo đã chạy và trả về false.
      sample["snappedToEdge"] = false
    }

    lastStatus = status
    lastLimitedReason = limitedReason
    lastAimTarget = aimTarget
    lastAimOvershootMm = aimOvershootMm
    lastAimRayAngleDeg = aimRayAngleDeg
    lastAimPlaneId = aimPlaneId
    lastFeatureCensus = featureCensus
    lastGrabbedPointIndex = grabbedPointIndex
    lastMm = mm
    lastEmitAt = now
    lastSample = sample
    output?.arMeasureSession(self, didProduce: sample)
  }

  // MARK: - Nối lại vị trí

  private func beginRelocalizationWatch() {
    cancelRelocalizationWatch()
    // Không có điểm nào thì không có gì để mất: cứ để ARKit nối lại bao lâu tuỳ
    // nó, người dùng chưa chấm gì cả.
    guard !anchors.isEmpty else { return }

    let work = DispatchWorkItem { [weak self] in self?.giveUpRelocalization() }
    relocalizationWatch = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.relocalizationDeadlineSeconds, execute: work)
  }

  private func cancelRelocalizationWatch() {
    relocalizationWatch?.cancel()
    relocalizationWatch = nil
  }

  private func giveUpRelocalization() {
    relocalizationWatch = nil
    guard !isStopped else { return }

    // Kiểm lại trạng thái, đừng tin mỗi cái hẹn giờ.
    //
    // Hẹn giờ được đặt theo SỰ KIỆN (`sessionInterruptionEnded`, [resume])
    // nhưng chỉ được huỷ khi trạng thái CHUYỂN sang `.normal` — và ARKit chỉ
    // gọi `cameraDidChangeTrackingState` khi trạng thái ĐỔI. Một lượt gián đoạn
    // ngắn không làm phiên rời `.normal` thì không callback nào tới, không ai
    // huỷ, và năm giây sau hàm này xoá hai điểm của một phiên hoàn toàn bình
    // thường — im lặng, giữa lúc người ta đang đo.
    //
    // `isInterrupted` là cờ duy nhất nói "đang chờ nối lại": [pause] huỷ hẹn
    // giờ, và [resume] bật lại cả cờ lẫn hẹn giờ cùng lúc.
    guard isInterrupted else { return }

    // Spec chốt: nối lại không được thì BỎ hai điểm và về `ready`. Đo tiếp trên
    // một hệ toạ độ khác cho ra một con số trông hoàn toàn bình thường mà sai
    // — dạng hỏng tệ nhất, vì không có gì trên màn nói ra.
    //
    // Đường về `ready` đi qua `initializing`: dựng lại hệ toạ độ mất vài giây,
    // và nói `ready` ngay trong lúc ấy là mời người dùng chấm vào một thứ chưa
    // bám được.
    clearAnchors()
    isInterrupted = false
    hasTrackedOnce = false
    trackingState = nil
    start(options: [.resetTracking, .removeExistingAnchors])
  }

  /// Nhận bản mới của hai điểm từ một danh sách anchor bất kỳ.
  ///
  /// `ARAnchor.transform` là **readonly**, nên nếu ARKit có chỉnh vị trí một
  /// điểm thì nó chỉ có thể trao ra một ĐỐI TƯỢNG KHÁC cùng `identifier`. Đây
  /// là chỗ đối tượng ấy được nhận về, dù nó tới từ `frame.anchors` hay từ
  /// `session(_:didUpdate anchors:)`.
  ///
  /// Trả về `true` khi có ít nhất một điểm được thay — người gọi dùng nó để
  /// khỏi bắn khi không có gì đổi.
  @discardableResult
  private func adoptUpdatedAnchors(_ updated: [ARAnchor]) -> Bool {
    guard !anchors.isEmpty else { return false }
    // Lọc theo id trước, tính sau: với `sceneReconstruction = .mesh`, danh sách
    // truyền vào có thể là hàng trăm `ARMeshAnchor` mỗi lượt.
    let ids = Set(anchors.map(\.identifier))
    var changed = false
    for candidate in updated where ids.contains(candidate.identifier) {
      guard let index = anchors.firstIndex(where: { $0.identifier == candidate.identifier })
      else { continue }
      if anchors[index] !== candidate {
        anchors[index] = candidate
        changed = true
      }
    }
    return changed
  }

  private func clearAnchors() {
    for anchor in anchors {
      sceneView.session.remove(anchor: anchor)
    }
    anchors.removeAll()
    pointDiagnostics.removeAll()
    lastMm = nil
    // Quãng nắm chết cùng danh sách điểm, và ở đây KHÔNG chốt gì — chốt một
    // điểm vào một danh sách vừa bị xoá là thêm lại đúng cái điểm mà `reset`
    // vừa bỏ. Cùng lẽ với lời xoá cứng của `livePoint` ngay dưới: chỗ cũ không
    // sai vì chưa dò lại được, nó sai vì cái thế giới nó đo trong đó đã hết.
    drag = nil
    // Đầu sống của đoạn thẳng đọc từ lượt dò của khung hình, và `reset()` dựng
    // lại cả hệ toạ độ — điểm của lượt dò trước nằm trong hệ toạ độ CŨ.
    //
    // XOÁ CỨNG, không đi qua quãng ôm: quãng ôm nói "chưa dò lại được", còn ở
    // đây điểm cũ không sai vì chưa dò lại mà sai vì cái thế giới nó đo trong
    // đó đã không còn. Ôm thêm 100 ms là vẽ tới một toạ độ trông hoàn toàn bình
    // thường và không còn liên quan gì tới thứ đang ở trước ống kính.
    livePoint.clear()
  }
}

// MARK: - ARSessionDelegate

extension ArMeasureSession: ARSessionDelegate {
  /// Bật nối lại vị trí.
  ///
  /// Gián đoạn thật (cuộc gọi, Control Center, xuống nền) hầu hết là ngắn, và
  /// ARKit thường về đúng hệ toạ độ cũ — trả `false` là vứt đi một phiên lẽ ra
  /// cứu được, bắt người dùng chấm lại từ đầu mỗi lần có ai gọi tới. Cái giá
  /// của `true` là một quãng `.limited(.relocalizing)`, và quãng ấy đã được
  /// [beginRelocalizationWatch] đặt hạn: hết hạn thì bỏ hai điểm, đúng như spec.
  func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
    true
  }

  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    trackingState = camera.trackingState
    if case .normal = camera.trackingState {
      hasTrackedOnce = true
      // Bám lại được rồi thì gián đoạn coi như xong, kể cả khi
      // `sessionInterruptionEnded` chưa tới.
      cancelRelocalizationWatch()
      isInterrupted = false
    }
    publish(force: true)
  }

  func sessionWasInterrupted(_ session: ARSession) {
    // Đường buông AN TOÀN. Cuộc gọi tới, Control Center, app xuống nền: tâm
    // ngắm không còn trong tay người dùng, và quãng gián đoạn dài bao lâu thì
    // không ai biết. Giữ quãng nắm qua đó là để lượt bám lại — có thể sau một
    // lượt nối lại hệ toạ độ — kéo đầu mút tới một chỗ chưa ai ngắm.
    //
    // Chốt chứ không vứt: lượt trúng cuối được ghi lúc ARKit còn bám BÌNH
    // THƯỜNG ([probeReticle] không nhận lượt trúng nào ngoài ba trạng thái ấy),
    // nên nó là một quan sát tốt, không phải một mảnh của lúc hỏng.
    releasePoint()
    isInterrupted = true
    cancelRelocalizationWatch()
    publish(force: true)
  }

  func sessionInterruptionEnded(_ session: ARSession) {
    if anchors.isEmpty {
      isInterrupted = false
    } else {
      // Giữ nguyên `isInterrupted` cho tới khi ARKit báo bám lại được: hai điểm
      // còn đó nhưng hệ toạ độ chưa chắc, nên con số chưa được phép hiện.
      beginRelocalizationWatch()
    }
    publish(force: true)
  }

  func session(_ session: ARSession, didFailWithError error: Error) {
    // ARKit đã dừng phiên trước khi gọi vào đây. Lỗi dính lại cho tới `reset()`
    // — chạy lại ngay lập tức chỉ dựng lại đúng cái lỗi vừa xảy ra.
    let code = (error as? ARError)?.code
    switch code {
    case .some(.cameraUnauthorized):
      failure = .cameraUnauthorized
      failureIsRecoverable = true

    case .some(.unsupportedConfiguration), .some(.sensorUnavailable):
      // Hai mã này là hỏng VĨNH VIỄN: máy không chạy nổi cấu hình đang dùng,
      // hoặc cảm biến không dùng được. Trạng thái vẫn là `trackingLost` — thêm
      // một trạng thái thứ chín thì mọi app đang dùng gói phải sửa — nhưng cờ
      // đi kèm cho màn biết đừng mời người dùng rê máy cho một phiên chết hẳn.
      //
      // `sensorFailed` (102) CỐ Ý không nằm đây: nó có thể chỉ là máy quá nóng,
      // và cái đó tự khỏi.
      failure = .trackingLost
      failureIsRecoverable = false

    default:
      failure = .trackingLost
      failureIsRecoverable = true
    }
    publish(force: true)
  }

  /// Nguồn kích hoạt CHÍNH của số đo trôi.
  ///
  /// Không phải `didUpdate anchors:`, và đây là chỗ dễ đặt nhầm nhất trong cả
  /// tệp. Tài liệu `ARAnchor` của Apple khuyên "nếu một vật ảo di chuyển thì bỏ
  /// anchor ở chỗ cũ và thêm một cái ở chỗ mới", `transform` là readonly, và
  /// mọi chỗ Apple thật sự tài liệu hoá việc anchor tự cập nhật đều gọi tên một
  /// LỚP CON (`ARPlaneAnchor`, `ARGeoAnchor`) chứ không phải một `ARAnchor`
  /// trần do app thêm. Bản thân `session(_:didUpdate anchors:)` cũng chỉ hứa
  /// ARKit "**may** automatically update".
  ///
  /// Treo cả phép đo lên một lời hứa có chữ "may" thì hỏng theo kiểu tệ nhất:
  /// callback kia không nổ → con số ĐỨNG IM từ lúc điểm thứ hai rơi xuống →
  /// toàn bộ bộ giãn nhịp bên dưới thành mã chết, và sau một lượt ARKit chỉnh
  /// lại thế giới thì hai transform đã lưu là số đông cứng trong hệ toạ độ CŨ.
  /// Khung hình thì luôn tới, nên nó là nguồn kích hoạt duy nhất đáng tin.
  ///
  /// Đây KHÔNG phải một cái vòi 60 Hz: [publish] gọi không ép buộc, nên ngưỡng
  /// 0,5 mm và nhịp 15 Hz (kèm phát bù) vẫn nén y như trước.
  ///
  /// Nó cũng là nguồn kích hoạt của lượt dò tâm ngắm, và đó là một lượt SỬA:
  /// bản trước chặn sớm ngay dòng đầu bằng `guard anchors.count == 2`.
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // Lượt dò chạy TRƯỚC, và chạy cả khi chưa có điểm nào.
    //
    // Lời chặn sớm cũ đúng với giả định của nó: dưới hai điểm thì không có gì
    // trong mẫu đổi được theo khung hình, vì trạng thái chỉ phụ thuộc
    // `trackingState`, `failure`, hai cờ pause/interrupt và SỐ điểm — không thứ
    // nào đi qua đây. Cờ ngắm phá đúng giả định ấy: nó CHỈ đổi theo khung hình,
    // và nó chỉ có nghĩa ở đúng cái quãng mà lời chặn cũ cắt bỏ — lúc người
    // dùng đang ngắm điểm đầu tiên.
    //
    // [probeReticle] tự giãn nhịp xuống 10 Hz và tự bỏ qua khi trạng thái không
    // cho chấm, nên đây không phải một lượt raycast mỗi khung hình — trừ đúng
    // quãng đang có đoạn thẳng SỐNG, là quãng nó phải chạy mỗi khung hình.
    let now = CACurrentMediaTime()

    // Thấu kính của ĐÚNG khung hình này, đọc trước mọi lối rẽ ở dưới. Hai phép
    // đọc và một phép gán — rẻ hơn hẳn một lượt raycast, và nó KHÔNG kích một
    // lượt bắn nào: con số này cố ý nằm ngoài mọi phép so của bộ nén, nên nó đi
    // nhờ những mẫu đã được bắn vì lý do khác.
    //
    // Đọc mỗi khung chứ không đọc một lần lúc `run`: gói bật lấy nét tự động,
    // nên tiêu cự nhúc nhích theo cự ly lấy nét: một `fx` đông cứng từ lúc mở
    // camera là một hằng số đội lốt một phép đo.
    cameraIntrinsics = ArCameraIntrinsics(camera: frame.camera)

    let probe = probeReticle(now: now, frame: frame)
    // Bước kéo đi TRƯỚC mọi thứ đọc vị trí điểm: lớp phủ, hình vẽ SceneKit và
    // con số đều lấy vị trí qua [position(ofPointAt:)], nên bước sau chúng là
    // vẽ một khung bằng toạ độ của khung trước — đầu mút trễ đúng một khung
    // hình sau tâm ngắm, suốt quãng kéo.
    //
    // `||` chứ không `|`: [refreshAimTarget] có tác dụng phụ (nó ghi bốn trường
    // ngắm và phép đếm vân), nên nó phải chạy ở MỌI khung. Viết
    // `stepDrag(...) || refreshAimTarget(...)` là một khung kéo trúng sẽ nhảy
    // qua cả lượt cập nhật tâm ngắm.
    let stepped = stepDrag(now: now, probe: probe)
    var shouldPublish = refreshAimTarget(now: now, frame: frame, probe: probe)
    // Số đo đổi ở mỗi bước kéo mà KHÔNG anchor nào đổi, nên không đường nào
    // khác kích được lượt bắn ấy — `adoptUpdatedAnchors` ngay dưới không thấy
    // gì. Thiếu dòng này thì đoạn thẳng bám theo tay còn CON SỐ ở dải đáy đứng
    // im suốt quãng kéo.
    if stepped { shouldPublish = true }

    // Phần số đo vẫn chặn y như cũ, chỉ là chặn SAU lượt dò chứ không trước.
    // Không giữ `frame` lại quá lời gọi này: giữ một `ARFrame` là chặn ARKit
    // giao khung mới. Chỉ hai `ARAnchor` được lấy ra, và chúng không giữ khung.
    if anchors.count == 2, adoptUpdatedAnchors(frame.anchors) {
      shouldPublish = true
    }

    // Lớp phủ chạy MỖI khung hình, không đợi `shouldPublish`. Đầu sống của đoạn
    // thẳng đổi ở mỗi khung mà không đổi trạng thái nào và không đổi số đo nào,
    // nên nếu nó đi nhờ lối rẽ này thì nó không bao giờ được bắn.
    if shouldPublish {
      publish()
    } else {
      refreshOverlay(now: now, force: false)
    }
  }

  func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    // Đường phụ, cố ý giữ lại: nếu ARKit CÓ tự cập nhật hai điểm thì mình nghe
    // được ngay lượt ấy thay vì đợi khung hình kế tiếp. Nhưng không có gì trong
    // phép đo phụ thuộc vào chuyện nó có nổ hay không — xem
    // [session(_:didUpdate frame:)].
    if adoptUpdatedAnchors(anchors) { publish() }
  }

  func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
    // ARKit tự bỏ điểm neo (hiếm — chủ yếu là hệ quả của `.removeExistingAnchors`
    // do chính lớp này gửi). Bỏ đúng cái nó bỏ, không bỏ thêm: còn lại một điểm
    // thì trạng thái tự về `firstPointPlaced`, và người dùng chấm tiếp là xong.
    // Bỏ cả hai "cho chắc" là xoá một điểm ARKit không hề nói là sai.
    let removed = Set(anchors.map(\.identifier))
    let before = self.anchors.count
    self.anchors.removeAll { removed.contains($0.identifier) }
    for id in removed { pointDiagnostics.removeValue(forKey: id) }
    guard self.anchors.count != before else { return }
    // Danh sách vừa ngắn đi, nên CHỈ SỐ đang nắm có thể đã trỏ sang một điểm
    // khác. Buông cứng, không chốt: chốt theo một chỉ số đã trượt là dời đúng
    // cái đầu mút người dùng không hề chạm vào. App biết vì `grabbedPointIndex`
    // của mẫu ngay dưới về `nil`.
    drag = nil
    if self.anchors.count < 2 { lastMm = nil }
    publish(force: true)
  }
}
