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

/// Vì sao ARKit đang bám hạn chế.
///
/// Chỉ có nghĩa khi [ArMeasureSample.status] là [ArMeasureStatus.needsMotion].
/// Hai lý do dưới đây đổ chung vào một trạng thái vì cả hai đều là "đang không
/// đo được, chưa hỏng hẳn" — nhưng cách gỡ thì **ngược nhau**, nên trạng thái
/// một mình không đủ để màn nói đúng câu. Đây là lý do trường này tồn tại chứ
/// không phải một trạng thái thứ chín.
enum ArMeasureLimitedReason {
  /// Máy đang bị rê quá nhanh. Câu đúng: **chậm lại**.
  excessiveMotion,

  /// Cảnh quá trơn, thiếu vân để bám. Câu đúng: **rê quanh tìm bề mặt có vân**
  /// — tức là bảo người dùng làm đúng cái mà [excessiveMotion] bảo họ đừng làm.
  insufficientFeatures,
}

/// Chuyện gì đã xảy ra với một lời gọi [ArMeasureController.placePoint].
///
/// Ba trong bốn giá trị đều là "không có điểm nào được đặt", và chúng tách nhau
/// ra vì ba lời khuyên đi kèm **ngược nhau**. Một `bool` gộp cả ba lại thì màn
/// chỉ còn một câu để nói và sai hai phần ba số lần.
enum ArMeasurePlaceResult {
  /// Điểm đã đặt.
  placed,

  /// Tia bắn ra không trúng gì.
  ///
  /// Câu đúng: **rê máy chậm quanh vật cho tới khi tâm ngắm khoá lại**. Kèm
  /// theo [ArMeasureSample.aimLocked], đây là đường duy nhất để một cú bấm
  /// trượt không trông giống một cái nút hỏng.
  missed,

  /// Phiên đang ở trạng thái không cho chấm.
  ///
  /// Câu đúng nằm ở chính [ArMeasureSample.status] đang bắn ra — đang khởi
  /// động, đang cần rê máy, đang gián đoạn, hay mất quyền camera.
  ///
  /// Cũng là giá trị trả về khi kênh không nói được gì: thiếu plugin, view đã
  /// chết, hoặc một bản Swift cũ trả về một kiểu khác. Không phải [missed] —
  /// mời người dùng rê máy để cứu một kênh đã chết là bắt họ rê mãi mãi.
  notReady,

  /// Đã đủ hai điểm rồi.
  ///
  /// Câu đúng: **đã đủ hai điểm, bấm Chốt hoặc Hoàn tác**. Giá trị này đi trước
  /// [notReady]: hai điểm đã nằm đó thì câu ấy đúng kể cả lúc ARKit đang rung.
  alreadyComplete,
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
  ///
  /// **CHƯA ĐƯỢC TÍNH.** Tầng Swift gán cứng `false` cho mọi mẫu — hít cạnh
  /// nằm sau một cờ tắt cho tới khi đo được tỉ lệ trúng trên máy thật. Trường
  /// tồn tại để khuôn dây không đổi lúc nó vào.
  ///
  /// Đừng đọc nó như dữ liệu, và nhất là đừng đọc nó như "điểm này KHÔNG nằm
  /// trên cạnh nào" — đó là một khẳng định mà chưa có phép tính nào đứng sau.
  /// Thứ nói được điều kiện thật của mỗi điểm là [ArMeasureSample.diagnostics].
  final bool snappedToEdge;
}

/// Tầng mục tiêu mà tia ĐÃ trúng — của ARKit, không phải của gói.
///
/// [existingPlaneGeometry] là điểm nằm trên một mặt phẳng ARKit **đã xác
/// nhận**; [estimatedPlane] là một mặt phẳng ARKit **đoán ra** từ hình học
/// quanh tia (trên máy LiDAR thì đó là lưới thật, nên cùng một giá trị mang hai
/// mức tin cậy rất khác nhau — [ArPointDiagnostics.planeAlignment] tách hai
/// chuyện ấy ra).
///
/// [existingPlaneInfinite] không nằm trong danh sách gói bắn ra, nhưng vẫn có
/// mặt ở đây vì giá trị này là của `ARRaycastQuery.Target`.
enum ArRaycastTarget {
  existingPlaneGeometry,
  existingPlaneInfinite,
  estimatedPlane,
}

