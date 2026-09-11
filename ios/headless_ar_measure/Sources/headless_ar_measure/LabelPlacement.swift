import Foundation
import simd

/// Chỗ đứng của tấm ảnh dán trên đoạn: hướng, cỡ, và phép lật.
///
/// **Chỉ nhập `Foundation` và `simd`**, cùng lý do với `PlaneOvershoot` và
/// `VideoFormatChoice`: ba luật ở đây làm sai thì tệp Swift vẫn trông hoàn toàn
/// hợp lý, vẫn trả về những con số hữu hạn cỡ đúng hàng, và SceneKit vẫn vẽ ra
/// một cái gì đó. Thứ phân biệt đúng với sai là GIÁ TRỊ — nên chúng phải nằm ở
/// một tệp `swiftc` dịch và chạy được trên macOS, không cần một máy iOS nào.
///
/// Gói **không biết trên tấm ảnh viết gì**. Nó nhận một tấm ảnh và một tỉ lệ
/// điểm ảnh; mọi phông chữ, màu và câu chữ là việc của app.
enum LabelPlacement {
  // MARK: - Hằng số

  /// Nửa bề rộng DẢI TRỄ của phép lật nửa vòng, tính bằng độ.
  ///
  /// **Vì sao phải có trễ.** Tấm ảnh xoay theo đoạn, nên khi đoạn đi qua phương
  /// đứng trên màn thì chữ chúc ngược và tấm ảnh phải lật nửa vòng cho đọc
  /// được. Một mốc lật ĐƠN ở đúng 90° nghĩa là hai bên mốc chỉ cách nhau một
  /// phần nghìn độ, mà tay người thì rung quanh đúng cái mốc ấy — tấm ảnh lật
  /// đi lật lại, và **chữ NHẢY**.
  ///
  /// Kho `lobanar_app` đã trả giá cho đúng cơ chế này hai lần: một ở mặt số la
  /// bàn (bản trước lật nửa vòng cho nửa dưới đọc xuôi, và cả một nửa vành lật
  /// đồng loạt mỗi lần xoay máy), một ở chính viên số này hồi nó còn được vẽ
  /// bằng Flutter.
  ///
  /// **8° là một hằng số CHỌN, chưa đo trên máy.** Hai nguồn dao động nó nhắm:
  /// rung tay ở tầm ngực (một vài độ quanh trục nhìn), và nhiễu góc của một
  /// đoạn NGẮN trên màn — góc suy từ hai đầu đã chiếu, nên sai số toạ độ khuếch
  /// đại lên khi đoạn ngắn. Nguồn thứ hai lớn hơn, và là lý do dải không hẹp
  /// hơn.
  ///
  /// Trần của nó: trong dải trễ, chữ đọc nghiêng tới 8° quá phương đứng. Ở
  /// quanh phương đứng thì trên–dưới vốn đã gần như không phân biệt được, nên
  /// tám độ ấy không đọc ra khác gì.
  static let flipHysteresisDegrees: Double = 8

