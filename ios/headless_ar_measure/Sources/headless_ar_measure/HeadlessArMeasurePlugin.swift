import ARKit
import Flutter
import UIKit

/// Cửa vào duy nhất của gói: hai kênh và một factory platform view.
///
/// Tách khỏi app thành gói riêng vì một lý do rất cụ thể: `project.pbxproj`
/// của app chưa dùng nhóm đồng bộ theo thư mục, nên một tệp `.swift` mới đặt
/// vào `ios/Runner/` sẽ KHÔNG vào target mà cũng không có lỗi nào nổ — nó chỉ
/// lặng lẽ không được biên dịch. Gói plugin có podspec riêng, nên mọi tệp
/// Swift trong nó đều được biên dịch.
///
/// **Không hàm nào trong tệp này ném về Dart.** Mọi lỗi trả thành giá trị canh
/// gác: `placePoint` trượt trả `false`, lệnh nhắm vào một view đã chết trả
/// `nil`, `isAvailable` trên máy không chạy được ARKit trả hai lần `false`.
/// Tầng Dart gọi những hàm này để quyết định vẽ gì; ném ở đây thì app không
/// biết đường nào mà ẩn hay hiện một nút.
public class HeadlessArMeasurePlugin: NSObject, FlutterPlugin {
  private static let methodChannelName = "headless_ar_measure/method"
  private static let eventChannelName = "headless_ar_measure/stream"
  private static let overlayChannelName = "headless_ar_measure/overlay"
  private static let viewTypeId = "headless_ar_measure/view"

  private var sink: FlutterEventSink?

  /// Đầu ra của kênh lớp phủ. Xem [ArMeasureOverlayChannel].
  ///
  /// Giữ MẠNH: plugin cần gọi vào nó ở mỗi khung lớp phủ, và chiều ngược lại
  /// giữ yếu nên không có vòng nào.
  private let overlayChannel = ArMeasureOverlayChannel()

  /// Sổ đăng ký platform view, GIỮ YẾU.
  ///
  /// Luật vòng đời số 2 nói `setMethodCallHandler` phải bắt `self` yếu, vì một
  /// tham chiếu phương thức instance truyền thẳng dựng ra một vòng giữ view
  /// sống mãi. Gói này không dựng kênh riêng cho từng view — chỉ có một kênh
  /// chung, và lệnh mang theo `viewId` — nên chỗ dễ dính bẫy không nằm ở
  /// `setMethodCallHandler` nữa. Nó chuyển sang **đúng cái sổ này**: plugin
  /// sống suốt đời engine, nên một tham chiếu mạnh ở đây là một platform view
  /// không bao giờ chết, kèm một camera không bao giờ tắt.
  ///
  /// Giữ yếu thì tệ nhất cũng chỉ là một lệnh rơi vào chỗ trống, và [prune]
  /// dọn hàng chết mỗi lần đụng tới sổ.
  private var views: [Int64: WeakView] = [:]

  private final class WeakView {
    weak var value: ArMeasurePlatformView?
    init(_ value: ArMeasurePlatformView) { self.value = value }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = HeadlessArMeasurePlugin()

    let method = FlutterMethodChannel(
      name: methodChannelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: method)

    let events = FlutterEventChannel(
      name: eventChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)

    // Kênh THỨ HAI, chỉ chở lớp phủ. Nhịp của nó (30 Hz) gấp đôi nhịp trần của
    // kênh trên, và phần lớn khung của nó không mang một thay đổi trạng thái
    // nào — gộp chung là bắt mọi người nghe trạng thái lọc ba mươi khung mỗi
    // giây để tìm một thay đổi mỗi vài giây.
    //
    // Cần một đối tượng riêng vì `FlutterStreamHandler` chỉ có MỘT bộ
    // `onListen`/`onCancel`, và `instance` đã dùng nó cho kênh trên.
    instance.overlayChannel.plugin = instance
    let overlayEvents = FlutterEventChannel(
      name: overlayChannelName, binaryMessenger: registrar.messenger())
    overlayEvents.setStreamHandler(instance.overlayChannel)

    registrar.register(ArMeasureViewFactory(plugin: instance), withId: viewTypeId)
  }

  /// Phát lại khung lớp phủ gần nhất của mọi phiên đang sống.
  ///
  /// Gọi từ [ArMeasureOverlayChannel] lúc có người nghe mới. Kênh lớp phủ KHÔNG
  /// bắn lại một khung y hệt khung trước, nên không có dòng này thì một người
  /// nghe tới muộn trong lúc máy nằm yên có thể đợi vô thời hạn.
  func replayLastOverlay() {
    prune()
    for entry in views.values {
      entry.value?.session.replayLastOverlay()
    }
  }

  /// Ghi một view vừa dựng vào sổ. Gọi từ [ArMeasureViewFactory].
  func attach(_ view: ArMeasurePlatformView) {
    prune()
    views[view.viewId] = WeakView(view)
    view.session.output = self
    // Người nghe có thể đã gắn từ trước khi view này dựng xong; phát ngay mẫu
    // đầu tiên để màn không đứng trắng.
    view.session.replayLastSample()
  }

  // MARK: - Kênh lệnh

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(Self.availability())

