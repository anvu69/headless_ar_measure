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
  /// Câu đúng: **đã đủ hai điểm, bấm Chốt, Hoàn tác, hoặc dời một đầu**. Giá
  /// trị này đi trước [notReady]: hai điểm đã nằm đó thì câu ấy đúng kể cả lúc
  /// ARKit đang rung.
  ///
  /// Từ `0.10.0` đây không còn là ngõ cụt: [ArMeasureController.movePoint] đặt
  /// lại một đầu mút đã chấm mà không bắt đo lại cả hai.
  alreadyComplete,
}

/// Chuyện gì đã xảy ra với một lời gọi [ArMeasureController.movePoint].
///
/// Cùng một họ với [ArMeasurePlaceResult], và cùng một lẽ: ba trong bốn giá trị
/// đều là "không có điểm nào đổi chỗ", và ba câu đi kèm chúng **ngược nhau**.
///
/// Vì sao lệnh này tồn tại, nguyên văn lượt máy thật: *"khi chọn xong 2 đầu thì
/// hiện ra nút cộng trừ, tuy nhiên nó gây confuse cho user khi thay đổi số mà
/// điểm trên màn hình không đổi"*. Một cái nút chỉnh CON SỐ trong khi HÌNH đứng
/// im là hai lời khai về cùng một đoạn thẳng trên cùng một màn. Lệnh này đổi
/// chiều nhân quả: người dùng dời cái điểm, và con số đổi **vì hình đổi**.
enum ArMeasureMoveResult {
  /// Điểm đã đổi chỗ, và số đo đã tính lại.
  moved,

  /// Tia bắn ra không trúng gì. **Điểm cũ còn nguyên.**
  ///
  /// Câu đúng: **rê máy chậm cho tới khi tâm ngắm khoá lại rồi bấm lại**. Giữ
  /// điểm cũ là hợp đồng, không phải một chi tiết cài đặt: một lượt dời hụt xoá
  /// mất đầu mút đang có là phá dữ liệu của người dùng để đổi lấy một thao tác
  /// KHÔNG xảy ra — và họ vừa định nhích nó đi vài milimét.
  ///
  /// Kèm [ArMeasureSample.aimLocked], đây là đường để một cú bấm trượt không
  /// trông giống một cái nút hỏng. Đừng để nó là chỗ ĐẦU TIÊN người dùng biết
  /// mình đang ngắm vào chỗ trống.
  missed,

  /// Phiên đang ở trạng thái không cho bắn tia.
  ///
  /// Câu đúng nằm ở chính [ArMeasureSample.status] đang bắn ra. Tia chỉ có
  /// nghĩa khi ARKit đang bám bình thường — tức [ArMeasureStatus.ready],
  /// [ArMeasureStatus.firstPointPlaced] hoặc [ArMeasureStatus.measured].
  ///
  /// Cũng là giá trị trả về khi kênh không nói được gì: thiếu plugin, view đã
  /// chết, hoặc một bản Swift **cũ hơn lệnh này**. Không phải [noSuchPoint] —
  /// một kênh câm không biết gì về việc app đang có mấy điểm, và trả lời thay
  /// nó là nói dối app về dữ liệu của chính app.
  notReady,

  /// Chỉ số không trỏ vào điểm nào đang có.
  ///
  /// Hợp lệ là `0 <= index < số điểm đã chấm`: một điểm, chỉ số 0; hai điểm,
  /// chỉ số 0 và 1; chưa chấm gì thì không chỉ số nào hợp lệ.
  ///
  /// **Không có câu nào để nói với người dùng.** Đây là một câu nói với app:
  /// nó vừa hỏi về một điểm không tồn tại, nên cái nút dời ấy lẽ ra không nên
  /// có mặt. Nó cũng là đường của một cuộc chạy đua bình thường — người dùng
  /// bấm dời đúng lúc [ArMeasureController.undoPoint] vừa chạy — và ở đó việc
  /// đúng là không làm gì cả.
  ///
  /// Giá trị này đi TRƯỚC [notReady]: nửa giây rung tay không được biến "điểm
  /// ấy không tồn tại" thành "chờ phiên bám lại", vì chờ bao lâu cũng không làm
  /// nó mọc ra.
  noSuchPoint,
}

/// Chuyện gì đã xảy ra với một lời gọi [ArMeasureController.grabPoint].
///
/// Vì sao cặp [ArMeasureController.grabPoint]/[ArMeasureController.releasePoint]
/// tồn tại bên cạnh [ArMeasureController.movePoint], nguyên văn lượt máy thật:
/// *"chiếu hồng tâm vào đầu mút thì hiện lên chức năng Dời đầu này. Tuy nhiên
/// cách dùng khó chịu, nó không phải nắm lấy điểm đó và kéo cho đến khi buông
/// ra, mà nhấn vào nút Dời đầu này là chỉ nhích được một khoảng. Phải làm cho
/// nó thực tế giống như chỉnh 2 đầu của một chiếc thước dây vậy."*
///
/// [ArMeasureController.movePoint] là một NHÁT dời — một cú bấm, một lượt bắn
/// tia, một chỗ mới. Cặp này mở một QUÃNG nắm, và trong quãng ấy đầu mút bám
/// theo tâm ngắm ở **mỗi khung hình**, ở tầng nền.
///
/// **Đừng cài một quãng nắm bằng cách gọi [ArMeasureController.movePoint] liên
/// tục.** Nó cho ra đúng hình ấy trên màn, nên nó không có triệu chứng nào
/// ngoài hoá đơn pin: 30 lượt qua kênh nền mỗi giây, 30 lượt gỡ-và-thêm một
/// `ARAnchor` vào phiên ARKit, và 30 [ArMeasureMoveResult] không ai đọc.
enum ArMeasureGrabResult {
  /// Đã nắm. Từ khung hình kế tiếp, đầu mút bám theo tâm ngắm.
  grabbed,

  /// Phiên không ở trạng thái bắn tia được, hoặc phiên đã dừng.
  ///
  /// Cũng là giá trị của một kênh câm — thiếu plugin, view đã chết, hay một bản
  /// Swift **cũ hơn cặp lệnh này**. Không phải [noSuchPoint], cùng một luật với
  /// [ArMeasureMoveResult.notReady]: một kênh câm không biết app đang có mấy
  /// điểm.
  notReady,

  /// Chỉ số không trỏ vào điểm nào đang có. Một câu nói với APP, không phải với
  /// người dùng — xem [ArMeasureMoveResult.noSuchPoint].
  noSuchPoint,

  /// Đang nắm một đầu rồi. Câu đúng: buông cái đang cầm trước đã.
  ///
  /// Gói cố ý KHÔNG tự buông cái cũ rồi nắm cái mới: hai lượt chốt điểm trong
  /// một cú bấm là một thao tác người dùng không xin.
  alreadyGrabbing,
}

/// Chuyện gì đã xảy ra với một lời gọi [ArMeasureController.releasePoint].
enum ArMeasureReleaseResult {
  /// Đã buông, và điểm chốt ở chỗ lượt trúng CUỐI của quãng kéo. Số đo đã tính
  /// lại, và nó vẫn TRÔI như mọi số chưa chốt.
  released,

  /// Đã buông, và điểm nằm **nguyên chỗ cũ**: không khung nào trong cả quãng
  /// nắm bắt được bề mặt.
  ///
  /// Tách khỏi [released] vì câu nói với người dùng ngược nhau — một bên là "đã
  /// dời, chốt lại khi số đứng yên", một bên là "chưa dời được, chĩa vào chỗ có
  /// vân rồi nắm lại". Gộp là để màn báo đã dời cho một cú dời chưa xảy ra.
  unmoved,

  /// Không có gì trong tay: gói đã tự buông, hoặc chưa nắm bao giờ.
  ///
  /// Gói tự buông ở những đường app không gây ra — phiên gián đoạn, `pause`,
  /// `reset`, `dispose`, một lệnh khác dời điểm, hay ARKit bỏ chính cái anchor
  /// đang nắm. Đọc [ArMeasureSample.grabbedPointIndex] để biết trước.
  notGrabbing,