  /// Quãng khoảng cách mà cỡ trên màn giữ ĐÚNG cỡ danh định, tính bằng mét.
  ///
  /// **Luật cỡ, và lý do của nó.** Có hai lối cực đoan, và cả hai đều hỏng:
  ///
  /// * **Cỡ THẬT cố định** (cùng lối với chấm đầu mút, xem `ArMeasureNodes`):
  ///   tấm ảnh nhỏ dần khi lùi máy, và ở 3 m thì con số không đọc nổi. Với một
  ///   cái chấm thì chấp nhận được — chấm chỉ cần thấy; với chữ thì không.
  /// * **Cỡ MÀN cố định tuyệt đối** (cỡ thật tỉ lệ thuận với khoảng cách, ở mọi
  ///   khoảng cách): đọc được ở mọi cự ly, nhưng ở cự ly rất gần nó **che mất
  ///   chính cái vật đang đo**. Người ta tới gần để đo thứ NHỎ, nên một tấm ảnh
  ///   rộng 60 pt cố định nuốt trọn một khe 5 cm đang chiếm 60 pt trên màn. Và
  ///   ở cự ly rất xa, cỡ thật nở ra hàng mét: tấm ảnh chui qua tường và chui
  ///   vào vật.
  ///
  /// Luật chọn: **cỡ màn cố định, KẸP theo khoảng cách.** Trong
  /// `[nearClampMetres, farClampMetres]` cỡ trên màn không đổi một chút nào.
  /// Ngoài quãng ấy cỡ THẬT đứng yên, nên cỡ màn đổi theo đúng tỉ lệ
  /// `cạnh kẹp / khoảng cách` — mềm, không nhảy bậc, và đổi theo chiều có ích:
  /// tới quá gần thì tấm ảnh TO lên (lời mời lùi lại), lùi quá xa thì nó nhỏ đi
  /// cùng với chính cái đoạn nó chú thích.
  ///
  /// **Quãng còn đọc được.** Đúng cỡ danh định từ 0,30 m tới 3,00 m — cùng quãng
  /// mà `ArMeasureNodes` đã ghi là tầm đo của gói. Ngoài đó nó suy giảm tuyến
  /// tính: ở 6 m còn một nửa, ở 0,15 m gấp đôi. Với cỡ danh định 19 pt của app
  /// hiện tại, nửa cỡ vẫn đọc được trên màn Retina, nên quãng dùng được thực tế
  /// là khoảng **0,2 m – 5 m**. Quá đó thì con số ở dải đáy là chỗ đọc, không
  /// phải tấm ảnh trên đoạn.
  ///
  /// Hai hằng này **chọn bằng lý lẽ, chưa nghiệm thu trên máy**.
  static let nearClampMetres: Double = 0.30
  static let farClampMetres: Double = 3.00

  // MARK: - Hệ trục

  /// Ba trục của tấm ảnh trong hệ THẾ GIỚI, trực chuẩn và thuận tay phải.
  ///
  /// `x` chạy dọc đoạn (bề ngang tấm ảnh), `y` là chiều dựng của tấm ảnh, `z`
  /// là pháp tuyến và nó quay VỀ PHÍA camera.
  struct Basis {
    let x: SIMD3<Float>
    let y: SIMD3<Float>
    let z: SIMD3<Float>
  }

  /// Hệ trục cho một đoạn và một hướng nhìn.
  ///
  /// **Mặt phẳng của tấm ảnh CHỨA đoạn, và nó quay quanh trục của đoạn cho tới
  /// khi mặt hướng về camera** — như con số trên một cái thước dây thật quay về
  /// phía người đọc. Nên `z` là phần của véc-tơ tới camera còn lại sau khi trừ
  /// đi thành phần dọc đoạn, chứ không phải chính véc-tơ ấy: lấy thẳng nó là
  /// một billboard đủ ba trục, và lúc ấy tấm ảnh thôi nằm dọc đoạn.
  ///
  /// **[flipped] là nửa vòng quanh PHÁP TUYẾN**, tức đảo cả `x` lẫn `y` và giữ
  /// nguyên `z`. Đừng lật quanh trục của đoạn: phép ấy cũng làm chữ đọc xuôi,
  /// nhưng nó quay LƯNG tấm ảnh về camera — và trên màn tấm ảnh biến mất (hoặc
  /// hiện ra ảnh gương, nếu vật liệu hai mặt). Một lỗi không có triệu chứng nào
  /// ngoài "thỉnh thoảng không thấy con số".
  ///
  /// **Không bao giờ trả về một hệ trục rác.** Hai đường suy biến, và cả hai là
  /// cảnh THẬT chứ không phải góc hiếm:
  ///
  /// * **Đoạn dài 0** — hai đầu trùng nhau ở khung hình đầu của một lượt kéo.
  /// * **Camera nằm đúng trên đường thẳng chứa đoạn** — tức người ta đang ngắm
  ///   dọc theo chính cái cạnh đang đo. Phần vuông góc bằng 0, và một phép
  ///   chuẩn hoá thẳng tay cho ra NaN. Node có transform NaN thì SceneKit bỏ
  ///   vẽ, im lặng, không lỗi nào nổ.
  static func basis(
    segment: SIMD3<Float>,
    toCamera: SIMD3<Float>,
    flipped: Bool
  ) -> Basis {
    let u = unit(segment) ?? SIMD3<Float>(1, 0, 0)

    let residual = toCamera - simd_dot(toCamera, u) * u
    let z = unit(residual) ?? anyPerpendicular(of: u)

    let x = flipped ? -u : u
    // `z × x`, theo đúng thứ tự ấy: đổi chỗ hai vế cho ra một hệ trục TRÁI tay,
    // và một hệ trái tay quy sang quaternion vẫn ra một quaternion chuẩn hoá.
    // Không có gì nổ; tấm ảnh chỉ lộn ngược.
    let y = simd_cross(z, x)

    return Basis(x: x, y: y, z: z)
  }

