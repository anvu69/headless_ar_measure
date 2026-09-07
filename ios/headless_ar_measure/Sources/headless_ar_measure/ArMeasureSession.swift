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

/// Đường ra của một phiên: một map đã sẵn sàng cho `EventChannel`.
///
/// Là protocol chứ không phải closure để phía nhận giữ được **yếu**. Một
/// closure bắt `self` mạnh ở đây là đúng cái vòng giữ view sống mãi mà luật
/// vòng đời số 2 nói tới.
protocol ArMeasureSessionOutput: AnyObject {
  func arMeasureSession(_ session: ArMeasureSession, didProduce sample: [String: Any])
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

  // MARK: - Ngưỡng bắn

  /// Số đo đổi ít hơn ngần này thì không bắn.
  ///
  /// ARKit tinh chỉnh hệ toạ độ liên tục, và mỗi lượt tinh chỉnh là một lượt vẽ
  /// lại bên Dart. 0,5 mm nằm **dưới sàn nhiễu** của chính phép đo (dung sai
  /// nhỏ nhất gói này trả ra là ±2 mm trên máy LiDAR, ±5 mm trên máy thường),
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

  // MARK: - Trạng thái

  /// Hai điểm đã chấm, theo thứ tự chấm. Nhiều nhất hai.
  private var anchors: [ARAnchor] = []

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

  private var lastStatus: ArMeasureStatus?
  private var lastLimitedReason: ArMeasureLimitedReason?
  private var lastMm: Double?
  private var lastEmitAt: TimeInterval = 0

  /// Mẫu bắn ra gần nhất, để phát lại cho người nghe tới muộn.
  private var lastSample: [String: Any]?

  // MARK: - Vòng đời

  init(frame: CGRect) {
    sceneView = ARSCNView(frame: frame)
    super.init()

    sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Gói KHÔNG vẽ chữ và không vẽ hình: mọi lớp phủ là việc của Flutter. Ở đây
    // `ARSCNView` chỉ còn làm đúng một việc — dựng nền camera.
    sceneView.debugOptions = []
    sceneView.automaticallyUpdatesLighting = false

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
    sceneView.session.delegate = nil
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
    if #available(iOS 13.4, *),
      ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    {
      config.sceneReconstruction = .mesh
    }
    return config
  }

  private func start(options: ARSession.RunOptions = []) {
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
    case .notDetermined, .authorized:
      break
    @unknown default:
      break
    }