/// Trạng thái bám của ARKit tại đúng khoảnh khắc một điểm được chấm.
///
/// Sáu nhánh, KHÔNG gộp năm nhánh `.limited` thành một chữ: mỗi nhánh là một
/// giả thuyết khác về vì sao một số đo lệch. [limitedInitializing] nói "máy
/// chưa ấm", [limitedExcessiveMotion] nói "tay đang rê",
/// [limitedRelocalizing] nói "hệ toạ độ vừa nối lại".
///
/// Khác [ArMeasureLimitedReason]: cái kia là thứ NGƯỜI DÙNG đọc (hai lý do,
/// hai lời khuyên ngược nhau), cái này là thứ NGƯỜI ĐIỀU TRA đọc.
enum ArTrackingSnapshot {
  normal,
  limitedInitializing,
  limitedExcessiveMotion,
  limitedInsufficientFeatures,
  limitedRelocalizing,
  notAvailable,
}

/// Phương của mặt phẳng mà một điểm rơi lên.
enum ArPlaneAlignment { horizontal, vertical }

/// Điều kiện MỘT điểm được chấm — ảnh chụp tại đúng khoảnh khắc cú bấm.
///
/// Không trường nào ở đây tham gia vào phép tính khoảng cách. Đây là tầng GHI:
/// nó nói lại thứ máy ĐÃ làm, không đổi thứ máy sẽ làm.
///
/// **Mọi trường đều có thể `null`**, và đó là chủ ý. Thiếu khung hình camera,
/// một bản Swift cũ hơn tầng này, hay một giá trị ARKit thêm ở bản iOS sau —
/// tất cả rơi về `null`. Bịa một giá trị mặc định là dựng ra bằng chứng giả cho
/// đúng cái lượt điều tra mà tầng này sinh ra để phục vụ.
class ArPointDiagnostics {
  const ArPointDiagnostics({
    this.target,
    this.tracking,
    this.sessionAgeMs,
    this.cameraDistanceMm,
    this.rayAngleDeg,
    this.planeAlignment,
    this.planeWidthMm,
    this.planeHeightMm,
  });

  final ArRaycastTarget? target;
  final ArTrackingSnapshot? tracking;

  /// Mili-giây kể từ lời gọi `run(...)` gần nhất của phiên ARKit.
  ///
  /// Neo vào `run` chứ không vào lúc mở màn: `reset()` dựng lại hệ toạ độ từ
  /// đầu và mốc này đếm lại từ đó. Đây là biến duy nhất phân biệt được giả
  /// thuyết "máy chưa ấm".
  final int? sessionAgeMs;

  /// Khoảng cách từ tâm camera tới điểm chấm, milimét.
  final double? cameraDistanceMm;

  /// Góc của tia so với MẶT PHẲNG trúng, độ.
  ///
  /// 90° là chĩa vuông góc vào mặt, 0° là tia lướt sát mặt. Không phải góc so
  /// với pháp tuyến — hai góc ấy bù nhau, và cả hai đều nằm trong 0–90.
  final double? rayAngleDeg;

  /// `null` khi tia trúng một mặt ƯỚC LƯỢNG: không có mặt phẳng nào cả.
  final ArPlaneAlignment? planeAlignment;

  /// Bề rộng/bề dài của mặt phẳng trúng, milimét. `null` khi không có mặt
  /// phẳng nào — cùng lối với [planeAlignment].
  final double? planeWidthMm;
  final double? planeHeightMm;
}

/// Chẩn đoán của cả phép đo: mỗi điểm một mục, theo ĐÚNG thứ tự chấm.
///
/// [points] có một mục khi mới chấm điểm đầu, hai mục khi đã đủ hai. Không bao
/// giờ rỗng — mẫu không có điểm nào thì [ArMeasureSample.diagnostics] là `null`
/// chứ không phải một danh sách rỗng.
class ArMeasureDiagnostics {
  const ArMeasureDiagnostics({required this.points});

