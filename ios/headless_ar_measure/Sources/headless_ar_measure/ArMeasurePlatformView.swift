import Flutter
import UIKit

/// Dựng một phiên đo mới cho mỗi platform view Flutter yêu cầu.
///
/// **Factory không giữ view nào nó đã tạo.** Engine giữ mạnh mọi factory
/// *vĩnh viễn* — `_factories` không bao giờ bị xoá — và đã giữ mạnh mỗi view
/// cho tới khi Dart gọi dispose. Factory giữ thêm một tham chiếu nữa là rò
/// không có đường gỡ: view sống bằng tuổi thọ của engine, và cùng với nó là
/// một `ARSession` đang mở camera.
///
/// Vì cùng lý do đó, ở đây cũng không có `ARSession` dùng chung: mỗi lần
/// [create] dựng một `ARSCNView` mới và trao trọn quyền sở hữu cho view.
final class ArMeasureViewFactory: NSObject, FlutterPlatformViewFactory {
  /// Giữ MẠNH, và đây là một lượt SỬA chứ không phải nếp cũ.
  ///
  /// Bản trước giữ yếu với lý lẽ "plugin sống suốt đời engine nên không cần
  /// giữ". Lý lẽ ấy đúng (registrar giữ plugin qua khối lệnh mà
  /// `addMethodCallDelegate` gắn vào messenger), nhưng nó bắt một đường CHÍNH —
  /// `create` là chỗ duy nhất nối view mới vào sổ đăng ký của plugin — treo vào
  /// một giả định về nội bộ engine. Nếu giả định ấy sai một ngày nào đó thì
  /// `plugin?` là `nil`, `attach` không chạy, và **không có lỗi nào nổ**: view
  /// vẫn dựng, camera vẫn chạy, chỉ có luồng trạng thái là câm.
  ///
  /// Giữ mạnh không dựng nổi vòng: plugin KHÔNG trỏ ngược về factory (nó chỉ
  /// giữ các view, và giữ yếu). Engine giữ factory vĩnh viễn, plugin cũng sống
  /// vĩnh viễn — nên đây đổi một tham chiếu yếu lấy một đường đi chắc chắn, chứ
  /// không đổi lấy một chỗ rò.
  private let plugin: HeadlessArMeasurePlugin

  init(plugin: HeadlessArMeasurePlugin) {
    self.plugin = plugin
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let view = ArMeasurePlatformView(frame: frame, viewId: viewId)
    // Trao view cho plugin để lệnh kênh tìm được nó. Sổ đăng ký bên ấy giữ
    // YẾU — xem `HeadlessArMeasurePlugin.attach`.
    plugin.attach(view)
    return view
  }
}

/// Vỏ `FlutterPlatformView` quanh một [ArMeasureSession].
///
/// Protocol này có đúng một phương thức, [view]. iOS **không có** callback
/// dispose cho platform view — đó là lý do phiên phải được dừng bằng một lệnh
/// kênh tường minh, gọi từ `State.dispose()` bên Dart.
final class ArMeasurePlatformView: NSObject, FlutterPlatformView {
  let viewId: Int64

  /// View sở hữu phiên mạnh; phiên sở hữu `ARSCNView` mạnh. Không ai khác giữ
  /// mạnh hai thứ này, nên khi engine thả view thì camera tắt theo.
  let session: ArMeasureSession

  init(frame: CGRect, viewId: Int64) {
    self.viewId = viewId
    self.session = ArMeasureSession(frame: frame)
    super.init()
  }

  func view() -> UIView {
    session.sceneView
  }
}