  /// Phiên đã dừng; cũng là giá trị của một kênh câm.
  ///
  /// Tách khỏi [notGrabbing] cùng lẽ với cặp
  /// [ArMeasureMoveResult.noSuchPoint]/[ArMeasureMoveResult.notReady]:
  /// [notGrabbing] là một câu về TRẠNG THÁI của phiên, mà một kênh chết không
  /// biết gì về trạng thái ấy.
  notReady,
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
/// Ba tầng, và chúng KHÔNG cùng một mức tin cậy:
///
/// * [existingPlaneGeometry] — điểm nằm trong đa giác biên của một mặt phẳng
///   ARKit **đã xác nhận**. Chắc nhất gói có.
/// * [estimatedPlane] — mặt phẳng ARKit **đoán ra** từ hình học quanh tia (trên
///   máy LiDAR thì đó là lưới thật, nên cùng một giá trị mang hai mức tin cậy
///   rất khác nhau — [ArPointDiagnostics.planeAlignment] tách hai chuyện ấy).
/// * [existingPlaneInfinite] — một mặt phẳng đã dò ra, **kéo dài ra ngoài biên
///   của chính nó**. Đây là điểm SUY RA, không phải điểm quan sát được, và nó
///   không bao giờ đi một mình: [ArPointDiagnostics.overshootMm] (hoặc
///   [ArMeasureSample.aimOvershootMm] cho tia đang ngắm) nói nó nằm cách biên
///   thật bao xa. Xem hai trường ấy trước khi dùng một điểm ở tầng này.
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
    this.planeId,
    this.planeAlignment,
    this.planeWidthMm,
    this.planeHeightMm,
    this.overshootMm,
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

  /// **Mặt phẳng NÀO** — định danh của mặt phẳng điểm này rơi lên.
  ///
  /// Chuỗi mờ, chỉ dùng để **so sánh bằng nhau**. Đừng phân tích nó, đừng hiển
  /// thị nó, đừng lưu nó như một khoá liên phiên: ARKit sinh lại định danh của
  /// mọi mặt phẳng ở mỗi phiên, nên hai phiên khác nhau không so được với nhau.
  ///
  /// **Vì sao nó tồn tại, khi đã có [planeAlignment] và hai bề rộng.** Hai cảnh
  /// hỏng trên máy thật, và cả hai lọt qua sạch mọi trường khác:
  ///
  /// 1. Điểm cuối lơ lửng trên tường nằm trên mặt phẳng MẶT BÀN kéo dài gần hai
  ///    mét ([overshootMm] +1946), nên [planeAlignment] của nó vẫn
  ///    [ArPlaneAlignment.horizontal] y hệt điểm đầu.
  /// 2. Điểm bị bắt xuống dưới chân bàn rơi lên mặt SÀN, vì lúc ấy mặt bàn chưa
  ///    được dò. Sàn và mặt bàn ĐỀU ngang.
  ///
  /// Phương giống nhau, tầng giống nhau, bề rộng không kết luận được gì. Mọi
  /// phép suy từ những trường ấy trả lời "cùng mặt phẳng" ở đúng hai cảnh chúng
  /// cần phân biệt — nên đây là một định danh THẬT, không phải một phép suy.
  ///
  /// **`null` là một sự thật, không phải một chỗ thiếu**, và app phải phân biệt
  /// nó với "có mặt phẳng, và là mặt phẳng khác". Ba đường về `null`:
  ///
  /// * [target] là [ArRaycastTarget.estimatedPlane] — tầng ấy **không có mặt
  ///   phẳng nào**: ARKit khớp một mặt phẳng từ hình học quanh tia và không neo
  ///   nó vào đâu cả;
  /// * tầng nền không nói được (một bản Swift cũ hơn trường này);
  /// * chuỗi rỗng hay sai kiểu, bị chặn ở cửa — hai chuỗi rỗng bằng nhau, nên
  ///   để một chuỗi rỗng đi tiếp là hai điểm bất kỳ đọc ra "cùng một mặt
  ///   phẳng".
  ///
  /// **Gói KHÔNG kết luận "cùng hay khác".** Đó là việc của app, cùng một ranh
  /// giới với [overshootMm]: gói trả sự thật đo được, app quyết.
  ///
  /// **Đây là định danh **lúc chấm**, và không đường nào viết lại nó.** ARKit
  /// GỘP mặt phẳng: hai mặt phẳng nhập một, mặt bị nuốt biến mất, nên một định
  /// danh lưu từ lúc chấm có thể trỏ vào một mặt phẳng không còn tồn tại. Gói
  /// cố ý không đuổi theo lượt gộp, vì ARKit không nói mặt phẳng bị nuốt đã
  /// nhập vào mặt phẳng NÀO — dựng lại ánh xạ ấy là một phép đoán, và một cú
  /// đoán sai in ra đúng chữ "cùng mặt phẳng" mà trường này sinh ra để chặn.
  ///
  /// Hệ quả app phải biết: sau một lượt gộp, hai điểm trên thứ vật lý là MỘT
  /// mặt bàn có thể khai hai định danh khác nhau. Đó là một báo động NHẦM, và
  /// nó là chiều sai an toàn — người dùng thấy được. Chiều ngược lại im lặng.
  final String? planeId;

  /// `null` khi tia trúng một mặt ƯỚC LƯỢNG: không có mặt phẳng nào cả.
  final ArPlaneAlignment? planeAlignment;

  /// Bề rộng/bề dài của mặt phẳng trúng, milimét. `null` khi không có mặt
  /// phẳng nào — cùng lối với [planeAlignment].
  final double? planeWidthMm;
  final double? planeHeightMm;

  /// Điểm này nằm cách **đa giác biên** của chính mặt phẳng ấy bao xa, milimét.
  ///
  /// Chỉ có giá trị khi [target] là [ArRaycastTarget.existingPlaneInfinite] —
  /// tức là điểm được SUY RA bằng cách kéo dài một mặt phẳng đã dò ra vượt khỏi
  /// biên thật của nó. `null` ở hai tầng kia, và `null` cũng là đường của một
  /// bản Swift cũ hơn trường này.
  ///
  /// **Đây là cái van, không phải một con số trang trí.** Tầng ngoại suy trả về
  /// một điểm ở MỌI lượt bắn, kể cả khi mặt phẳng ấy đã bị kéo dài xuyên qua
  /// vật đang ngắm — nên nếu không đọc con số này thì một cao độ mặt bàn hiện
  /// ra dưới dạng một số đo bình thường và không có gì nói ra:
  ///
  /// * vài chục mm — mép bàn mà biên chưa mọc tới, ngoại suy đáng tin vừa phải;
  /// * hàng trăm mm tới hàng mét — mặt phẳng đã kéo dài tới một chỗ không có gì
  ///   ở đó.
  ///
  /// **Gói không đặt ngưỡng, và cố ý không đặt.** Ngưỡng nào là "quá xa" phụ
  /// thuộc việc app đang đo cái gì và số ấy dùng để làm gì. Gói trả sự thật:
  /// tầng nào, vượt biên bao nhiêu.
  ///
  /// Số dương, hữu hạn. Quãng đo trong MẶT PHẲNG (bỏ trục pháp tuyến), tới
  /// **đoạn** biên gần nhất chứ không tới đỉnh gần nhất — đỉnh của
  /// `boundaryVertices` chỉ là điểm mẫu ARKit rải dọc biên.
  final double? overshootMm;
}

/// Khuôn hình ARKit đang CHẠY — chuyện của cả phiên, không phải của một điểm.
///
/// Gói **không** lấy khuôn mặc định của Apple: nó chọn khuôn có **nhịp khung
/// cao nhất**, và trong số các khuôn cùng nhịp cao nhất thì lấy khuôn nhiều
/// điểm ảnh nhất. Danh sách rỗng thì giữ mặc định.
///
/// Thứ tự ấy đổi ở `0.9.0`. Trước đó (`0.4.0`) nó xếp ngược: nhiều điểm ảnh
/// nhất trước. Ba con số dưới đây là thứ duy nhất nói được phép chọn ấy đang
/// làm gì trên một máy thật, và chúng ở đây từ trước khi ai đó phải trả lời
/// câu hỏi ấy lần đầu.
///
/// **[fps] là nhịp DANH ĐỊNH của khuôn.** Sau `0.9.0` con số ấy thường là 60,
/// và một cái máy đang nóng vẫn giao ít hơn thế mà không có gì ở đây nói ra.
/// Đọc lời chú của [fps].
///
/// **Mọi trường có thể `null`**, cùng lối với [ArPointDiagnostics]: một bản
/// Swift cũ hơn khối này không gửi gì cả.
class ArVideoFormat {
  const ArVideoFormat({this.width, this.height, this.fps});

  /// Độ phân giải ảnh camera ARKit đang lấy, tính bằng điểm ảnh.
  final int? width;
  final int? height;