  final List<ArPointDiagnostics> points;
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
  const ArMeasureSample({
    required this.status,
    this.measurement,
    this.limitedReason,
    this.recoverable = true,
    this.aimLocked = false,
    this.diagnostics,
  });

  final ArMeasureStatus status;

  /// `null` ở mọi trạng thái không mang số đo (vd. [ArMeasureStatus.ready]).
  final ArMeasurement? measurement;

  /// Vì sao đang bám hạn chế, khi [status] là [ArMeasureStatus.needsMotion].
  ///
  /// `null` ở mọi trạng thái khác, và cũng `null` khi tầng nền không nói được
  /// (ARKit thêm một lý do mới ở bản iOS sau). Màn phải chịu được `null`: lúc
  /// ấy câu an toàn duy nhất là câu viết được cho cả hai lý do.
  final ArMeasureLimitedReason? limitedReason;

  /// Phiên này còn tự gỡ được không.
  ///
  /// `false` chỉ ở các hỏng **vĩnh viễn**: máy không chạy nổi cấu hình đang
  /// dùng, hoặc cảm biến không dùng được. Với chúng, [ArMeasureStatus.trackingLost]
  /// vẫn đúng nhưng lời khuyên đi kèm thì sai — mời người dùng "rê máy chậm và
  /// đều" cho một phiên không bao giờ chạy lại được là bắt họ đợi mãi mãi.
  ///
  /// Mặc định `true`: thiếu khoá thì coi như còn gỡ được, vì đó là dạng hỏng
  /// phổ biến hơn hẳn và cũng là hành vi của mọi bản trước khoá này.
  final bool recoverable;

  /// Tia bắn từ tâm màn ĐANG trúng một bề mặt hay không.
  ///
  /// Nói cách khác: bấm ngay bây giờ thì có đặt được điểm không. Đây là thứ
  /// duy nhất trong cả gói nói được chuyện đó **trước** cú bấm, và nó tồn tại
  /// vì một lượt chạy trên máy thật: chĩa vào một màn iPad đen bóng ở cự ly
  /// gần — phản chiếu, không vân, gần như không có điểm đặc trưng — thì
  /// [ArMeasureController.placePoint] trượt thật, nhưng người dùng chỉ thấy
  /// một cái nút không làm gì.
  ///
  /// Dùng nó để đổi hình tâm ngắm, y như app Measure của Apple: người ta rê
  /// máy tới khi con trỏ khoá lại rồi mới bấm.
  ///
  /// Chỉ có nghĩa khi [status] là [ArMeasureStatus.ready] hoặc
  /// [ArMeasureStatus.firstPointPlaced]. Ở mọi trạng thái khác — kể cả
  /// [ArMeasureStatus.measured], lúc đã đủ hai điểm và không còn gì để chấm —
  /// nó luôn `false`.
  ///
  /// Mặc định `false`: thiếu khoá nghĩa là chưa bám, tức là hình tâm ngắm an
  /// toàn (rỗng, còn phải rê tiếp).
  final bool aimLocked;

  /// Điều kiện mỗi điểm được chấm — xem [ArMeasureDiagnostics].
  ///
  /// `null` ở mọi mẫu chưa có điểm nào, và cũng `null` khi tầng nền không nói
  /// được (một bản Swift cũ hơn tầng chẩn đoán). Không bao giờ là một danh sách
  /// rỗng: rỗng đọc ra "đã đo và không có gì", còn `null` đọc đúng nghĩa "bản
  /// nền này không nói".
  ///
  /// Không thứ gì trong đây tham gia vào phép tính khoảng cách. Nó tồn tại vì
  /// một lượt điều tra đã bác sạch mọi giả thuyết về sai lệch số đo, và bác vì
  /// cùng một lý do ở MỌI giả thuyết: mẫu bắn lên Dart không mang một mẩu nào
  /// về việc phép đo đã diễn ra thế nào, nên mọi lời giải đều khớp mọi số đo.
  final ArMeasureDiagnostics? diagnostics;
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
  static const EventChannel _events = EventChannel(eventChannelName);