    case "placePoint":
      // Giá trị canh gác là `.notReady`, KHÔNG phải `.missed`: không tìm thấy
      // view nghĩa là không có phiên nào — và lời khuyên đi kèm `.missed` ("rê
      // máy quanh vật cho tới khi tâm ngắm khoá lại") mời người dùng rê máy cả
      // ngày cho một kênh đã chết. "Chưa chấm được" thì đúng ở cả hai đường.
      result((session(for: call)?.placePoint() ?? .notReady).rawValue)

    case "undoPoint":
      session(for: call)?.undoPoint()
      result(nil)

    case "reset":
      session(for: call)?.reset()
      result(nil)

    case "pause":
      session(for: call)?.pause()
      result(nil)

    case "resume":
      session(for: call)?.resume()
      result(nil)

    case "dispose":
      // Đường CHÍNH để tắt camera. iOS không có callback dispose cho platform
      // view, nên nếu Dart không gọi tới đây thì phiên chỉ chết khi engine
      // tình cờ thả view — và việc xoá thật còn bị hoãn tới khung hình có
      // platform view kế tiếp.
      if let id = viewId(from: call) {
        views.removeValue(forKey: id)?.value?.session.stop()
      }
      prune()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Máy này chạy được ARKit tới đâu. Hỏi LÚC CHẠY, không suy từ đời máy.
  private static func availability() -> [String: Any] {
    var hasSceneDepth = false
    if #available(iOS 13.4, *) {
      hasSceneDepth = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    return [
      "arSupported": ARWorldTrackingConfiguration.isSupported,
      "hasSceneDepth": hasSceneDepth,
    ]
  }

  private func viewId(from call: FlutterMethodCall) -> Int64? {
    guard let args = call.arguments as? [String: Any] else { return nil }
    // Kênh chuẩn của Flutter gửi số nguyên Dart về Swift dưới dạng `NSNumber`;
    // ép qua `Int64` trực tiếp trượt ở bản 32-bit, nên đi vòng qua `NSNumber`.
    guard let raw = args["viewId"] as? NSNumber else { return nil }
    return raw.int64Value
  }

  private func session(for call: FlutterMethodCall) -> ArMeasureSession? {
    prune()
    guard let id = viewId(from: call) else { return nil }
    return views[id]?.value?.session
  }

  /// Bỏ những hàng mà view đằng sau đã chết.
  private func prune() {
    views = views.filter { $0.value.value != nil }
  }
}

// MARK: - Kênh sự kiện

extension HeadlessArMeasurePlugin: FlutterStreamHandler {
  public func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    prune()
    // Người nghe tới muộn hơn view là chuyện thường: `UiKitView` dựng view ở
    // khung hình đầu, còn `Stream` chỉ gắn khi Dart thật sự listen. Không phát
    // lại thì màn đứng ở "chưa có mẫu nào" cho tới lần ARKit đổi trạng thái kế
    // tiếp — có thể là vài giây, và trông y hệt một kênh chết.
    for entry in views.values {
      entry.value?.session.replayLastSample()
    }
    return nil
  }

  public func onCancel(withArguments _: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

// MARK: - Đường ra của phiên

extension HeadlessArMeasurePlugin: ArMeasureSessionOutput {
  func arMeasureSession(_ session: ArMeasureSession, didProduce sample: [String: Any]) {
    // Không có người nghe thì bỏ mẫu. `FlutterEventSink` chỉ được gọi trên
    // luồng nền tảng, và mọi thứ gọi tới đây đã ở trên luồng chính
    // (`ArMeasureSession` đặt `delegateQueue = .main` chính vì việc này).
    sink?(sample)
  }

  func arMeasureSession(_ session: ArMeasureSession, didProduceOverlay frame: [String: Any]) {
    overlayChannel.send(frame)
  }
}

// MARK: - Kênh sự kiện thứ hai

/// Đầu ra của kênh lớp phủ.
///
/// Một lớp riêng chỉ vì một ràng buộc của khuôn: `FlutterStreamHandler` có đúng
/// MỘT bộ `onListen`/`onCancel`, và [HeadlessArMeasurePlugin] đã dùng bộ ấy cho
/// kênh trạng thái. Không có logic nào ở đây ngoài việc giữ một `sink`.
final class ArMeasureOverlayChannel: NSObject, FlutterStreamHandler {
  /// Giữ YẾU, dù plugin sống suốt đời engine: kênh này bị chính plugin giữ
  /// mạnh, nên một tham chiếu mạnh ngược lại là một vòng — và luật vòng đời số
  /// 2 của gói không có ngoại lệ cho "đằng nào cũng sống mãi".
  weak var plugin: HeadlessArMeasurePlugin?

  private var sink: FlutterEventSink?

  func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    // Kênh này KHÔNG bắn lại một khung y hệt khung trước, nên người nghe tới
    // muộn trong lúc máy nằm yên có thể đợi vô thời hạn. Xem
    // `ArMeasureSession.replayLastOverlay`.
    plugin?.replayLastOverlay()
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  /// Đẩy một khung lên Dart. Không có người nghe thì bỏ khung — lớp phủ là thứ
  /// vẽ được ngay ở khung sau, không có gì để dồn lại.
  func send(_ frame: [String: Any]) {
    sink?(frame)
  }
}