  /// Số khung hình mỗi giây của khuôn ấy — **nhịp danh nghĩa của khuôn**, không
  /// phải nhịp đo được lúc chạy. Máy nóng hay CPU đầy làm nhịp thật tụt xuống
  /// dưới con số này, và không có gì ở đây nói ra chuyện đó.
  ///
  /// Cụ thể: tầng Swift đọc `config.videoFormat.framesPerSecond` đúng một lần,
  /// tại lời gọi `run`, rồi để im. Một phiên tụt xuống 20 khung/s vì nóng máy
  /// vẫn báo 30. Chỗ hiển thị phải ghi rõ "danh định"; ai cần nhịp THẬT thì
  /// phải tự đếm khung — gói không đếm.
  ///
  /// Khoảng cách giữa hai thứ ấy **rộng ra** từ `0.9.0`, không hẹp lại. Phép
  /// chọn nay ưu tiên nhịp, nên con số này thường là 60 — và một cái máy nóng
  /// giao 40 vẫn khai 60. Trước đó nó thường là 30, và một khai báo 30 sai ít
  /// hơn vì trần của nó thấp hơn. Ai định kết luận điều gì về độ mượt từ con
  /// số này phải đếm khung trước.
  final int? fps;
}

/// Thấu kính của **một khung hình**: tiêu cự tính bằng điểm ảnh, kèm đúng khuôn
/// hình mà tiêu cự ấy được biểu diễn trên đó.
///
/// Có mặt vì app cần một mẫu số. Số hạng dung sai của một phép đo AR là
///
///     ε = d · Δu / (fx · sin θ)
///
/// — `d` là cự ly tới điểm, `Δu` là sai số hướng ngắm tính bằng điểm ảnh, `θ`
/// là góc giữa tia và MẶT phẳng ([ArMeasureSample.aimRayAngleDeg] cho tia đang
/// ngắm, [ArPointDiagnostics.rayAngleDeg] cho điểm đã chấm). Không có [fx] thì
/// không tính nổi một milimét nào, và cách duy nhất còn lại là ước bừa.
///
/// **Gói dừng ở đây.** Nó không tính `ε`, không biết `Δu`, không đặt ngưỡng nào
/// — cùng một ranh giới với [ArPointDiagnostics.overshootMm]. Nó trả sự thật đo
/// được: thấu kính dài bao nhiêu điểm ảnh, trên khuôn hình nào.
///
/// **Vì sao KHÔNG nằm chung khối với [ArVideoFormat].** Khối kia là ảnh chụp
/// tại lời gọi `run`, đọc từ cấu hình — khuôn được **xin**. Khối này đọc từ
/// `ARFrame.camera` của khung hình vừa tới — khuôn đang **chạy**, và ARKit
/// không hứa hai thứ ấy bằng nhau. Trộn chúng là đọc [fx] trên một bề rộng
/// không phải bề rộng của nó, và con số sai ra được vẫn là một con số milimét
/// trông bình thường.
///
/// **Mọi trường có thể `null`**, cùng lối với [ArPointDiagnostics]: một bản
/// Swift cũ hơn tầng này không gửi gì cả.
class ArCameraIntrinsics {
  const ArCameraIntrinsics({this.fx, this.width, this.height});

  /// Tiêu cự theo trục ngang, tính bằng **điểm ảnh** —
  /// `ARFrame.camera.intrinsics[0][0]`.
  ///
  /// **Đừng ghim cứng con số này.** 1442 — giá trị mà mọi bài viết về máy iOS
  /// dẫn ra — là tiêu cự của khuôn 1920×1440. Gói tự chọn khuôn hình, và tiêu
  /// chí chọn ĐÃ đổi một lần: tới `0.8.0` nó lấy khuôn to nhất (3840×2160 trên
  /// máy đã đo, tức [fx] gần gấp đôi), từ `0.9.0` nó ưu tiên nhịp khung và trên
  /// cùng máy ấy khuôn được chọn nhỏ hơn. Một hằng số ghim theo bản nào cũng
  /// sai ở bản kia, và cả hai giá trị sai đều rơi vào khoảng vài milimét —
  /// trông hoàn toàn hợp lý. Nó còn nhúc nhích trong một phiên, vì gói bật lấy
  /// nét tự động.
  ///
  /// Luôn đọc kèm [width]: cùng một thấu kính cho hai con số khác nhau trên hai
  /// khuôn hình, và tỉ lệ giữa chúng đúng bằng tỉ lệ bề rộng.
  ///
  /// Số dương, hữu hạn. Qua cùng một cửa lọc với [ArPointDiagnostics.overshootMm]
  /// chứ không qua cửa của một con số để đọc, và vì cùng một lẽ: nó là MẪU SỐ.
  /// `0` cho ra `ε` vô cực, `NaN` làm mọi phép so sánh với `ε` thành `false` —
  /// cả hai đều là một ngưỡng cảnh báo câm mà không ai biết.
  final double? fx;

  /// Độ phân giải của khung hình mà [fx] vừa được đọc ra —
  /// `ARFrame.camera.imageResolution`, tính bằng điểm ảnh.
  ///
  /// Đây là hệ toạ độ mà [fx] và `Δu` phải cùng nằm trong. Đo `Δu` trên toạ độ
  /// màn (point) rồi chia cho một [fx] tính trên điểm ảnh là lệch nguyên một hệ
  /// số `devicePixelRatio`.
  final int? width;
  final int? height;
}

/// Đếm điểm đặc trưng thô của MỘT khung hình: tổng, và số nằm quanh tia ngắm.
///
/// **Đây là một PHÉP ĐO, không phải một tính năng.** Nó có mặt ở `0.5.0` để trả
/// lời đúng một câu hỏi đang treo, và nó biến mất cùng lúc câu hỏi ấy được trả
/// lời: khi tia bắn từ tâm ngắm trượt LIÊN TỤC — bàn gỗ phủ tấm lót chuột đen
/// phẳng lì, tường trơn, trong nhà buổi tối, cả hai tầng raycast cùng rỗng — thì
/// quanh tia còn nguyên liệu để tự khớp lấy một mặt phẳng hay không.
///
/// Câu hỏi ấy đáng hỏi vì [ArRaycastTarget.estimatedPlane] **về bản chất đã là**
/// "khớp một mặt phẳng từ điểm đặc trưng quanh tia", và nó trả rỗng. Nếu quanh
/// tia cũng không có điểm nào thì không có gì để dựng — và một tầng khớp mặt
/// phẳng tự viết sẽ trả về đúng cái rỗng ấy, chỉ tốn hơn.
///
/// Không thứ gì trong đây tham gia vào phép tính khoảng cách, vào tâm ngắm, hay
/// vào cách một điểm được chấm.
class ArFeatureCensus {
  const ArFeatureCensus({this.total, this.nearRay});

  /// Tổng số điểm trong `ARFrame.rawFeaturePoints` của khung hình ấy.
  ///
  /// Một mình nó không phân biệt được "phòng trơn" với "đang chĩa vào một mảng
  /// trơn giữa một phòng đầy vân" — [nearRay] mới tách hai chuyện ấy.
  final int? total;

  /// Bao nhiêu trong số ấy nằm trong hình nón quanh tia bắn từ tâm màn.
  ///
  /// Nửa góc 10° và cửa sổ khoảng cách 0,2–3 m, cả ba chọn theo lập luận chứ
  /// không theo một phép đo — lập luận nằm ở tầng Swift, cạnh chính các hằng số.
  /// Nón cố ý rộng hơn hình tâm ngắm, nên đây là một CẬN TRÊN của nguyên liệu:
  /// số thấp kết luận được ngay, số cao thì chưa chứng minh nguyên liệu nằm
  /// đúng trên bề mặt đang ngắm.
  final int? nearRay;
}

/// Chẩn đoán: điều kiện của mỗi điểm đã chấm, cộng khuôn hình của cả phiên.
///
/// [points] có một mục khi mới chấm điểm đầu, hai mục khi đã đủ hai, và **rỗng**
/// khi chưa chấm gì mà tầng nền vẫn có chuyện để nói ([video], [features]). Cả
/// khối là `null` khi tầng nền không nói được gì cả.
class ArMeasureDiagnostics {
  const ArMeasureDiagnostics({
    required this.points,
    this.video,
    this.features,
    this.camera,
  });

  final List<ArPointDiagnostics> points;

  /// Khuôn hình đang chạy. `null` trước lượt `run` đầu tiên, và trên một bản
  /// Swift cũ hơn phép thử ấy.
  final ArVideoFormat? video;

  /// Đếm điểm đặc trưng của khung hình đã sinh ra lượt ngắm gần nhất.
  ///
  /// `null` khi phiên không đang ở quãng còn chấm được (không có lượt ngắm nào
  /// để đếm về), khi ARKit không giao đám mây điểm, và trên một bản Swift cũ
  /// hơn phép đo này. Xem [ArFeatureCensus].
  final ArFeatureCensus? features;