  static Stream<ArMeasureSample>? _samples;

  /// Luồng trạng thái và số đo của phiên đang chạy.
  ///
  /// Một luồng dùng chung cho cả gói, không phải một luồng cho mỗi view: chỉ
  /// có một mặt camera AR mở tại một lúc, và một kênh sự kiện thứ hai chỉ để
  /// phân biệt hai view không bao giờ cùng sống là một tầng phức tạp không
  /// mua được gì.
  ///
  /// **Không bao giờ ném, không bao giờ đứt.** Một khung hình hỏng từ tầng nền
  /// bị bỏ ([ArMeasure.parseSample] trả `null`), và một lỗi trên kênh cũng bị
  /// bỏ — luồng này nuôi màn hình đang đo, nên để nó chết là để màn đông cứng
  /// ở khung hình cuối mà không có gì nói ra.
  ///
  /// Số đo **trôi**: mỗi lượt ARKit tinh chỉnh hệ toạ độ là một mẫu mới với
  /// một con số hơi khác. Đông cứng nó lại là việc của người gọi, không phải
  /// của gói.
  static Stream<ArMeasureSample> get samples {
    return _samples ??= _events
        .receiveBroadcastStream()
        .handleError((Object _) {})
        .map(
          (Object? event) => event is Map
              ? parseSample(Map<Object?, Object?>.from(event))
              : null,
        )
        .where((ArMeasureSample? s) => s != null)
        .cast<ArMeasureSample>();
  }

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

    // Khoá phụ, và cả hai đều KHÔNG được giết mẫu khi lạ hay thiếu: một bản
    // Swift cũ không gửi chúng, và ARKit có thể thêm một lý do mới ở bản iOS
    // sau. Cả hai đường đều rơi về mặc định, y như "thiếu mm" ở trên.
    final limitedReason = switch (raw['limitedReason']) {
      'excessiveMotion' => ArMeasureLimitedReason.excessiveMotion,
      'insufficientFeatures' => ArMeasureLimitedReason.insufficientFeatures,
      _ => null,
    };
    final rawRecoverable = raw['recoverable'];
    final recoverable = rawRecoverable is bool ? rawRecoverable : true;
    final rawAimLocked = raw['aimLocked'];
    final aimLocked = rawAimLocked is bool ? rawAimLocked : false;