  /// Quaternion đưa hệ trục chuẩn của node về [Basis].
  static func orientation(_ basis: Basis) -> simd_quatf {
    simd_quatf(simd_float3x3(columns: (basis.x, basis.y, basis.z)))
  }

  // MARK: - Phép lật

  /// Tấm ảnh có phải LẬT nửa vòng hay không, cho một véc-tơ trục X đã chiếu
  /// xuống màn và trạng thái lật ĐANG CÓ.
  ///
  /// [screenDelta] là hiệu hai toạ độ MÀN (point, `y` đi XUỐNG — cùng hệ với
  /// `SCNSceneRenderer.projectPoint`) của hai điểm nằm trên trục X của tấm ảnh.
  ///
  /// Hàm THUẦN, và trạng thái đi vào rồi đi ra bằng tham số: nó là chỗ duy nhất
  /// giữ luật trễ, còn chỗ NHỚ trạng thái là phiên. Chôn một biến nhớ trong đây
  /// là biến một hàm kiểm được thành một hàm không kiểm được.
  ///
  /// Đầu vào suy biến — hai điểm trùng nhau, hay một toạ độ không hữu hạn — thì
  /// **GIỮ NGUYÊN** trạng thái đang có, không rơi về `false`: một khung hình
  /// không đọc được mà làm tấm ảnh lật là con số nhảy trong lúc không ai đụng
  /// gì.
  static func isFlipped(
    screenDelta: SIMD2<Double>,
    wasFlipped: Bool,
    hysteresisDegrees: Double = flipHysteresisDegrees
  ) -> Bool {
    guard screenDelta.x.isFinite, screenDelta.y.isFinite else { return wasFlipped }
    guard screenDelta.x != 0 || screenDelta.y != 0 else { return wasFlipped }

    // Quy về [0, 180]: chữ đọc xuôi khi trục nghiêng dưới một phần tư vòng so
    // với phương ngang, bất kể nó chỉ sang trái hay sang phải.
    let degrees = abs(atan2(screenDelta.y, screenDelta.x)) * 180 / Double.pi
    let half = max(0, hysteresisDegrees)

    return wasFlipped ? degrees > 90 - half : degrees > 90 + half
  }

  // MARK: - Luật cỡ

  /// Cỡ trên màn so với cỡ danh định: `1` nghĩa là đúng cỡ tấm ảnh đã gửi.
  ///
  /// Bằng `1` suốt quãng `[nearClampMetres, farClampMetres]`, và ngoài quãng ấy
  /// nó là `cạnh kẹp / khoảng cách`. Xem [nearClampMetres] về lý do có kẹp.
  ///
  /// Trả `0` cho mọi đầu vào không dùng được — đó là giá trị nói "không có cỡ
  /// nào", và người gọi đọc nó là "đừng vẽ", chứ không phải một cỡ rác.
  static func screenScale(
    distanceMetres distance: Double,
    nearClampMetres near: Double = nearClampMetres,
    farClampMetres far: Double = farClampMetres
  ) -> Double {
    guard distance.isFinite, distance > 0 else { return 0 }
    guard near.isFinite, far.isFinite, near > 0, far >= near else { return 0 }
    return min(max(distance, near), far) / distance
  }