  /// Thấu kính của khung hình gần nhất — xem [ArCameraIntrinsics].
  ///
  /// `null` trước khung hình đầu tiên và trên một bản Swift cũ hơn tầng này.
  /// KHÔNG bị gác theo trạng thái phiên: nó nói về cái máy, không nói về lượt
  /// ngắm, và app cần nó cả lúc đã đo xong hai điểm để tính dung sai của con số
  /// vừa chốt.
  final ArCameraIntrinsics? camera;
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
    this.aimTarget,
    this.aimOvershootMm,
    this.aimRayAngleDeg,
    this.aimPlaneId,
    this.grabbedPointIndex,
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
  /// Có nghĩa ở **ba** trạng thái — [ArMeasureStatus.ready],
  /// [ArMeasureStatus.firstPointPlaced] và [ArMeasureStatus.measured] — tức là
  /// đúng những lúc ARKit đang bám bình thường. Ở mọi trạng thái khác nó luôn
  /// `false`.
  ///
  /// [ArMeasureStatus.measured] vào danh sách ấy từ `0.10.0`, cùng lượt với
  /// [ArMeasureController.movePoint], và **đây là lật một câu cũ**: tài liệu
  /// bản trước nói thẳng rằng ở `measured` cờ này luôn `false` vì "đã đủ hai
  /// điểm và không còn gì để chấm". Câu ấy nay sai — vẫn còn một cú bấm đặt
  /// được một điểm, là cú dời. Để cờ câm ở đó là bắt người dùng biết mình đang
  /// ngắm vào chỗ trống bằng cách BẤM, tức là dựng lại đúng cái nút chết mà cả
  /// trường này sinh ra để chặn.
  ///
  /// Mặc định `false`: thiếu khoá nghĩa là chưa bám, tức là hình tâm ngắm an
  /// toàn (rỗng, còn phải rê tiếp).
  ///
  /// Suy ra từ [aimTarget] ở tầng nền (`!= nil`), nên hai trường này không bao
  /// giờ nói hai chuyện khác nhau — trừ một đường: một bản Swift cũ hơn
  /// [aimTarget] gửi cờ mà không gửi tầng.
  final bool aimLocked;

  /// Tia bắn từ tâm màn đang trúng TẦNG nào. `null` là không trúng gì.
  ///
  /// Bốn cảnh, không phải hai — và [aimLocked] chỉ tách được hai:
  ///
  /// * [ArRaycastTarget.existingPlaneGeometry] — điểm nằm trên một mặt phẳng
  ///   ARKit **đã xác nhận**. Chấm ở đây là chắc nhất gói có.
  /// * [ArRaycastTarget.estimatedPlane] — ARKit **đoán** một mặt phẳng từ hình
  ///   học quanh tia. Chấm được, nhưng cao độ có thể lệch, và trên máy không có
  ///   LiDAR thì lệch nhiều hơn hẳn.
  /// * [ArRaycastTarget.existingPlaneInfinite] — một mặt phẳng đã dò ra, **kéo
  ///   dài ra ngoài biên của chính nó**. Chấm được, và điểm ấy là điểm SUY RA.
  ///   Đọc kèm [aimOvershootMm]: nó nói tia đang rơi cách biên thật bao xa.
  /// * `null` — không trúng gì. Cú bấm ngay bây giờ sẽ **trượt**.
  ///
  /// Dùng nó để tâm ngắm nói bốn chuyện khác nhau. Gộp ba tầng vào một hình là
  /// giấu đúng phần người dùng cần: một điểm trên mặt ước lượng — và nhất là
  /// một điểm ngoại suy — trông y hệt một điểm chắc chắn, cho tới lúc con số
  /// cuối cùng lệch.
  ///
  /// Có nghĩa ở cùng ba trạng thái với [aimLocked], kể cả
  /// [ArMeasureStatus.measured] — ở đó nó nói về cú bấm của
  /// [ArMeasureController.movePoint] thay vì của
  /// [ArMeasureController.placePoint], và câu hỏi thì y hệt: chỗ đang ngắm là
  /// chỗ quan sát được, chỗ đoán ra, chỗ suy ra, hay không có chỗ nào.
  ///
  /// `null` cũng là đường của một bản Swift cũ hơn trường này. Hai đường đổ về
  /// cùng một chỗ có chủ đích: cả hai đều là "không có tầng nào để bày".
  final ArRaycastTarget? aimTarget;

  /// Tia đang ngắm rơi cách **đa giác biên** của mặt phẳng ấy bao xa, milimét.
  ///
  /// Chỉ có giá trị khi [aimTarget] là
  /// [ArRaycastTarget.existingPlaneInfinite]; `null` ở mọi tầng khác, khi tia
  /// trượt, và trên một bản Swift cũ hơn trường này.
  ///
  /// Cùng một cái van với [ArPointDiagnostics.overshootMm], đo trước cú bấm
  /// thay vì sau: dùng nó để tâm ngắm nói ra rằng chỗ đang ngắm là chỗ SUY RA,
  /// và suy ra xa tới mức nào. Gói không đặt ngưỡng — xem
  /// [ArPointDiagnostics.overshootMm] để biết vì sao.
  final double? aimOvershootMm;

  /// Góc giữa tia ĐANG ngắm và **mặt phẳng** nó đang trúng, độ.
  ///
  /// 90° là chĩa vuông góc vào mặt, 0° là tia lướt sát mặt. Không phải góc so
  /// với pháp tuyến — hai góc ấy bù nhau, và cả hai đều nằm trong 0–90, nên
  /// nhầm là in 63° thành 27° mà không có gì nói ra.
  ///
  /// **Vì sao nó ở đây chứ không chỉ ở [ArPointDiagnostics.rayAngleDeg].** Góc
  /// sượt là số hạng nở nhanh nhất của dung sai: nó nằm ở MẪU SỐ dưới dạng
  /// `sin θ`. Ở 0,6 m với sai số hướng ngắm 2 điểm ảnh, ε là 0,83 mm ở 90°,
  /// 4,00 mm ở 12°, và 9,55 mm ở 5° — mà cúi thấp ngắm sượt đúng là tư thế
  /// người ta cầm máy khi đo mép bàn. Một cảnh báo dựng trên góc của điểm ĐÃ
  /// chấm là một cảnh báo tới sau cú bấm, và nó không cứu được cú bấm nào.
  ///
  /// Có nghĩa ở **mọi** tầng của [aimTarget], khác hẳn [aimOvershootMm]: một
  /// tia sượt 4° vào một mặt phẳng ARKit đã xác nhận vẫn là một tia sượt 4°.
  ///
  /// `null` khi tia **không trúng gì** (không có mặt phẳng nào để đo góc so với
  /// nó), ở mọi trạng thái mà [aimTarget] cũng `null`, và trên một bản Swift cũ
  /// hơn trường này.
  ///
  /// Số hữu hạn: `NaN` và vô cực bị chặn ở cửa, cùng lối với [aimOvershootMm].
  /// Đây là chỗ nó khác [ArPointDiagnostics.rayAngleDeg] của các bản trước —
  /// con số kia chỉ để ĐỌC, con số này đi vào một phép chia.
  final double? aimRayAngleDeg;

  /// Định danh mặt phẳng mà tia ĐANG ngắm rơi lên.
  ///
  /// Cùng một giá trị, cùng một luật đọc với [ArPointDiagnostics.planeId] —
  /// đọc tài liệu ở đó trước; đây chỉ nói chỗ nó khác.
  ///
  /// Đo TRƯỚC cú bấm thay vì sau: dùng nó để nói ra rằng chỗ đang ngắm nằm trên
  /// một mặt phẳng KHÁC mặt phẳng của điểm đầu, ở đúng lúc còn ngăn được cú bấm
  /// — thay vì phát hiện sau khi đã có hai điểm và một con số.
  ///
  /// `null` ở **hai** đường, và cả hai đều là sự thật: tia không trúng gì, hoặc
  /// tia trúng một mặt ƯỚC LƯỢNG ([ArRaycastTarget.estimatedPlane] không có mặt
  /// phẳng nào để khai tên). Cộng đường thứ ba của mọi trường: một bản Swift cũ
  /// hơn trường này.
  ///
  /// Chỗ nó khác [aimOvershootMm]: van chỉ có nghĩa ở tầng ngoại suy, còn định
  /// danh có nghĩa ở cả tầng hình học lẫn tầng ngoại suy — mặt phẳng bị kéo dài
  /// vẫn là một mặt phẳng đã dò ra, và nó vẫn có tên. Bất biến của van không
  /// đổi: `aimOvershootMm != null` vẫn đúng bằng
  /// `aimTarget == existingPlaneInfinite`.
  final String? aimPlaneId;

