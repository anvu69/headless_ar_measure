import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Trạng thái của một phiên đo AR.
///
/// Tám giá trị đủ để app vẽ mọi màn hình mà không cần hỏi thêm gì gói: hai
/// giá trị đầu là trước khi đo được, giữa là đang đo, ba giá trị cuối là các
/// đường rơi ra ngoài ý muốn của người dùng (cuộc gọi đến, xuống nền, quyền
/// camera bị tắt giữa chừng).
enum ArMeasureStatus {
  initializing,
  needsMotion,
  ready,
  firstPointPlaced,
  measured,
  trackingLost,
  interrupted,
  cameraUnauthorized,
}

/// Một số đo khoảng cách.
class ArMeasurement {
  const ArMeasurement({
    required this.mm,
    required this.tolMm,
    required this.snappedToEdge,
  });

  /// Khoảng cách, tính bằng milimét.
  final double mm;

  /// Sai số ± tính bằng milimét.
  final double tolMm;

  /// Điểm cuối có hít vào một cạnh do ARKit dò ra hay không.
  final bool snappedToEdge;
}

/// Máy này chạy được ARKit tới đâu.
class ArAvailability {
  const ArAvailability({
    required this.arSupported,
    required this.hasSceneDepth,
  });

  /// `ARWorldTrackingConfiguration.isSupported`.
  final bool arSupported;

  /// `supportsSceneReconstruction(.mesh)` — có LiDAR để dò bề mặt hay không.
  final bool hasSceneDepth;
}

/// Một lần đọc từ kênh sự kiện: trạng thái, kèm số đo nếu trạng thái đó có.
class ArMeasureSample {
  const ArMeasureSample({required this.status, this.measurement});

  final ArMeasureStatus status;

  /// `null` ở mọi trạng thái không mang số đo (vd. [ArMeasureStatus.ready]).
  final ArMeasurement? measurement;
}

/// Cửa vào duy nhất tới phiên đo AR.
///
/// Trung tính hoàn toàn: không có gì trong lớp này biết cung là gì, hay có
/// một chuỗi tiếng Việt nào của sản phẩm. Nó đo khoảng cách và trả số.
///
/// Toàn bộ mặt cắt là tĩnh — không có trạng thái nào giữ ở phía Dart để giữ.
/// Gói không có gì để khởi tạo hai lần cho khác nhau.
class ArMeasure {
  ArMeasure._();

  static const String methodChannelName = 'headless_ar_measure/method';
  static const String eventChannelName = 'headless_ar_measure/stream';

  /// `viewType` truyền cho [UiKitView] khi dựng [ArMeasureView].
  static const String viewType = 'headless_ar_measure/view';

  static const MethodChannel _method = MethodChannel(methodChannelName);

  /// Máy này chạy được ARKit tới đâu. Hỏi LÚC CHẠY, không suy từ đời máy.
  ///
  /// Kênh hỏng thì trả về một [ArAvailability] toàn `false`: chạy trên máy
  /// ảo, chạy trước khi plugin đăng ký xong, hoặc bản dựng thiếu tệp Swift
  /// đều rơi vào đây. Ném thì app không biết đường nào mà ẩn hay hiện một
  /// nút, trong khi thứ đúng phải làm là coi như không có ARKit.
  static Future<ArAvailability> isAvailable() async {
    try {
      final raw = await _method.invokeMethod<Map<Object?, Object?>>(
        'isAvailable',
      );
      final map = raw ?? const <Object?, Object?>{};
      return ArAvailability(
        arSupported: map['arSupported'] as bool? ?? false,
        hasSceneDepth: map['hasSceneDepth'] as bool? ?? false,
      );
    } catch (_) {
      return const ArAvailability(arSupported: false, hasSceneDepth: false);
    }
  }

  /// Dựng mẫu từ dữ liệu kênh. Công khai để test được mà không cần kênh thật.
  ///
  /// `status` lạ hoặc thiếu thì trả `null` — dữ liệu từ tầng nền không phải
  /// thứ mình kiểm soát, và ném ở đây thì cả luồng chết theo một khung hỏng.
  /// Thiếu, hoặc sai kiểu, `mm`/`tolMm`/`snappedToEdge` thì
  /// [ArMeasureSample.measurement] về `null` (hoặc `snappedToEdge` về
  /// `false`) chứ không làm hỏng cả mẫu, và tuyệt đối không ném: nhiều trạng
  /// thái (vd. [ArMeasureStatus.ready]) đúng ra là không mang số đo.
  static ArMeasureSample? parseSample(Map<Object?, Object?> raw) {
    final status = switch (raw['status']) {
      'initializing' => ArMeasureStatus.initializing,
      'needsMotion' => ArMeasureStatus.needsMotion,
      'ready' => ArMeasureStatus.ready,
      'firstPointPlaced' => ArMeasureStatus.firstPointPlaced,
      'measured' => ArMeasureStatus.measured,
      'trackingLost' => ArMeasureStatus.trackingLost,
      'interrupted' => ArMeasureStatus.interrupted,
      'cameraUnauthorized' => ArMeasureStatus.cameraUnauthorized,
      _ => null,
    };
    if (status == null) return null;

    // Kiểm kiểu trước khi ép: `as num?`/`as bool?` ném _TypeError khi tầng
    // nền gửi sai kiểu (vd. 'mm': 'not-a-number'), và dữ liệu từ tầng nền
    // không phải thứ mình kiểm soát. Sai kiểu bị coi như thiếu trường — cùng
    // một lối rẽ với "thiếu mm/tolMm" ở trên, không phải một nhánh lỗi riêng.
    final rawMm = raw['mm'];
    final mm = rawMm is num ? rawMm.toDouble() : null;
    final rawTolMm = raw['tolMm'];
    final tolMm = rawTolMm is num ? rawTolMm.toDouble() : null;
    final rawSnapped = raw['snappedToEdge'];
    final snappedToEdge = rawSnapped is bool ? rawSnapped : false;
    final measurement = (mm == null || tolMm == null)
        ? null
        : ArMeasurement(mm: mm, tolMm: tolMm, snappedToEdge: snappedToEdge);

    return ArMeasureSample(status: status, measurement: measurement);
  }
}

/// Widget bọc mặt camera AR của nền tảng.
///
/// Một [UiKitView] mỏng quanh `ARSCNView` phía Swift. Gói không vẽ chữ,
/// không vẽ lớp phủ — mọi con số, mọi nhãn là việc của app.
class ArMeasureView extends StatelessWidget {
  const ArMeasureView({super.key, this.onPlatformViewCreated});

  /// Báo ra ngoài id của platform view vừa sinh, để phía Dart gọi các lệnh
  /// kênh nhắm đúng view đó.
  final PlatformViewCreatedCallback? onPlatformViewCreated;

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: ArMeasure.viewType,
      onPlatformViewCreated: onPlatformViewCreated,
    );
  }
}