    return ArMeasureSample(
      status: status,
      measurement: measurement,
      limitedReason: limitedReason,
      recoverable: recoverable,
      aimLocked: aimLocked,
      diagnostics: _parseDiagnostics(raw['diagnostics']),
    );
  }

  /// Đọc khối chẩn đoán. **Không bao giờ ném, và không bao giờ giết mẫu.**
  ///
  /// Chẩn đoán là thứ đi kèm: một khoá hỏng ở đây mà làm mất cả mẫu thì tầng
  /// chẩn đoán tự nó thành một lỗi sản phẩm — màn đo đứng im ở khung hình cuối
  /// vì một trường không ai nhìn.
  static ArMeasureDiagnostics? _parseDiagnostics(Object? raw) {
    if (raw is! Map) return null;
    final rawPoints = raw['points'];
    if (rawPoints is! List) return null;
    if (rawPoints.isEmpty) return null;

    // Phần tử hỏng thành một điểm TRỐNG, không bị loại khỏi danh sách. Loại nó
    // ra là điểm thứ hai trượt lên chỗ điểm thứ nhất, và cả dải chẩn đoán nói
    // dối về việc điểm nào được chấm trong điều kiện nào — im lặng, và người
    // đọc không có cách nào biết.
    return ArMeasureDiagnostics(
      points: rawPoints
          .map(
            (Object? p) => p is Map
                ? _parsePointDiagnostics(Map<Object?, Object?>.from(p))
                : const ArPointDiagnostics(),
          )
          .toList(growable: false),
    );
  }

  /// Đọc một điểm. Mọi trường sai kiểu hay lạ đều về `null`, y như
  /// [parseSample] làm với `mm`/`tolMm`.
  static ArPointDiagnostics _parsePointDiagnostics(Map<Object?, Object?> raw) {
    final rawAge = raw['sessionAgeMs'];
    final rawDistance = raw['cameraDistanceMm'];
    final rawAngle = raw['rayAngleDeg'];
    final rawWidth = raw['planeWidthMm'];
    final rawHeight = raw['planeHeightMm'];

    return ArPointDiagnostics(
      target: switch (raw['target']) {
        'existingPlaneGeometry' => ArRaycastTarget.existingPlaneGeometry,
        'existingPlaneInfinite' => ArRaycastTarget.existingPlaneInfinite,
        'estimatedPlane' => ArRaycastTarget.estimatedPlane,
        _ => null,
      },
      tracking: switch (raw['tracking']) {
        'normal' => ArTrackingSnapshot.normal,
        'limitedInitializing' => ArTrackingSnapshot.limitedInitializing,
        'limitedExcessiveMotion' => ArTrackingSnapshot.limitedExcessiveMotion,
        'limitedInsufficientFeatures' =>
          ArTrackingSnapshot.limitedInsufficientFeatures,
        'limitedRelocalizing' => ArTrackingSnapshot.limitedRelocalizing,
        'notAvailable' => ArTrackingSnapshot.notAvailable,
        _ => null,
      },
      sessionAgeMs: rawAge is num ? rawAge.round() : null,
      cameraDistanceMm: rawDistance is num ? rawDistance.toDouble() : null,
      rayAngleDeg: rawAngle is num ? rawAngle.toDouble() : null,
      planeAlignment: switch (raw['planeAlignment']) {
        'horizontal' => ArPlaneAlignment.horizontal,
        'vertical' => ArPlaneAlignment.vertical,
        _ => null,
      },
      planeWidthMm: rawWidth is num ? rawWidth.toDouble() : null,
      planeHeightMm: rawHeight is num ? rawHeight.toDouble() : null,
    );
  }
}

/// Đọc kết quả `placePoint` từ chuỗi tầng nền trả về.
///
/// Không đọc được — `null`, sai kiểu, hay một chuỗi lạ từ một bản Swift lệch
/// pha — thì về [ArMeasurePlaceResult.notReady] chứ không ném: đây là giá trị
/// trả về của một cú chạm, và ném ở đây thì cái nút thành cái nút nổ.
ArMeasurePlaceResult _parsePlaceResult(Object? raw) {
  return switch (raw) {
    'placed' => ArMeasurePlaceResult.placed,
    'missed' => ArMeasurePlaceResult.missed,
    'notReady' => ArMeasurePlaceResult.notReady,
    'alreadyComplete' => ArMeasurePlaceResult.alreadyComplete,
    _ => ArMeasurePlaceResult.notReady,
  };
}

/// Các lệnh gửi tới đúng một platform view.
///
/// Dựng từ id mà [ArMeasureView.onPlatformViewCreated] báo ra. Lệnh mang theo
/// id ấy, nên gói không cần một kênh riêng cho mỗi view — và không cần một kênh
/// riêng thì cũng không có chỗ nào để dựng vòng giữ view sống mãi ở tầng Swift.
///
/// **Không hàm nào ném.** Plugin chưa đăng ký, view đã chết, máy ảo — tất cả
/// rơi vào cùng một đường: lệnh không làm gì và trả về bình thường.
class ArMeasureController {
  const ArMeasureController(this.viewId);

  /// Id platform view, từ [ArMeasureView.onPlatformViewCreated].
  final int viewId;