  /// Đầu mút mà phiên ĐANG NẮM — `0` là đầu chấm trước, `1` là đầu chấm sau.
  /// `null` là không nắm gì.
  ///
  /// Mở bằng [ArMeasureController.grabPoint], đóng bằng
  /// [ArMeasureController.releasePoint]. Trong quãng ấy đầu mút bám theo tâm
  /// ngắm ở mỗi khung hình, và cả số đo lẫn [ArMeasureOverlay] chạy theo.
  ///
  /// **Đọc trường này chứ đừng tự nhớ lấy từ giá trị trả về của
  /// [ArMeasureController.grabPoint].** Gói TỰ buông ở những đường app không
  /// gây ra: phiên gián đoạn (cuộc gọi, xuống nền), [ArMeasureController.pause],
  /// [ArMeasureController.reset], [ArMeasureController.dispose],
  /// [ArMeasureController.undoPoint], [ArMeasureController.movePoint], hay ARKit
  /// bỏ chính cái anchor đang nắm. App nhớ một mình thì sau những lượt ấy nó
  /// còn vẽ "đang nắm đầu A" cho một quãng đã kết thúc, và cái nút buông không
  /// buông gì cả.
  ///
  /// KHÔNG bị gác theo [status], khác hẳn bốn trường `aim*`: chúng suy từ một
  /// lượt raycast nên chúng hết nghĩa lúc tia hết nghĩa, còn quãng nắm là một
  /// trạng thái của PHIÊN. Gác nó theo trạng thái là cái nút buông biến mất ở
  /// đúng lúc phiên rung tay.
  ///
  /// `null` cũng là đường của một bản Swift cũ hơn cặp lệnh này — và ở đó `null`
  /// là sự thật, vì bản ấy không có đường nào để nắm.
  final int? grabbedPointIndex;

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

/// Hai đầu đoạn thẳng đang đo, đã chiếu xuống **toạ độ màn**.
///
/// Gói tự vẽ đoạn thẳng ở tầng SceneKit — xem [ArMeasureView]. Lớp này tồn tại
/// cho thứ gói KHÔNG vẽ và không được phép vẽ: một nhãn chữ neo vào đoạn ấy.
/// Chữ là việc của app, còn phép chiếu 3D → 2D thì Dart không làm nổi, nên gói
/// trả về đúng phần Dart thiếu.
///
/// Đơn vị là **point** (đơn vị của Flutter), gốc ở góc **trên-trái** của bề mặt
/// AR — cùng hệ toạ độ với một `CustomPaint` đặt đè lên [ArMeasureView], nên
/// người vẽ dùng thẳng, không đổi đơn vị lần nữa.
///
/// Đi trên một kênh RIÊNG ([ArMeasure.overlay]), không đi chung với
/// [ArMeasure.samples]: lớp phủ chạy tới 30 Hz, còn trạng thái và chẩn đoán đổi
/// vài giây một lần. Gộp chung là bắt mọi người nghe trạng thái lọc ba mươi
/// khung mỗi giây.
///
/// **Đây cũng là chỗ trả lời câu "tâm ngắm đang ở gần đầu nào".** Hai toạ độ
/// dưới đây cùng hệ với tâm ngắm — giữa [ArMeasureView], mà chính app đã đặt —
/// nên app đo được khoảng cách trên màn tới từng đầu bằng một phép trừ, rồi tự
/// chọn ngưỡng "gần" và tự gọi [ArMeasureController.movePoint] với chỉ số 0 hay
/// 1. Gói cố ý KHÔNG bày một trường "đầu nào đang được chỉ": nó sẽ là một nguồn
/// sự thật thứ hai về hình học màn (app vẽ tâm ngắm ở đâu là việc của app — có
/// màn đẩy nó lên trên một thẻ ở đáy), và nó buộc gói phải chọn một ngưỡng —
/// đúng thứ nó không biết đủ để chọn.
///
/// Một đầu `null` không tạo lỗ hổng nào cho phép so ấy: đầu không chiếu được
/// xuống màn thì cũng không thể là đầu đang nằm gần tâm ngắm.
class ArMeasureOverlay {
  const ArMeasureOverlay({
    this.pointA,
    this.pointB,
    this.bIsLive = false,
    this.distanceMm,
  });

  /// Điểm thứ nhất trên màn. `null` khi chưa chấm điểm nào, và cũng `null` khi
  /// điểm ĐÃ chấm nằm ngoài khối nhìn — sau lưng camera, hoặc quá xa.
  ///
  /// Hai chuyện ấy cố ý không tách nhau: cả hai đều là "không có chỗ nào trên
  /// màn để vẽ", và đó là toàn bộ điều người vẽ cần biết.
  ///
  /// `null` KHÔNG có nghĩa "ngoài mép màn". Một điểm ngoài mép màn vẫn có toạ
  /// độ, và toạ độ ấy **âm hoặc lớn hơn bề màn** — giữ nguyên, vì đoạn thẳng
  /// nối tới nó vẫn cắt qua khung hình và vẫn phải vẽ.
  final Offset? pointA;

  /// Đầu kia của đoạn thẳng trên màn.
  ///
  /// Là điểm thứ hai ĐÃ chấm khi [bIsLive] là `false`, và là giao điểm của tia
  /// tâm ngắm ở khung hình này khi [bIsLive] là `true`.
  ///
  /// `null` theo đúng hai lối của [pointA], cộng một lối thứ ba khi [bIsLive]:
  /// tia tâm ngắm **không trúng gì**. Lúc ấy đừng vẽ đoạn nào — giữ lại đoạn
  /// của khung trước là để một đoạn thẳng đứng yên trên màn, và một đoạn đứng
  /// yên đọc ra "đã chấm xong".
  ///
  /// Lối thứ ba ấy nói "tia đã trượt **một quãng**", không phải "tia trượt ở
  /// khung này": từ `0.9.1` tầng native ôm lượt trúng gần nhất khoảng 100 ms
  /// trước khi buông. Một khung trượt lẻ giữa chuỗi trúng không còn tắt đoạn
  /// thẳng nữa — ở 60 khung/s nó đọc ra một cái nháy chứ không đọc ra một lời
  /// cảnh báo. Lời cảnh báo thật vẫn đi đúng nhịp trên
  /// [ArMeasureSample.aimLocked] và [ArMeasureSample.aimTarget], và **đó** mới
  /// là chỗ đọc câu "bấm bây giờ thì có trúng không".
  ///
  /// Toạ độ cũng đã đi qua một phép làm mượt nhẹ (hằng số thời gian 0,03 s),
  /// nên nó tụt sau tâm ngắm chừng một centimét trong lúc rê máy và về đúng chỗ
  /// khi tay dừng lại. Điểm ĐƯỢC CHẤM không đi qua đó: [ArMeasureController]
  /// bắn một tia mới ở đúng lúc bấm.
  final Offset? pointB;

  /// [pointB] là tâm ngắm đang chạy, chưa chấm.
  ///
  /// Nói về TRẠNG THÁI của phép đo — "mới có một điểm, đầu kia còn chạy theo
  /// máy" — nên nó vẫn `true` ở những khung mà tia trượt và [pointB] là `null`.
  ///
  /// Mặc định `false`: thiếu khoá thì coi như hai điểm đã chốt, và đó là phía
  /// an toàn — một nhãn đứng yên đọc nhầm thành số đã chốt còn đỡ hơn một số đã
  /// chốt bị đọc nhầm thành đang chạy.
  final bool bIsLive;

  /// Khoảng cách giữa hai đầu, milimét — **kể cả khi đầu B còn sống**.
  ///
  /// Đo trong không gian 3D, không đo trên màn: nó là cùng một phép tính với
  /// [ArMeasurement.mm], nên con số chạy và con số chốt không bao giờ lệch nhau
  /// vì hai công thức.
  ///
  /// Vì đo trong 3D nên nó vẫn có giá trị khi [pointA] hoặc [pointB] là `null`
  /// — hai điểm vẫn có thật, chỉ là không chiếu được xuống màn.
  ///
  /// Không kèm dung sai. Dung sai đi với số đã chốt ([ArMeasurement.tolMm]);
  /// một con số đang trôi theo tay người thì ± của nó chưa nói được gì.
  final double? distanceMm;
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

  /// Kênh sự kiện THỨ HAI, chỉ chở [ArMeasureOverlay]. Xem [overlay].
  static const String overlayChannelName = 'headless_ar_measure/overlay';

  /// `viewType` truyền cho [UiKitView] khi dựng [ArMeasureView].
  static const String viewType = 'headless_ar_measure/view';