    failure = nil
    failureIsRecoverable = true
    sceneView.session.run(makeConfiguration(), options: options)
    publish(force: true)
  }

  // MARK: - Lệnh

  /// Chấm một điểm tại con trỏ giữa màn.
  ///
  /// Trả `false` khi **không có điểm nào được đặt**: raycast trượt (chĩa vào
  /// trời, vào mặt kính, vào chỗ chưa có đủ điểm đặc trưng), hoặc phiên đang ở
  /// trạng thái không cho chấm, hoặc đã đủ hai điểm.
  ///
  /// Vì sao là giá trị trả về chứ không phải một trạng thái bắn ra: raycast
  /// trượt **không đổi trạng thái gì cả** — phiên vẫn `ready`, vẫn đúng như một
  /// giây trước. Bắn `ready` thêm một lần nữa để nói "vừa rồi trượt" là gửi một
  /// tin không phân biệt được với một lần bám lại bình thường, và tầng Dart
  /// không có cách nào tách hai chuyện ấy. Giá trị trả về đi thẳng về đúng cú
  /// chạm đã gây ra nó, nên app rung/nháy được ngay tại chỗ.
  func placePoint() -> Bool {
    guard !isStopped else { return false }

    let status = currentStatus()
    guard status == .ready || status == .firstPointPlaced else { return false }
    guard let transform = raycastFromReticle() else { return false }

    // ARAnchor chứ không phải `simd_float3` thuần. ARKit chỉnh lại hệ toạ độ
    // thế giới mỗi lần nó hiểu thêm về căn phòng (gộp mặt phẳng, đóng vòng,
    // nối lại vị trí sau gián đoạn). Một `simd_float3` lưu lại là một con số
    // đông cứng trong hệ toạ độ CŨ: sau một lượt chỉnh, hai điểm trôi khỏi chỗ
    // thật mà khoảng cách giữa chúng vẫn trông rất bình thường — sai mà không
    // có dấu hiệu. Transform của `ARAnchor` thì được ARKit cập nhật theo, nên
    // đọc lại nó mỗi lượt cho ra đúng "số đo TRÔI" mà spec muốn: cái trôi ấy
    // CHÍNH LÀ lượt tinh chỉnh, hiện ra cho người dùng thấy nó đứng dần lại.
    let anchor = ARAnchor(name: "headless_ar_measure.point", transform: transform)
    anchors.append(anchor)
    sceneView.session.add(anchor: anchor)

    publish(force: true)
    return true
  }

  /// Bỏ điểm chấm gần nhất. Không có điểm nào thì không làm gì.
  ///
  /// Không trả về gì, khác với [placePoint]: app đã biết nó đang có mấy điểm
  /// (từ chính luồng trạng thái), nên "hoàn tác lúc chưa có điểm nào" là một
  /// chuyện app tự chặn được, còn "raycast trượt" thì không.
  func undoPoint() {
    guard !isStopped, let last = anchors.popLast() else { return }
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
  private func raycastFromReticle() -> simd_float4x4? {
    let bounds = sceneView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let reticle = CGPoint(x: bounds.midX, y: bounds.midY)

    let targets: [ARRaycastQuery.Target] = [.existingPlaneGeometry, .estimatedPlane]
    for target in targets {
      guard let query = sceneView.raycastQuery(from: reticle, allowing: target, alignment: .any)
      else { continue }
      if let hit = sceneView.session.raycast(query).first {
        return hit.worldTransform
      }
    }
    return nil
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
    let limitedReason = currentLimitedReason()
    // Số đo chỉ đi kèm khi hệ toạ độ còn đáng tin. Mất bám hay đang gián đoạn
    // thì hai điểm vẫn còn đó, nhưng khoảng cách giữa chúng đã không còn nghĩa
    // — spec gọi đây là "che con số đang trôi".
    let mm = status == .measured ? currentDistanceMm() : nil
    let now = CACurrentMediaTime()

    // `limitedReason` nằm trong điều kiện gộp cùng `status`: đổi từ "rê quá
    // nhanh" sang "thiếu vân" mà không đổi trạng thái là đổi hẳn câu màn phải
    // nói, nên nó không được rơi vào nhánh nén.
    if !force, status == lastStatus, limitedReason == lastLimitedReason {
      guard let mm else { return }
      if let last = lastMm, abs(mm - last) < Self.minChangeMm { return }

      let waited = now - lastEmitAt
      if waited < Self.minIntervalSeconds {
        // Trễ nhịp thì HẸN LẠI, không bỏ. Bỏ thẳng thì lượt tinh chỉnh cuối
        // cùng — đúng lượt con số đứng lại, tức tín hiệu để người dùng bấm chốt
        // — có thể không bao giờ tới Dart, vì ARKit chỉ báo khi nó thật sự
        // chỉnh chứ không báo đều đặn.
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
    if let mm {
      sample["mm"] = mm
      sample["tolMm"] = toleranceMm(forMm: mm)
      // Hít cạnh chưa dựng (nó nằm sau một cờ tắt cho tới khi đo được tỉ lệ
      // trúng trên máy thật). Trường vẫn gửi để khuôn dây không đổi lúc nó vào.
      sample["snappedToEdge"] = false
    }

    lastStatus = status
    lastLimitedReason = limitedReason
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

  private func clearAnchors() {
    for anchor in anchors {
      sceneView.session.remove(anchor: anchor)
    }
    anchors.removeAll()
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

  func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    // Chỉ quan tâm hai điểm của mình. Với `sceneReconstruction = .mesh`, mảng
    // này chở hàng trăm `ARMeshAnchor` mỗi lượt — lọc trước, tính sau.
    let ids = Set(self.anchors.map(\.identifier))
    var changed = false
    for updated in anchors where ids.contains(updated.identifier) {
      if let index = self.anchors.firstIndex(where: { $0.identifier == updated.identifier }) {
        self.anchors[index] = updated
        changed = true
      }
    }
    if changed { publish() }
  }

  func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
    // ARKit tự bỏ điểm neo (hiếm — chủ yếu là hệ quả của `.removeExistingAnchors`
    // do chính lớp này gửi). Bỏ đúng cái nó bỏ, không bỏ thêm: còn lại một điểm
    // thì trạng thái tự về `firstPointPlaced`, và người dùng chấm tiếp là xong.
    // Bỏ cả hai "cho chắc" là xoá một điểm ARKit không hề nói là sai.
    let removed = Set(anchors.map(\.identifier))
    let before = self.anchors.count
    self.anchors.removeAll { removed.contains($0.identifier) }
    guard self.anchors.count != before else { return }
    if self.anchors.count < 2 { lastMm = nil }
    publish(force: true)
  }
}
