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

// MARK: - Chẩn đoán

/// Tầng mục tiêu mà tia ĐÃ trúng — đọc thẳng từ `ARRaycastResult.target`.
///
/// Ba giá trị đúng bằng `ARRaycastQuery.Target`. `.existingPlaneGeometry` là
/// điểm nằm trên một mặt phẳng ARKit đã xác nhận; `.estimatedPlane` là một mặt
/// phẳng ARKit ĐOÁN ra từ hình học quanh tia (trên máy LiDAR thì đó là lưới
/// thật, nên cùng một chữ mang hai mức tin cậy rất khác nhau — vì thế
/// [ArPointDiagnostics] còn chở kèm mặt phẳng trúng).
/// `.existingPlaneInfinite` KHÔNG nằm trong danh sách gói bắn ra
/// ([ArMeasureSession.raycastFromReticle] cố ý không dùng), nhưng vẫn có mặt ở
/// đây vì `target` là của ARKit chứ không phải của gói.
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

  /// `nil` khi tia trúng một mặt ƯỚC LƯỢNG — không có `ARPlaneAnchor` nào.
  let planeAlignment: ArPlaneAlignment?
  let planeWidthMm: Double?
  let planeHeightMm: Double?

  /// Map đã sẵn sàng cho kênh. Khoá vắng mặt = tầng nền không nói được.
  var payload: [String: Any] {
    var map: [String: Any] = [:]
    if let target { map["target"] = target.rawValue }
    if let tracking { map["tracking"] = tracking.rawValue }
    if let sessionAgeMs { map["sessionAgeMs"] = sessionAgeMs }
    if let cameraDistanceMm { map["cameraDistanceMm"] = cameraDistanceMm }
    if let rayAngleDeg { map["rayAngleDeg"] = rayAngleDeg }
    if let planeAlignment { map["planeAlignment"] = planeAlignment.rawValue }
    if let planeWidthMm { map["planeWidthMm"] = planeWidthMm }
    if let planeHeightMm { map["planeHeightMm"] = planeHeightMm }
    return map
  }
}

/// Đường ra của một phiên: một map đã sẵn sàng cho `EventChannel`.
///
/// Là protocol chứ không phải closure để phía nhận giữ được **yếu**. Một
/// closure bắt `self` mạnh ở đây là đúng cái vòng giữ view sống mãi mà luật
/// vòng đời số 2 nói tới.
protocol ArMeasureSessionOutput: AnyObject {
  func arMeasureSession(_ session: ArMeasureSession, didProduce sample: [String: Any])
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
  private let line: SCNNode

  init() {
    dots = [Self.makeDot(), Self.makeDot()]
    line = Self.makeLine()
    for dot in dots {
      root.addChildNode(dot)
    }
    root.addChildNode(line)
    update(points: [])
  }