  static const MethodChannel _method = MethodChannel(methodChannelName);
  static const EventChannel _events = EventChannel(eventChannelName);
  static const EventChannel _overlayEvents = EventChannel(overlayChannelName);

  static Stream<ArMeasureSample>? _samples;
  static Stream<ArMeasureOverlay>? _overlay;

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

  /// Luồng lớp phủ: hai đầu đoạn thẳng ở toạ độ màn, kèm số đo đang chạy.
  ///
  /// Nhịp **khung hình, chặn trên 30 Hz**. Nó là luồng nuôi một lớp vẽ, nên
  /// người nghe phải ghi vào `ValueNotifier` chứ đừng gọi `setState`.
  ///
  /// **Một kênh riêng, không phải một trường mới của [samples].** Trạng thái và
  /// chẩn đoán đổi vài giây một lần; đẩy chúng lên 30 Hz là bắt mọi người nghe
  /// trạng thái lọc ba mươi khung mỗi giây để tìm một thay đổi.
  ///
  /// **Không bao giờ ném, không bao giờ đứt** — cùng lối với [samples]: một
  /// khung không phải `Map` bị bỏ, một lỗi trên kênh bị bỏ.
  ///
  /// Tầng nền **không bắn lại một khung y hệt khung trước**, nên đừng đọc luồng
  /// này như một nhịp tim: im lặng nghĩa là không có gì đổi, không phải hỏng.
  static Stream<ArMeasureOverlay> get overlay {
    return _overlay ??= _overlayEvents
        .receiveBroadcastStream()
        .handleError((Object _) {})
        .map(
          (Object? event) => event is Map
              ? parseOverlay(Map<Object?, Object?>.from(event))
              : null,
        )
        .where((ArMeasureOverlay? o) => o != null)
        .cast<ArMeasureOverlay>();
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
      // Chuỗi lạ về `null` chứ không giết mẫu, y như `limitedReason`: ARKit có
      // thể thêm một tầng ở bản iOS sau, và mất cả mẫu vì một trường trang trí
      // là để màn đo đứng im ở khung hình cuối.
      aimTarget: _parseRaycastTarget(raw['aimTarget']),
      // Qua [_parseFinite] chứ không qua `as num?`, và đây là chỗ nó khác mọi
      // con số khác của mẫu: đây là một cái VAN — app đọc nó để quyết định có
      // được chốt một kết luận theo số đo hay không. NaN đi tiếp thì mọi phép
      // so sánh với nó đều `false`, nên một ngưỡng "vượt quá ngần này thì
      // đừng" lặng lẽ không bao giờ đúng, và cái van câm mà không ai biết.
      aimOvershootMm: _parseFinite(raw['aimOvershootMm']),
      // Cũng qua [_parseFinite], và cùng một lý do với cái van ngay trên: góc
      // này nằm ở MẪU SỐ (`sin θ`) của số hạng dung sai mà app dựng lên. Một
      // `NaN` đi tiếp là `ε` thành `NaN`, mọi phép so sánh với nó `false`, và
      // ngưỡng "sượt quá thì đừng chốt" lặng lẽ không bao giờ đúng.
      aimRayAngleDeg: _parseFinite(raw['aimRayAngleDeg']),
      // Qua [_parseIdentity] chứ không qua `as String?`, và đó không phải một
      // lời gác kiểu cho đủ bộ: giá trị này chỉ dùng để SO SÁNH BẰNG NHAU, nên
      // một chuỗi RỖNG lọt qua là hai mặt phẳng bất kỳ đọc ra "cùng một mặt
      // phẳng" — đúng kết luận sai mà trường này sinh ra để chặn, và nó sai im
      // lặng, về phía "yên tâm".
      aimPlaneId: _parseIdentity(raw['aimPlaneId']),
      // Sai kiểu coi như THIẾU, và không giết mẫu — cùng lối rẽ với mọi khoá
      // phụ khác. Mất một mẫu vì một trường không tham gia phép tính nào là để
      // màn đo đứng im ở khung hình cuối.
      grabbedPointIndex: raw['grabbedPointIndex'] is int
          ? raw['grabbedPointIndex']! as int
          : null,
      diagnostics: _parseDiagnostics(raw['diagnostics']),
    );
  }

  /// Đọc một tầng tia. Dùng chung cho tia ĐANG ngắm và cho chẩn đoán của một
  /// điểm ĐÃ chấm — một bảng dịch, không phải hai bản chép lệch nhau được.
  static ArRaycastTarget? _parseRaycastTarget(Object? raw) => switch (raw) {
    'existingPlaneGeometry' => ArRaycastTarget.existingPlaneGeometry,
    'existingPlaneInfinite' => ArRaycastTarget.existingPlaneInfinite,
    'estimatedPlane' => ArRaycastTarget.estimatedPlane,
    _ => null,
  };

  /// Đọc khối chẩn đoán. **Không bao giờ ném, và không bao giờ giết mẫu.**
  ///
  /// Chẩn đoán là thứ đi kèm: một khoá hỏng ở đây mà làm mất cả mẫu thì tầng
  /// chẩn đoán tự nó thành một lỗi sản phẩm — màn đo đứng im ở khung hình cuối
  /// vì một trường không ai nhìn.
  static ArMeasureDiagnostics? _parseDiagnostics(Object? raw) {
    if (raw is! Map) return null;

    final rawPoints = raw['points'];
    // Phần tử hỏng thành một điểm TRỐNG, không bị loại khỏi danh sách. Loại nó
    // ra là điểm thứ hai trượt lên chỗ điểm thứ nhất, và cả dải chẩn đoán nói
    // dối về việc điểm nào được chấm trong điều kiện nào — im lặng, và người
    // đọc không có cách nào biết.
    final points = rawPoints is List
        ? rawPoints
              .map(
                (Object? p) => p is Map
                    ? _parsePointDiagnostics(Map<Object?, Object?>.from(p))
                    : const ArPointDiagnostics(),
              )
              .toList(growable: false)
        : const <ArPointDiagnostics>[];

    final video = _parseVideoFormat(raw['video']);
    final features = _parseFeatureCensus(raw['features']);
    final camera = _parseCameraIntrinsics(raw['camera']);

    // Không có mẩu nào trong bốn mẩu thì cả khối về `null`, không phải một đối
    // tượng rỗng: rỗng đọc ra "đã đo và không có gì", còn `null` đọc đúng nghĩa
    // "bản nền này không nói". Nhưng chỉ MỘT mẩu có mặt là ĐỦ để khối tồn tại —
    // khuôn hình, phép đếm vân và thấu kính đều có nghĩa từ trước khi có điểm
    // nào, và đó đúng là lúc người ta cần chúng.
    if (points.isEmpty && video == null && features == null && camera == null) {
      return null;
    }

    return ArMeasureDiagnostics(
      points: points,
      video: video,
      features: features,
      camera: camera,
    );
  }

  /// Đọc khối thấu kính. Cùng lối với [_parseVideoFormat]: sai kiểu hay thiếu
  /// về `null`, và một map hỏng KHÔNG giết cả khối chẩn đoán.
  ///
  /// `fx` đi qua [_parseFinite] rồi còn phải **dương**, khác hẳn hai ô kia. Một
  /// tiêu cự bằng `0` không phải một sự thật ("thấu kính dài không điểm ảnh" là
  /// một câu vô nghĩa) — nó là một con số hỏng, và nó hỏng ở chỗ nguy hiểm
  /// nhất: dưới gạch chia. Bề rộng và bề cao thì chỉ để đọc và để quy đổi, nên
  /// chúng đi cửa thường.
  static ArCameraIntrinsics? _parseCameraIntrinsics(Object? raw) {
    if (raw is! Map) return null;

    final fx = _parseFinite(raw['fx']);
    final rawWidth = raw['width'];
    final rawHeight = raw['height'];

    return ArCameraIntrinsics(
      fx: (fx != null && fx > 0) ? fx : null,
      width: rawWidth is num ? rawWidth.round() : null,
      height: rawHeight is num ? rawHeight.round() : null,
    );
  }

  /// Đọc khối đếm điểm đặc trưng. Cùng lối với [_parseVideoFormat]: sai kiểu
  /// hay thiếu về `null`, và một map hỏng KHÔNG giết cả khối chẩn đoán.
  ///
  /// `0` KHÔNG được đổ chung với `null`, và cả phép đo nằm ở chỗ phân biệt hai
  /// thứ ấy: `0` là "ARKit có đám mây điểm và đám mây rỗng" — một sự thật, và
  /// là sự thật đóng được quyết định; `null` là "không hỏi được".
  static ArFeatureCensus? _parseFeatureCensus(Object? raw) {
    if (raw is! Map) return null;

    final rawTotal = raw['total'];
    final rawNearRay = raw['nearRay'];

    return ArFeatureCensus(
      total: rawTotal is num ? rawTotal.round() : null,
      nearRay: rawNearRay is num ? rawNearRay.round() : null,
    );
  }