  /// Chấm một điểm tại con trỏ giữa màn.
  ///
  /// Trả **lý do** chứ không phải một `bool`, vì cả ba đường "không đặt được
  /// điểm nào" đều cần một câu khác nhau nói với người dùng — xem
  /// [ArMeasurePlaceResult]. Không bao giờ ném: một kênh chết cũng ra
  /// [ArMeasurePlaceResult.notReady].
  ///
  /// Vì sao là giá trị trả về chứ không phải một trạng thái bắn ra trên luồng
  /// [ArMeasure.samples]: chấm trượt **không đổi trạng thái gì cả** — phiên vẫn
  /// `ready`, y như một giây trước. Bắn thêm một `ready` nữa để nói "vừa rồi
  /// trượt" là gửi một tin không phân biệt được với một lần bám lại bình
  /// thường. Giá trị trả về thì đi thẳng về đúng cú chạm đã gây ra nó, nên
  /// người gọi rung hay nháy được ngay tại chỗ.
  ///
  /// Đừng để đây là chỗ ĐẦU TIÊN người dùng biết mình đang ngắm vào chỗ trống:
  /// [ArMeasureSample.aimLocked] nói chuyện đó ra từ trước cú bấm.
  Future<ArMeasurePlaceResult> placePoint() async {
    try {
      final raw = await ArMeasure._method.invokeMethod<String>('placePoint', {
        'viewId': viewId,
      });
      return _parsePlaceResult(raw);
    } catch (_) {
      return ArMeasurePlaceResult.notReady;
    }
  }

  /// Bỏ điểm chấm gần nhất. Chưa có điểm nào thì không làm gì.
  ///
  /// Không trả về gì, khác với [placePoint]: người gọi đã biết nó đang có mấy
  /// điểm (từ chính [ArMeasure.samples]), nên "hoàn tác lúc chưa có gì" là
  /// chuyện tự chặn được — còn "tia bắn trượt" thì không.
  Future<void> undoPoint() => _send('undoPoint');

  /// Bỏ hết điểm và dựng lại hệ toạ độ từ đầu.
  Future<void> reset() => _send('reset');

  /// Tạm dừng camera, GIỮ hai điểm.
  Future<void> pause() => _send('pause');

  /// Chạy lại sau [pause].
  ///
  /// ARKit sẽ tìm lại hệ toạ độ cũ. Không tìm được thì phiên bỏ hai điểm và
  /// quay về [ArMeasureStatus.ready] — đo tiếp trên một hệ toạ độ khác cho ra
  /// một con số trông bình thường mà sai.
  Future<void> resume() => _send('resume');

  /// Dừng hẳn phiên và tắt camera.
  ///
  /// **Phải gọi từ `State.dispose()`.** iOS không có callback dispose cho
  /// platform view — protocol `FlutterPlatformView` chỉ có đúng một phương
  /// thức `view()` — nên đây là đường chính, không phải một lượt dọn cho gọn.
  /// Quên gọi thì camera còn chạy tới lúc engine tình cờ thả view.
  Future<void> dispose() => _send('dispose');

  Future<void> _send(String method) async {
    try {
      await ArMeasure._method.invokeMethod<void>(method, {'viewId': viewId});
    } catch (_) {
      // Nuốt có chủ đích: xem chú thích ở đầu lớp.
    }
  }
}

/// Widget bọc mặt camera AR của nền tảng.
///
/// Một [UiKitView] mỏng quanh `ARSCNView` phía Swift. Gói không vẽ chữ và
/// không vẽ số — mọi con số, mọi nhãn, mọi nút là việc của app.
///
/// Hai thứ gói CÓ vẽ, và cả hai đều vì app không vẽ nổi:
///
/// * **Hai chấm và đoạn thẳng nối chúng.** Chúng là toạ độ 3D trong hệ toạ độ
///   của ARKit; chỉ tầng Swift biết chúng chiếu xuống màn ở đâu sau mỗi lượt
///   máy xoay. App chỉ nhận được một con số milimét.
/// * **Hướng dẫn quét bề mặt** — `ARCoachingOverlayView`, bản của Apple, chữ
///   của hệ điều hành. Nó tự bật lúc phiên chưa sẵn sàng và tự tắt khi ARKit dò
///   xong.
///
/// Bề mặt này KHÔNG nhận cú chạm nào: mọi thao tác là widget Flutter đặt đè lên
/// trên, và chạm rơi thẳng xuống đó.
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