  /// Cỡ THẬT của tấm ảnh (chiều dựng, mét) để nó cao [pointHeight] point trên
  /// màn.
  ///
  /// [pointsPerMetre] là số point mà một mét ở ĐÚNG khoảng cách ấy chiếm trên
  /// màn — nó tỉ lệ nghịch với khoảng cách, và đó là toàn bộ phép phối cảnh mà
  /// luật cỡ phải khử. Người gọi ĐO nó bằng chính phép chiếu của SceneKit chứ
  /// không suy từ trường nhìn: phép chiếu của view đã gánh cả hướng giao diện,
  /// cả tỉ lệ khung ngắm, và nó là con số duy nhất trong gói đã được đối chiếu
  /// với máy thật.
  ///
  /// Trả `0` cho mọi đầu vào không dùng được, cùng lẽ với [screenScale]: `NaN`
  /// hay vô cực gán vào `simdScale` làm SceneKit bỏ vẽ cả node — im lặng.
  static func worldHeight(
    pointHeight: Double,
    pointsPerMetre: Double,
    distanceMetres: Double,
    nearClampMetres near: Double = nearClampMetres,
    farClampMetres far: Double = farClampMetres
  ) -> Double {
    guard pointHeight.isFinite, pointHeight > 0 else { return 0 }
    guard pointsPerMetre.isFinite, pointsPerMetre > 0 else { return 0 }

    let scale = screenScale(
      distanceMetres: distanceMetres, nearClampMetres: near, farClampMetres: far)
    guard scale > 0 else { return 0 }

    let height = pointHeight / pointsPerMetre * scale
    return height.isFinite ? height : 0
  }

  // MARK: - Phụ

  /// Véc-tơ đơn vị, hoặc `nil` khi không có hướng nào đọc được.
  ///
  /// Ngưỡng chứ không phải phép so với 0: một véc-tơ dài `1e-20` chuẩn hoá được
  /// về mặt toán học nhưng hướng của nó là nhiễu dấu phẩy động thuần tuý.
  private static func unit(_ v: SIMD3<Float>) -> SIMD3<Float>? {
    guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { return nil }
    let length = simd_length(v)
    guard length.isFinite, length > 1e-5 else { return nil }
    return v / length
  }

  /// Một véc-tơ đơn vị bất kỳ vuông góc với [u], chọn một cách XÁC ĐỊNH.
  ///
  /// Nhân có hướng với trục thế giới ÍT song song nhất với [u]: chọn trục gần
  /// song song là đúng chỗ tích có hướng tiến về 0, tức là đúng chỗ phép chuẩn
  /// hoá ngay sau đó mất hết chữ số có nghĩa.
  ///
  /// Xác định chứ không ngẫu nhiên, cùng lẽ với `VideoFormatChoice`: một phép
  /// chọn đổi ý giữa hai lượt chạy biến mọi ca kiểm của nó thành ca thi thoảng
  /// đỏ — và trên màn là một tấm ảnh xoay một cái không ai gây ra.
  private static func anyPerpendicular(of u: SIMD3<Float>) -> SIMD3<Float> {
    let ax = abs(u.x)
    let ay = abs(u.y)
    let az = abs(u.z)

    let axis: SIMD3<Float>
    if ax <= ay, ax <= az {
      axis = SIMD3<Float>(1, 0, 0)
    } else if ay <= az {
      axis = SIMD3<Float>(0, 1, 0)
    } else {
      axis = SIMD3<Float>(0, 0, 1)
    }

    return unit(simd_cross(u, axis)) ?? SIMD3<Float>(0, 0, 1)
  }
}