  /// Đọc khuôn hình. Mọi trường sai kiểu hay thiếu về `null`, và một map hỏng
  /// KHÔNG giết cả khối chẩn đoán.
  static ArVideoFormat? _parseVideoFormat(Object? raw) {
    if (raw is! Map) return null;

    final rawWidth = raw['width'];
    final rawHeight = raw['height'];
    final rawFps = raw['fps'];

    return ArVideoFormat(
      width: rawWidth is num ? rawWidth.round() : null,
      height: rawHeight is num ? rawHeight.round() : null,
      fps: rawFps is num ? rawFps.round() : null,
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
      target: _parseRaycastTarget(raw['target']),
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
      // Cùng cửa lọc với `aimPlaneId` của [parseSample], và cùng một lẽ: đây là
      // một chuỗi để SO SÁNH, không phải một chuỗi để đọc. Một chuỗi rỗng ở đây
      // làm hai điểm bất kỳ đọc ra "cùng một mặt phẳng".
      planeId: _parseIdentity(raw['planeId']),
      planeAlignment: switch (raw['planeAlignment']) {
        'horizontal' => ArPlaneAlignment.horizontal,
        'vertical' => ArPlaneAlignment.vertical,
        _ => null,
      },
      planeWidthMm: rawWidth is num ? rawWidth.toDouble() : null,
      planeHeightMm: rawHeight is num ? rawHeight.toDouble() : null,
      // Cùng lối với `aimOvershootMm` của [parseSample], và khác mọi con số
      // khác của chính khối này: quãng vượt biên là cái VAN, còn bảy trường
      // trên là số liệu để ĐỌC. Một `NaN` ở `rayAngleDeg` in ra "NaN" và người
      // đọc thấy ngay; một `NaN` ở đây lọt qua mọi phép so sánh mà không ai
      // thấy.
      overshootMm: _parseFinite(raw['overshootMm']),
    );
  }

  /// Dựng một khung lớp phủ từ dữ liệu kênh. Công khai để test được mà không
  /// cần kênh thật, y như [parseSample].
  ///
  /// **Không bao giờ trả `null`, và không bao giờ ném.** Khác [parseSample] ở
  /// chỗ ấy, vì ở đây không có trường nào đóng vai `status` — không có gì để
  /// một khung "hỏng đến mức phải bỏ". Một khung RỖNG là khung hợp lệ và có
  /// nghĩa hẳn hoi: "không còn gì để vẽ", đúng cái tầng nền phải nói ra sau một
  /// lượt Hoàn tác. Bỏ nó đi là để đoạn thẳng cũ nằm lại trên màn.
  ///
  /// Mọi trường thiếu hoặc sai kiểu rơi về `null` (hoặc `false` với [
  /// ArMeasureOverlay.bIsLive]) — cùng một lối với `mm`/`tolMm` của
  /// [parseSample].
  static ArMeasureOverlay parseOverlay(Map<Object?, Object?> raw) {
    final rawBIsLive = raw['bIsLive'];

    return ArMeasureOverlay(
      pointA: _parsePoint(raw['ax'], raw['ay']),
      pointB: _parsePoint(raw['bx'], raw['by']),
      bIsLive: rawBIsLive is bool ? rawBIsLive : false,
      distanceMm: _parseFinite(raw['distanceMm']),
    );
  }