  /// Đặt lại hình theo các điểm đang có: không điểm nào, một, hoặc hai.
  ///
  /// Không dựng lại node nào — chỉ dời chỗ và ẩn/hiện. Dựng lại `SCNGeometry`
  /// mỗi lượt là cấp phát trên luồng vẽ, và lượt gọi này đi cùng nhịp với số đo
  /// trôi.
  func update(points: [SIMD3<Float>]) {
    for (index, dot) in dots.enumerated() {
      if index < points.count {
        dot.simdPosition = points[index]
        dot.isHidden = false
      } else {
        dot.isHidden = true
      }
    }

    guard points.count == 2 else {
      line.isHidden = true
      return
    }

    let a = points[0]
    let b = points[1]
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

  private static func makeLine() -> SCNNode {
    let cylinder = SCNCylinder(radius: lineRadius, height: 0.01)
    cylinder.radialSegmentCount = 12
    cylinder.firstMaterial = makeMaterial()
    return SCNNode(geometry: cylinder)
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

  // MARK: - Nhịp dò tâm ngắm

  /// Bao lâu bắn một tia thăm dò cho tâm ngắm.
  ///
  /// Lượt dò này KHÔNG dùng chung nhịp với [minIntervalSeconds] vì hai thứ
  /// khác hẳn nhau về giá: bắn một mẫu là ghép một dictionary rồi đẩy qua kênh,
  /// còn dò là chạy tới hai `ARRaycastQuery` thật — một lượt cắt hình học mặt
  /// phẳng đã dò ra, rồi (nếu trượt) một lượt khớp mặt phẳng ước lượng quanh
  /// tia.
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

  /// Trượt liên tiếp bao lâu thì mới HẠ cờ ngắm.
  ///
  /// Bất đối xứng có chủ đích: khoá thì khoá ngay ở lượt dò trúng đầu tiên,
  /// nhưng mở khoá thì phải trượt suốt quãng này. Không có nó, một bề mặt ở
  /// ranh giới (mép giấy, vân gỗ mờ) cho ra một chuỗi trúng-trượt-trúng và tâm
  /// ngắm **nhấp nháy 10 lần một giây** — khó đọc hơn hẳn một tâm ngắm đứng yên
  /// ở một trong hai hình.
  ///
  /// 0,3 s là ba lượt dò trượt liên tiếp, và nằm dưới quãng phản xạ của người
  /// (~0,4 s) nên nó không làm chậm được cú bấm nào.
  private static let aimUnlockGraceSeconds: TimeInterval = 0.3

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

  /// Tia bắn từ tâm ngắm ĐANG trúng một bề mặt hay không.
  ///
  /// Đây là thứ duy nhất nói trước cho người dùng biết cú bấm sắp tới sẽ đặt
  /// được điểm hay rơi vào chỗ trống. Xem [refreshAimLock].
  private var aimLocked = false

  /// Lần dò gần nhất TRÚNG, để tính quãng ân hạn khi hạ cờ.
  private var lastAimHitAt: TimeInterval = 0

  /// Lần dò gần nhất CHẠY, để giãn nhịp dò.
  private var lastAimProbeAt: TimeInterval = 0

  private var lastStatus: ArMeasureStatus?
  private var lastLimitedReason: ArMeasureLimitedReason?
  private var lastAimLocked: Bool?
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
    sceneView.session.run(makeConfiguration(), options: options)
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

    let status = currentStatus()
    guard status == .ready || status == .firstPointPlaced else { return .notReady }
    guard let hit = raycastFromReticle() else { return .missed }
    let transform = hit.worldTransform

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

  /// Bỏ điểm chấm gần nhất. Không có điểm nào thì không làm gì.
  ///
  /// Không trả về gì, khác với [placePoint]: app đã biết nó đang có mấy điểm
  /// (từ chính luồng trạng thái), nên "hoàn tác lúc chưa có điểm nào" là một
  /// chuyện app tự chặn được, còn "raycast trượt" thì không.
  func undoPoint() {
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
  func replayLastSample() {
    guard !isStopped else { return }
    if let sample = lastSample {
      output?.arMeasureSession(self, didProduce: sample)
    } else {
      publish(force: true)
    }
  }

  // MARK: - Raycast phân tầng

  /// Bắn tia từ con trỏ giữa màn.
  ///
  /// Hai tầng, đúng thứ tự: `.existingPlaneGeometry` là điểm nằm trên một mặt
  /// phẳng ARKit **đã xác nhận** — chắc nhất, nhưng chỉ có khi mặt ấy đã dò ra.
  /// Trượt thì rơi về `.estimatedPlane`, chỗ ARKit đoán một mặt phẳng từ hình
  /// học quanh tia. Trên máy LiDAR tầng thứ hai cắt vào lưới thật, nên nó chắc
  /// hơn hẳn — cùng một dòng mã, khác nhau ở dưới.
  ///
  /// Trả về CẢ `ARRaycastResult` chứ không phải mỗi `worldTransform`: kết quả
  /// còn chở `target` (tầng nào đã trúng) và `anchor` (mặt phẳng nào, nếu có),
  /// và đây là chỗ DUY NHẤT hai thứ ấy tồn tại. Vứt chúng ở đây thì tầng chẩn
  /// đoán mất đúng hai trường phân biệt "mặt phẳng ARKit đã xác nhận" với "mặt
  /// phẳng nó đoán ra" — mà không lỗi nào nổ, vì mọi thứ còn lại vẫn chạy.
  private func raycastFromReticle() -> ARRaycastResult? {
    let bounds = sceneView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let reticle = CGPoint(x: bounds.midX, y: bounds.midY)

    let targets: [ARRaycastQuery.Target] = [.existingPlaneGeometry, .estimatedPlane]
    for target in targets {
      guard let query = sceneView.raycastQuery(from: reticle, allowing: target, alignment: .any)
      else { continue }
      if let hit = sceneView.session.raycast(query).first {
        return hit
      }
    }
    return nil
  }

  // MARK: - Ghi lại điều kiện lúc chấm

  /// Ảnh chụp điều kiện của MỘT cú chấm. Xem [ArPointDiagnostics].
  ///
  /// Chạy đúng một lần cho mỗi điểm, ngay sau khi tia trúng — không phải mỗi
  /// khung hình. Không có gì trong đây quay lại đụng vào phép đo.
  private func makeDiagnostics(for hit: ARRaycastResult) -> ArPointDiagnostics {
    // Tầng trúng đọc THẲNG từ kết quả. Suy từ thứ tự vòng lặp ở
    // [raycastFromReticle] là chép lại một sự thật ARKit đã nói ra sẵn, và bản
    // chép rời khỏi bản gốc ngay lượt đầu ai đó đổi danh sách tầng mục tiêu.
    let target: ArRaycastTarget?
    switch hit.target {
    case .existingPlaneGeometry: target = .existingPlaneGeometry
    case .existingPlaneInfinite: target = .existingPlaneInfinite
    case .estimatedPlane: target = .estimatedPlane
    @unknown default: target = nil
    }

    let hitColumn = hit.worldTransform.columns.3
    let hitPosition = SIMD3<Float>(hitColumn.x, hitColumn.y, hitColumn.z)

    var cameraDistanceMm: Double?
    var rayAngleDeg: Double?
    // Đọc khung hình hiện tại rồi THẢ ngay: giữ một `ARFrame` là chặn ARKit
    // giao khung mới. `ARCamera` lấy ra không giữ khung.
    if let camera = sceneView.session.currentFrame?.camera {
      let camColumn = camera.transform.columns.3
      let cameraPosition = SIMD3<Float>(camColumn.x, camColumn.y, camColumn.z)
      let toHit = hitPosition - cameraPosition
      let distance = simd_length(toHit)
      if distance.isFinite {
        cameraDistanceMm = Double(distance) * 1000
      }
      if distance > 0 {
        // Trục Y của transform mà raycast trả về LÀ pháp tuyến bề mặt (hợp
        // đồng của `ARRaycastResult`).
        let n = hit.worldTransform.columns.1
        let normal = simd_normalize(SIMD3<Float>(n.x, n.y, n.z))
        let direction = toHit / distance
        // `asin` chứ không `acos`: `dot` cho góc so với PHÁP TUYẾN, mà thứ đọc
        // được bằng mắt là góc so với MẶT PHẲNG. Hai góc bù nhau, nên nhầm ở
        // đây in 63° ra thành 27° — một con số vẫn hợp lệ, vẫn nằm trong 0–90,
        // và không có gì trên màn nói ra là mình đang đọc nhầm cái nào.
        let cosToNormal = min(1, max(0, abs(simd_dot(direction, normal))))
        let radians = asin(cosToNormal)
        if radians.isFinite {
          rayAngleDeg = Double(radians) * 180 / .pi
        }
      }
    }

    var planeAlignment: ArPlaneAlignment?
    var planeWidthMm: Double?
    var planeHeightMm: Double?
    // Không có `ARPlaneAnchor` nghĩa là tia trúng một mặt ƯỚC LƯỢNG. Ba khoá
    // dưới đây vắng mặt trên dây, và Dart đọc ra "không có mặt phẳng".
    if let plane = hit.anchor as? ARPlaneAnchor {
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
      planeAlignment: planeAlignment,
      planeWidthMm: planeWidthMm,
      planeHeightMm: planeHeightMm
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

  /// Dò xem tia từ tâm ngắm có trúng gì không, và cập nhật [aimLocked].
  ///
  /// Trả `true` khi cờ ĐỔI — người gọi dùng nó để khỏi bắn khi không có gì mới.
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
  /// gần giống. Cờ này là một lời hứa về cú bấm sắp tới; hai tia khác nhau là
  /// một lời hứa hão, và nó hỏng theo đúng kiểu tệ nhất — tâm ngắm khoá lại,
  /// người dùng bấm, không có gì xảy ra.
  private func refreshAimLock(now: TimeInterval) -> Bool {
    let was = aimLocked

    // Ngoài hai trạng thái còn chấm được thì cú bấm tới không đặt nổi điểm nào
    // dù tia có trúng hay không — kể cả khi đã đủ hai điểm, lúc mà cờ này hết
    // sạch ý nghĩa. Hạ cờ, và KHÔNG dò: một lượt raycast ở đây là công đổ đi.
    let status = currentStatus()
    guard status == .ready || status == .firstPointPlaced else {
      aimLocked = false
      lastAimHitAt = 0
      return was != aimLocked
    }

    guard now - lastAimProbeAt >= Self.aimProbeIntervalSeconds else { return false }
    lastAimProbeAt = now

    if raycastFromReticle() != nil {
      lastAimHitAt = now
      aimLocked = true
    } else if now - lastAimHitAt >= Self.aimUnlockGraceSeconds {
      // Trượt một lượt chưa đủ để hạ cờ — xem [aimUnlockGraceSeconds].
      aimLocked = false
    }

    return was != aimLocked
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

  /// Vị trí các điểm đã chấm trong hệ toạ độ thế giới, theo thứ tự chấm.
  ///
  /// Đọc từ chính `anchors` — cùng nguồn với [currentDistanceMm], nên hình vẽ
  /// và con số không bao giờ nói hai chuyện khác nhau.
  private func currentPoints() -> [SIMD3<Float>] {
    anchors.map {
      let column = $0.transform.columns.3
      return SIMD3<Float>(column.x, column.y, column.z)
    }
  }

  /// Khoảng cách giữa hai điểm, tính bằng milimét. `nil` khi chưa đủ hai điểm.
  private func currentDistanceMm() -> Double? {
    guard anchors.count == 2 else { return nil }
    let a = anchors[0].transform.columns.3
    let b = anchors[1].transform.columns.3
    let metres = simd_distance(SIMD3(a.x, a.y, a.z), SIMD3(b.x, b.y, b.z))
    return Double(metres) * 1000
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

  // MARK: - Bắn

  private func publish(force: Bool = false) {
    guard !isStopped else { return }

    trailingEmit?.cancel()
    trailingEmit = nil

    let status = currentStatus()

    // Vẽ TRƯỚC mọi nhánh nén ở dưới. Hình phải bám hai điểm ngay cả ở những
    // lượt con số không đáng gửi đi (đổi dưới 0,5 mm, hoặc chưa tới nhịp 15 Hz)
    // — để nó rơi vào nhánh nén thì đoạn thẳng giật theo nhịp KÊNH thay vì theo
    // khung hình, và mắt đọc ra ngay.
    //
    // Ẩn ở đúng ba trạng thái mà hệ toạ độ không còn đáng tin, cùng lý lẽ với
    // việc che con số: hai chấm vẫn nằm nguyên chỗ cũ trong một hệ toạ độ đã
    // trôi thì chúng chỉ vào sai vật, mà trông vẫn như đang chỉ đúng.
    // `needsMotion` KHÔNG nằm trong danh sách: nó chớp lên vì nửa giây rung tay,
    // và cho hình biến mất từng nhịp như thế còn khó đọc hơn.
    let coordinatesAreTrustworthy =
      status != .interrupted && status != .trackingLost && status != .cameraUnauthorized
    measureNodes.update(points: coordinatesAreTrustworthy ? currentPoints() : [])

    let limitedReason = currentLimitedReason()
    // Số đo chỉ đi kèm khi hệ toạ độ còn đáng tin. Mất bám hay đang gián đoạn
    // thì hai điểm vẫn còn đó, nhưng khoảng cách giữa chúng đã không còn nghĩa
    // — spec gọi đây là "che con số đang trôi".
    let mm = status == .measured ? currentDistanceMm() : nil

    // Cờ ngắm chỉ có nghĩa ở hai trạng thái còn chấm được, và hai điểm đã đủ
    // thì nó hết nghĩa hẳn. [refreshAimLock] đã hạ cờ ở mọi trạng thái khác,
    // nhưng nó chỉ chạy khi CÓ khung hình — mà `publish` còn được gọi từ những
    // đường không có khung hình nào (lỗi phiên, `pause`, mất quyền camera).
    // Chặn thêm một lượt ở đây thì không còn đường nào để một cờ cũ lọt ra
    // ngoài kênh.
    let aimLocked = (status == .ready || status == .firstPointPlaced) && self.aimLocked
    let now = CACurrentMediaTime()

    // `limitedReason` và `aimLocked` nằm trong điều kiện gộp cùng `status`, và
    // cả hai vì cùng một lý do: bộ nén ở dưới neo vào "số đo đổi quá 0,5 mm",
    // mà cả hai khoá này đổi ĐƯỢC trong khi số đo không đổi một chút nào.
    //
    // Với `aimLocked` thì còn mạnh hơn thế: lúc nó đổi, phần lớn thời gian
    // **chưa có điểm nào**, nên `mm` là `nil` và nhánh dưới `return` thẳng.
    // Không đưa nó lên đây thì lượt khoá đầu tiên — đúng cái tín hiệu bảo người
    // dùng bấm được rồi — bị nuốt trọn, và tâm ngắm câm đúng lúc nó cần nói.
    //
    // Cái giá là cờ đổi thì bỏ qua cả nhịp 15 Hz. Chấp nhận được vì trần đã bị
    // chặn từ chỗ khác: lượt dò chỉ chạy 10 Hz, và quãng ân hạn khi hạ cờ
    // (0,3 s) kéo trần một chu kỳ khoá-mở xuống dưới 7 lần/giây.
    if !force, status == lastStatus, limitedReason == lastLimitedReason,
      aimLocked == lastAimLocked
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
    // `placePoint` ghi ngay lúc thêm anchor) — giữ CHỖ chứ không rút ngắn danh
    // sách, vì rút ngắn là điểm hai trượt lên chỗ điểm một.
    //
    // Không cần đưa vào bộ nén ở trên: chẩn đoán chỉ đổi khi [anchors] đổi, và
    // mọi đường đổi [anchors] đều `publish(force: true)`.
    if !anchors.isEmpty {
      sample["diagnostics"] = [
        "points": anchors.map { pointDiagnostics[$0.identifier]?.payload ?? [:] }
      ]
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
    lastAimLocked = aimLocked
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
    // [refreshAimLock] tự giãn nhịp xuống 10 Hz và tự bỏ qua khi trạng thái
    // không cho chấm, nên đây không phải một lượt raycast mỗi khung hình.
    var shouldPublish = refreshAimLock(now: CACurrentMediaTime())

    // Phần số đo vẫn chặn y như cũ, chỉ là chặn SAU lượt dò chứ không trước.
    // Không giữ `frame` lại quá lời gọi này: giữ một `ARFrame` là chặn ARKit
    // giao khung mới. Chỉ hai `ARAnchor` được lấy ra, và chúng không giữ khung.
    if anchors.count == 2, adoptUpdatedAnchors(frame.anchors) {
      shouldPublish = true
    }

    guard shouldPublish else { return }
    publish()
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
    if self.anchors.count < 2 { lastMm = nil }
    publish(force: true)
  }
}