  /// Ghép hai nửa toạ độ thành một điểm. Thiếu hoặc hỏng **một** nửa thì cả
  /// điểm về `null`.
  ///
  /// Bù 0 cho nửa thiếu là đặt một đầu đoạn thẳng lên mép trên hoặc mép trái
  /// màn — một chỗ trông hoàn toàn hợp lệ, nên không ai soi ra được.
  ///
  /// Toạ độ ÂM đi qua nguyên vẹn: một đầu đoạn thẳng nằm ngoài mép màn là
  /// chuyện thường ở tầm đo gần, và đoạn nối tới nó vẫn cắt qua khung hình. Thứ
  /// bị loại là điểm nằm **sau lưng camera**, và nó bị loại ở tầng Swift — nơi
  /// còn thành phần z của phép chiếu để mà loại.
  static Offset? _parsePoint(Object? rawX, Object? rawY) {
    final x = _parseFinite(rawX);
    final y = _parseFinite(rawY);
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  /// Một chuỗi định danh dùng được, hoặc `null`.
  ///
  /// Chặn cả chuỗi RỖNG, không chỉ chặn sai kiểu — và đây là chỗ nó khác một
  /// phép ép kiểu thường. Chuỗi này không bao giờ được ĐỌC, nó chỉ được SO
  /// SÁNH; mà `'' == ''` là `true`, nên hai giá trị rỗng đọc ra "cùng một mặt
  /// phẳng" cho hai mặt phẳng chẳng liên quan gì nhau. Đó đúng là kết luận sai
  /// mà cả trường này sinh ra để chặn, và nó không in ra một dấu hiệu nào.
  ///
  /// Không cắt khoảng trắng, không đổi hoa thường, không kiểm khuôn `UUID`: gói
  /// không hứa giá trị này có dạng gì, và một phép chuẩn hoá là một chỗ nữa để
  /// hai giá trị khác nhau bị kéo về bằng nhau.
  static String? _parseIdentity(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return raw;
  }

  /// Một số thực hữu hạn, hoặc `null`.
  ///
  /// Chặn cả NaN và vô cực, không chỉ chặn sai kiểu: `Offset(nan, nan)` dựng
  /// được, so sánh được, và `Canvas.drawLine` chỉ lặng lẽ **không vẽ** nó —
  /// một đoạn thẳng biến mất mà không lỗi nào nổ.
  static double? _parseFinite(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite ? value : null;
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

ArMeasureMoveResult _parseMoveResult(Object? raw) {
  return switch (raw) {
    'moved' => ArMeasureMoveResult.moved,
    'missed' => ArMeasureMoveResult.missed,
    'notReady' => ArMeasureMoveResult.notReady,
    'noSuchPoint' => ArMeasureMoveResult.noSuchPoint,
    // Mọi thứ không đọc được đổ về `notReady`, KHÔNG về `noSuchPoint`: xem lời
    // chú của hai giá trị ấy.
    _ => ArMeasureMoveResult.notReady,
  };
}

ArMeasureGrabResult _parseGrabResult(Object? raw) {
  return switch (raw) {
    'grabbed' => ArMeasureGrabResult.grabbed,
    'notReady' => ArMeasureGrabResult.notReady,
    'noSuchPoint' => ArMeasureGrabResult.noSuchPoint,
    'alreadyGrabbing' => ArMeasureGrabResult.alreadyGrabbing,
    // Mọi thứ không đọc được đổ về `notReady`, KHÔNG về `noSuchPoint`: cùng
    // một luật với [_parseMoveResult].
    _ => ArMeasureGrabResult.notReady,
  };
}

ArMeasureReleaseResult _parseReleaseResult(Object? raw) {
  return switch (raw) {
    'released' => ArMeasureReleaseResult.released,
    'unmoved' => ArMeasureReleaseResult.unmoved,
    'notGrabbing' => ArMeasureReleaseResult.notGrabbing,
    'notReady' => ArMeasureReleaseResult.notReady,
    // Không đọc được đổ về `notReady`, KHÔNG về `notGrabbing`: "không nắm gì"
    // là một câu về trạng thái của một PHIÊN, và một kênh câm không có phiên
    // nào để nói về.
    _ => ArMeasureReleaseResult.notReady,
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

  /// Dời điểm thứ [index] tới chỗ tia tâm ngắm ĐANG trúng.
  ///
  /// Hợp lệ là `0 <= index < số điểm đã chấm` — chỉ số phải trỏ vào một điểm
  /// đang có, không phải "phải đủ hai điểm". Với một điểm thì `movePoint(0)`
  /// chạy được; với hai điểm thì `0` và `1`; chưa chấm gì thì mọi chỉ số ra
  /// [ArMeasureMoveResult.noSuchPoint]. Thứ tự chỉ số là thứ tự CHẤM, và nó
  /// khớp thứ tự của [ArMeasureDiagnostics.points] cũng như cặp
  /// [ArMeasureOverlay.pointA]/[ArMeasureOverlay.pointB].
  ///
  /// **Dời hụt thì điểm cũ còn nguyên.** Tia trượt trả
  /// [ArMeasureMoveResult.missed] và không đụng gì tới phép đo — xem lời chú
  /// của giá trị ấy.
  ///
  /// **Lai lịch đi theo điểm MỚI, cả khối.** Điểm sau khi dời khai tầng tia,
  /// quãng vượt biên, định danh mặt phẳng, góc và cự ly của lần dời **này**, đo
  /// tại đúng cú bấm — không mang một mẩu nào của lần chấm cũ. Đây là chỗ dễ
  /// sót nhất và cũng là chỗ đắt nhất: một điểm dời sang mặt phẳng khác mà vẫn
  /// khai định danh cũ làm mọi tín hiệu trung thực của gói nói dối, và nói dối
  /// bằng những con số trông hoàn toàn hợp lệ.
  ///
  /// **Số đo tính lại ngay**, và nó vẫn TRÔI như thường cho tới khi app chốt —
  /// xem [ArMeasurement.tolMm] và [ArMeasureOverlay.distanceMm].
  ///
  /// **Điểm dời KHÔNG đi qua bộ lọc đầu mút sống.** Nó bắn một tia mới ở đúng
  /// lúc bấm, y như [placePoint]: bộ lọc phục vụ một điểm được vẽ lại 60 lần
  /// mỗi giây, và cái giá của nó là độ trễ — một sai số hệ thống không có chỗ
  /// trong một điểm đã chốt.
  ///
  /// **Gói KHÔNG quyết định khi nào được dời.** Chuyện "hồng tâm ở gần đầu mút
  /// thì bắt lấy" là việc của app, và app có đủ dữ kiện để tự làm: [ArMeasure.overlay]
  /// bắn ra toạ độ MÀN của cả hai đầu, còn tâm ngắm nằm giữa [ArMeasureView] mà
  /// chính app đã đặt. Ngưỡng "gần" là một lựa chọn về giao diện — nó phụ thuộc
  /// cỡ ngón tay, cỡ màn, và chỗ app vẽ nút — nên gói không đặt nó, cùng một
  /// ranh giới với [ArPointDiagnostics.overshootMm].
  ///
  /// Không bao giờ ném: một kênh chết cũng ra [ArMeasureMoveResult.notReady].
  Future<ArMeasureMoveResult> movePoint(int index) async {
    try {
      final raw = await ArMeasure._method.invokeMethod<String>('movePoint', {
        'viewId': viewId,
        'index': index,
      });
      return _parseMoveResult(raw);
    } catch (_) {
      return ArMeasureMoveResult.notReady;
    }
  }

  /// **NẮM** điểm thứ [index]: mở một quãng kéo.
  ///
  /// Từ khung hình kế tiếp, đầu mút ấy bám theo giao điểm của tia tâm ngắm —
  /// **mỗi khung hình**, ở tầng nền, trong cùng lượt dò mà tâm ngắm đã chạy.
  /// Không có lượt bắn tia thứ hai, và không có lượt gọi kênh nào trong suốt
  /// quãng kéo.
  ///
  /// **Đừng cài quãng nắm bằng cách gọi [movePoint] liên tục** — xem
  /// [ArMeasureGrabResult].
  ///
  /// Chỉ số hợp lệ là chỉ số trỏ vào một điểm ĐANG CÓ, cùng luật với
  /// [movePoint]: một điểm thì `0`; hai điểm thì `0` và `1`.
  ///
  /// **Trong lúc nắm, tia TRƯỢT thì đầu mút ĐỨNG YÊN** — nó không rơi về chỗ
  /// cũ và không biến mất. Một cái thước dây không rơi mất đầu khi tay che mất
  /// vạch. App không mất tin ấy: [ArMeasureSample.aimTarget] và
  /// [ArMeasureSample.aimLocked] vẫn nói ra, đúng nhịp, suốt quãng kéo.
  ///
  /// **Số đo và [ArMeasure.overlay] chạy theo liên tục.** Số vẫn TRÔI như mọi
  /// số chưa chốt.
  ///
  /// Đừng nhớ lấy "đang nắm đầu nào" từ giá trị trả về của hàm này — đọc
  /// [ArMeasureSample.grabbedPointIndex], vì gói tự buông ở những đường app
  /// không gây ra.
  ///
  /// Không bao giờ ném: một kênh chết cũng ra [ArMeasureGrabResult.notReady].
  Future<ArMeasureGrabResult> grabPoint(int index) async {
    try {
      final raw = await ArMeasure._method.invokeMethod<String>('grabPoint', {
        'viewId': viewId,
        'index': index,
      });
      return _parseGrabResult(raw);
    } catch (_) {
      return ArMeasureGrabResult.notReady;
    }
  }

  /// **BUÔNG**: đóng quãng nắm và chốt điểm ở chỗ nó đang đứng.
  ///
  /// Không nhận chỉ số, và đó là chủ đích: phiên đang nắm đúng một đầu và chỉ
  /// nó biết đầu nào. Bắt app nói lại chỉ số ở lúc buông là dựng một nguồn sự
  /// thật thứ hai, và hai nguồn ấy lệch nhau ở đúng những đường gói TỰ buông.
  ///
  /// **Chốt lượt trúng CUỐI của quãng kéo** — không chốt vệt đã làm mượt mà mắt
  /// vừa nhìn theo, và không bắn một tia mới ở đúng khung hình buông. Hai lối
  /// kia đều hỏng: một bên là vị trí và lai lịch lệch nhau đúng bằng độ trễ của
  /// bộ lọc (kéo qua ranh giới hai mặt phẳng rồi buông ngay là một điểm ĐỨNG
  /// trên mặt này mà KHAI mặt kia); một bên là một khung trượt ở đúng khoảnh
  /// khắc ấy vứt cả quãng kéo và điểm nhảy ngược về chỗ trước khi nắm.
  ///
  /// **Lai lịch tính lại ở đây, và là lai lịch của chỗ CUỐI, cả khối**: tầng
  /// tia, quãng vượt biên, định danh mặt phẳng, góc và cự ly đều của lượt trúng
  /// cuối, đo tại chính khung hình đã đặt điểm tới chỗ ấy. Trong lúc kéo thì
  /// mọi lai lịch đều là TẠM — đừng đọc [ArMeasureSample.diagnostics] của một
  /// mẫu giữa quãng kéo như một kết luận.
  ///
  /// Gọi được bao nhiêu lần cũng không sao: lượt thứ hai ra
  /// [ArMeasureReleaseResult.notGrabbing] và không đụng gì.
  ///
  /// Không bao giờ ném: một kênh chết cũng ra [ArMeasureReleaseResult.notReady].
  Future<ArMeasureReleaseResult> releasePoint() async {
    try {
      final raw = await ArMeasure._method.invokeMethod<String>('releasePoint', {
        'viewId': viewId,
      });
      return _parseReleaseResult(raw);
    } catch (_) {
      return ArMeasureReleaseResult.notReady;
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

  /// Ghi khung hình camera hiện tại ra một tệp JPEG trong thư mục TẠM, và trả
  /// đường dẫn của nó.
  ///
  /// Khung **THUẦN**: không hai chấm, không đoạn thẳng, không một chữ nào. Gói
  /// vẽ hai thứ đầu trong SceneKit vì chỉ tầng Swift biết chúng chiếu xuống màn
  /// ở đâu; nhưng một tấm ảnh thì người gọi hợp lấy, và hợp trên một nền đã có
  /// sẵn nửa lớp phủ là vẽ đè hai lần lệch một nhịp.
  ///
  /// Cỡ ảnh bằng cỡ **khung ngắm** nhân hệ số điểm ảnh của màn, và chiều ảnh
  /// nướng thẳng vào điểm ảnh (không cờ EXIF). Nên toạ độ mà [ArMeasure.overlay]
  /// bắn ra — cùng khung ngắm ấy, đơn vị point — quy sang toạ độ ảnh bằng đúng
  /// một phép nhân.
  ///
  /// `null` nghĩa là KHÔNG có tệp nào: phiên chưa chạy, view đã chết, kênh
  /// hỏng, hay đĩa không ghi được. Không bao giờ ném, và không bao giờ trả một
  /// chuỗi rỗng — chuỗi rỗng đi tiếp được vào một `File` rồi mới nổ, xa chỗ
  /// hỏng.
  ///
  /// **Tệp là của người gọi.** Gói không xoá nó, và thư mục tạm chỉ được hệ
  /// điều hành dọn theo lịch riêng của nó.
  Future<String?> captureFrame() async {
    try {
      return await ArMeasure._method.invokeMethod<String>('captureFrame', {
        'viewId': viewId,
      });
    } catch (_) {
      return null;
    }
  }

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
