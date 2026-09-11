import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseSample', () {
    test('đủ trường', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
        'snappedToEdge': true,
      });

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement?.mm, 812);
    });

    test('trạng thái lạ trả null thay vì ném', () {
      expect(ArMeasure.parseSample({'status': 'vệ tinh'}), isNull);
    });

    test('trạng thái không kèm số đo vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'needsMotion'});

      expect(s?.status, ArMeasureStatus.needsMotion);
      expect(s?.measurement, isNull);
    });

    // Tầng nền (Swift) gửi sai kiểu không phải chuyện giả định — một khung
    // hình lỗi kiểu không được phép ném, vì nó sẽ giết cả Stream đang lắng
    // nghe EventChannel. Coi sai kiểu như thiếu trường: measurement về null,
    // status vẫn được giữ nguyên.
    test('mm sai kiểu (chuỗi) không ném, số đo về null', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 'not-a-number',
          'tolMm': 12.0,
          'snappedToEdge': true,
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement, isNull);
    });

    test('tolMm sai kiểu (chuỗi) không ném, số đo về null', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 812.0,
          'tolMm': 'not-a-number',
          'snappedToEdge': true,
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement, isNull);
    });

    test('snappedToEdge sai kiểu (chuỗi) không ném, mặc định false', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 812.0,
          'tolMm': 12.0,
          'snappedToEdge': 'not-a-bool',
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement?.mm, 812);
      expect(s?.measurement?.snappedToEdge, isFalse);
    });

    test('map rỗng trả null, không ném', () {
      expect(ArMeasure.parseSample(const {}), isNull);
    });

    // `.excessiveMotion` và `.insufficientFeatures` đổ chung vào `needsMotion`,
    // nhưng cách gỡ thì NGƯỢC nhau: một cái bảo người dùng chậm lại, cái kia
    // bảo rê máy quanh tìm bề mặt có vân. Không có trường này thì màn không có
    // cách nào nói đúng câu nào — nó phải chọn một câu và sai một nửa số lần.
    test('limitedReason đọc được cả hai lý do', () {
      final fast = ArMeasure.parseSample({
        'status': 'needsMotion',
        'limitedReason': 'excessiveMotion',
      });
      final bare = ArMeasure.parseSample({
        'status': 'needsMotion',
        'limitedReason': 'insufficientFeatures',
      });

      expect(fast?.limitedReason, ArMeasureLimitedReason.excessiveMotion);
      expect(bare?.limitedReason, ArMeasureLimitedReason.insufficientFeatures);
    });

    // Khoá mới KHÔNG được phá tương thích: một bản Swift cũ không gửi nó, và
    // mẫu ấy vẫn phải hợp lệ y như trước.
    test('thiếu limitedReason thì về null, mẫu vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'needsMotion'});

      expect(s?.status, ArMeasureStatus.needsMotion);
      expect(s?.limitedReason, isNull);
    });

    // ARKit có thể thêm lý do mới ở một bản iOS sau. Lý do lạ về `null` chứ
    // KHÔNG được giết cả mẫu — trạng thái vẫn là thứ màn cần nhất.
    test('limitedReason lạ không giết mẫu, chỉ về null', () {
      final s = ArMeasure.parseSample({
        'status': 'needsMotion',
        'limitedReason': 'sao chổi',
      });

      expect(s?.status, ArMeasureStatus.needsMotion);
      expect(s?.limitedReason, isNull);
    });

    // `unsupportedConfiguration` và `sensorUnavailable` là hỏng VĨNH VIỄN.
    // Gộp chúng vào `trackingLost` trần thì màn mời người dùng "rê máy chậm và
    // đều" mãi mãi, cho một phiên không bao giờ chạy lại được.
    test('recoverable false đi kèm lỗi vĩnh viễn', () {
      final s = ArMeasure.parseSample({
        'status': 'trackingLost',
        'recoverable': false,
      });

      expect(s?.status, ArMeasureStatus.trackingLost);
      expect(s?.recoverable, isFalse);
    });

    test('thiếu hoặc sai kiểu recoverable thì mặc định là true', () {
      expect(
        ArMeasure.parseSample({'status': 'trackingLost'})?.recoverable,
        isTrue,
      );
      expect(
        ArMeasure.parseSample({
          'status': 'trackingLost',
          'recoverable': 'not-a-bool',
        })?.recoverable,
        isTrue,
      );
    });

    // Cờ ngắm là thứ DUY NHẤT nói cho người dùng biết cú bấm sắp tới có trúng
    // gì không. Máy thật báo về: bấm "Chấm điểm" chĩa vào màn iPad đen bóng thì
    // KHÔNG có gì xảy ra — không điểm, không thông báo — vì tia trượt thật mà
    // nút thì không có cách nào nói ra trước.
    test('aimLocked đọc được khi tầng nền báo tâm ngắm đã bám', () {
      final s = ArMeasure.parseSample({'status': 'ready', 'aimLocked': true});

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimLocked, isTrue);
    });

    // Tầng nền chỉ gửi khoá này khi TRUE — thiếu nghĩa là chưa bám, đúng cái
    // mặc định an toàn: màn vẽ tâm ngắm rỗng và người dùng còn phải rê tiếp.
    test('thiếu aimLocked thì mặc định false, mẫu vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'ready'});

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimLocked, isFalse);
    });

    test('aimLocked sai kiểu không ném, về false', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'ready',
          'aimLocked': 'not-a-bool',
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimLocked, isFalse);
    });

    // Cờ trúng/trượt gộp hai mức tin cậy rất khác nhau vào một hình tâm ngắm:
    // "nằm trên mặt phẳng ARKit đã xác nhận" và "nằm trên mặt phẳng ARKit vừa
    // đoán ra quanh tia". Người dùng cần thấy khác nhau TRƯỚC cú bấm.
    test('aimTarget đọc được cả BA tầng tia gói bắn ra', () {
      final geometry = ArMeasure.parseSample({
        'status': 'ready',
        'aimLocked': true,
        'aimTarget': 'existingPlaneGeometry',
      });
      final estimated = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'aimLocked': true,
        'aimTarget': 'estimatedPlane',
      });
      // Tầng thứ ba vào từ 0.6.0. Chuỗi đã đọc được từ trước (enum có đủ ba
      // giá trị của `ARRaycastQuery.Target` ngay từ đầu), nhưng tầng nền chưa
      // bao giờ bắn nó ra — nay thì có.
      final infinite = ArMeasure.parseSample({
        'status': 'ready',
        'aimLocked': true,
        'aimTarget': 'existingPlaneInfinite',
        'aimOvershootMm': 47.5,
      });

      expect(geometry?.aimTarget, ArRaycastTarget.existingPlaneGeometry);
      expect(estimated?.aimTarget, ArRaycastTarget.estimatedPlane);
      expect(infinite?.aimTarget, ArRaycastTarget.existingPlaneInfinite);
    });

    /// Cái van của tầng ngoại suy, đo trên tia ĐANG ngắm.
    ///
    /// Không có nó thì tầng ba là đúng thứ mà bản trước cấm: một điểm ở cao độ
    /// mặt bàn, trả về ở chỗ không có mặt bàn, kèm một tâm ngắm khoá chắc.
    test('aimOvershootMm đọc được khi tia đang ở tầng ngoại suy', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'aimLocked': true,
        'aimTarget': 'existingPlaneInfinite',
        'aimOvershootMm': 1840.25,
      });

      expect(s?.aimTarget, ArRaycastTarget.existingPlaneInfinite);
      expect(s?.aimOvershootMm, 1840.25);
    });

    // Hai tầng đầu KHÔNG kèm quãng vượt biên, và `null` ở đó đọc đúng nghĩa:
    // không có gì để vượt, điểm nằm trong biên thật hoặc trên một mặt ước
    // lượng. Bù 0 là nói "đo được, và bằng không" — một khẳng định khác hẳn.
    test('thiếu aimOvershootMm thì về null, mẫu vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({
        'status': 'ready',
        'aimLocked': true,
        'aimTarget': 'existingPlaneGeometry',
      });

      expect(s?.aimTarget, ArRaycastTarget.existingPlaneGeometry);
      expect(s?.aimOvershootMm, isNull);
    });

    test('aimOvershootMm sai kiểu hay không hữu hạn về null, không ném', () {
      late ArMeasureSample? saiKieu;
      late ArMeasureSample? voCuc;
      expect(() {
        saiKieu = ArMeasure.parseSample({
          'status': 'ready',
          'aimTarget': 'existingPlaneInfinite',
          'aimOvershootMm': 'xa-lam',
        });
        voCuc = ArMeasure.parseSample({
          'status': 'ready',
          'aimTarget': 'existingPlaneInfinite',
          'aimOvershootMm': double.infinity,
        });
      }, returnsNormally);

      expect(saiKieu?.status, ArMeasureStatus.ready);
      expect(saiKieu?.aimOvershootMm, isNull);
      // Vô cực và NaN KHÔNG đi tiếp: mọi phép so sánh với NaN đều `false`, nên
      // một ngưỡng "vượt quá ngần này thì đừng chốt cung" lặng lẽ không bao giờ
      // đúng. `null` thì người gọi buộc phải xử lý.
      expect(voCuc?.aimOvershootMm, isNull);
    });

    // Thiếu khoá = tia không trúng gì, và đó cũng là đường của một bản Swift cũ
    // hơn tầng này. Hai đường cùng đổ về `null` có chủ đích: cả hai đều nghĩa
    // là "không có tầng nào để bày", và màn phải vẽ ra cùng một thứ.
    test('thiếu aimTarget thì về null, mẫu vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'ready', 'aimLocked': true});

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimLocked, isTrue);
      expect(s?.aimTarget, isNull);
    });

    test('aimTarget lạ hay sai kiểu không ném, về null', () {
      late ArMeasureSample? la;
      late ArMeasureSample? saiKieu;
      expect(() {
        la = ArMeasure.parseSample({
          'status': 'ready',
          'aimTarget': 'mot-tang-moi-cua-iOS-sau',
        });
        saiKieu = ArMeasure.parseSample({'status': 'ready', 'aimTarget': 7});
      }, returnsNormally);

      expect(la?.status, ArMeasureStatus.ready);
      expect(la?.aimTarget, isNull);
      expect(saiKieu?.aimTarget, isNull);
    });

    /// Góc tia của tia ĐANG ngắm — trước cú bấm, không phải sau. Vào từ 0.7.0.
    ///
    /// Vì sao nó phải có mặt: số hạng dung sai mà app dựng lên là
    /// `ε = d · Δu / (fx · sin θ)`, với θ là góc giữa tia và MẶT phẳng. `sin θ`
    /// nằm ở MẪU SỐ, nên ngắm sượt làm dung sai nở ra rất nhanh — ở 0,6 m với
    /// lệch 2 điểm ảnh: 0,83 mm ở 90°, 4,00 mm ở 12°, 9,55 mm ở 5°. Đó đúng là
    /// tư thế người ta cầm máy khi đo mép bàn: cúi thấp, ngắm sượt.
    ///
    /// Gói đã bắn góc ấy cho điểm ĐÃ chấm ([ArPointDiagnostics.rayAngleDeg]) từ
    /// trước. Một cảnh báo "ngắm quá sượt" dựng trên con số đó là một cảnh báo
    /// tới SAU khi người dùng đã bấm — nó không cứu được cú bấm nào.
    test(
      'aimRayAngleDeg đọc được ở CẢ BA tầng, không riêng tầng ngoại suy',
      () {
        final geometry = ArMeasure.parseSample({
          'status': 'ready',
          'aimLocked': true,
          'aimTarget': 'existingPlaneGeometry',
          'aimRayAngleDeg': 71.5,
        });
        final estimated = ArMeasure.parseSample({
          'status': 'firstPointPlaced',
          'aimLocked': true,
          'aimTarget': 'estimatedPlane',
          'aimRayAngleDeg': 12.0,
        });
        final infinite = ArMeasure.parseSample({
          'status': 'ready',
          'aimLocked': true,
          'aimTarget': 'existingPlaneInfinite',
          'aimOvershootMm': 47.5,
          'aimRayAngleDeg': 4.75,
        });

        expect(geometry?.aimRayAngleDeg, 71.5);
        expect(estimated?.aimRayAngleDeg, 12.0);
        expect(infinite?.aimRayAngleDeg, 4.75);
      },
    );

    /// Bất biến của van GIỮ NGUYÊN, và góc tia cố ý KHÔNG theo nó.
    ///
    /// `aimOvershootMm != null` vẫn tương đương `aimTarget ==
    /// existingPlaneInfinite` — nó nói về một cái biên bị vượt, và hai tầng kia
    /// không vượt biên nào. Góc tia thì có nghĩa ở MỌI tầng: một tia sượt 4° vào
    /// một mặt phẳng ARKit đã xác nhận vẫn là một tia sượt 4°.
    ///
    /// Gộp hai thứ vào chung một lối gác là mất cảnh báo sượt ở đúng cái tầng
    /// người ta tin nhất.
    test(
      'góc tia có ở tầng KHÔNG có van, và van có ở tầng không nói gì thêm',
      () {
        final geometry = ArMeasure.parseSample({
          'status': 'ready',
          'aimTarget': 'existingPlaneGeometry',
          'aimRayAngleDeg': 6.25,
        });

        expect(geometry?.aimRayAngleDeg, 6.25);
        expect(
          geometry?.aimOvershootMm,
          isNull,
          reason:
              'Tầng hình học không vượt biên nào. Bù 0 ở đây là nói "đã đo, và '
              'bằng không" — một khẳng định khác hẳn.',
        );
      },
    );

    // Không trúng gì thì không có mặt phẳng nào để đo góc so với nó. `null`, và
    // `null` cũng là đường của một bản Swift cũ hơn trường này — cùng một chỗ
    // rơi, cùng một cách vẽ.
    test('không trúng gì thì aimRayAngleDeg về null, mẫu vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'ready'});

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimTarget, isNull);
      expect(s?.aimRayAngleDeg, isNull);
    });

    test('aimRayAngleDeg sai kiểu hay không hữu hạn về null, không ném', () {
      late ArMeasureSample? saiKieu;
      late ArMeasureSample? khongPhaiSo;
      expect(() {
        saiKieu = ArMeasure.parseSample({
          'status': 'ready',
          'aimTarget': 'estimatedPlane',
          'aimRayAngleDeg': 'suot-lam',
        });
        khongPhaiSo = ArMeasure.parseSample({
          'status': 'ready',
          'aimTarget': 'estimatedPlane',
          'aimRayAngleDeg': double.nan,
        });
      }, returnsNormally);

      expect(saiKieu?.aimRayAngleDeg, isNull);
      // NaN KHÔNG đi tiếp, và đây là chỗ trường này khác hẳn
      // [ArPointDiagnostics.rayAngleDeg] của các bản trước: con số ấy chỉ để
      // ĐỌC, con số này nằm ở MẪU SỐ của một phép chia. `sin(NaN)` là `NaN`,
      // `ε` thành `NaN`, và mọi phép so sánh với `NaN` đều `false` — nên ngưỡng
      // "sượt quá thì đừng chốt" lặng lẽ không bao giờ đúng.
      expect(khongPhaiSo?.aimRayAngleDeg, isNull);
    });

    /// Định danh mặt phẳng của tia ĐANG ngắm.
    ///
    /// Vì sao trường này tồn tại, và vì sao KHÔNG suy được từ những trường đã
    /// có: hai cảnh hỏng trên máy thật lọt qua sạch mọi tín hiệu cũ.
    ///
    /// * Điểm cuối lơ lửng trên tường nằm trên mặt phẳng MẶT BÀN kéo dài gần
    ///   hai mét, nên [ArPointDiagnostics.planeAlignment] của nó vẫn
    ///   `horizontal` y hệt điểm đầu.
    /// * Điểm bị bắt xuống dưới chân bàn rơi lên mặt SÀN, vì lúc ấy mặt bàn
    ///   chưa được dò. Sàn và mặt bàn ĐỀU ngang.
    ///
    /// Phương giống nhau, tầng giống nhau, bề rộng không nói được gì. Mọi phép
    /// suy từ chúng trả lời "cùng mặt phẳng" ở đúng hai cảnh nó sinh ra để bắt,
    /// nên phải có một định danh THẬT.
    test('aimPlaneId đọc được ở cả tầng hình học lẫn tầng ngoại suy', () {
      final geometry = ArMeasure.parseSample({
        'status': 'ready',
        'aimLocked': true,
        'aimTarget': 'existingPlaneGeometry',
        'aimPlaneId': 'B3F1C0DE-4A2E-4C1B-9E77-000000000001',
      });
      final infinite = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'aimLocked': true,
        'aimTarget': 'existingPlaneInfinite',
        'aimOvershootMm': 1946.0,
        'aimPlaneId': 'B3F1C0DE-4A2E-4C1B-9E77-000000000001',
      });

      expect(geometry?.aimPlaneId, 'B3F1C0DE-4A2E-4C1B-9E77-000000000001');
      // Tầng ngoại suy KÉO DÀI một mặt phẳng đã dò, nên nó vẫn có mặt phẳng ấy
      // để mà khai tên — và đây đúng là cảnh hỏng thứ nhất: cùng mặt bàn, kéo
      // dài gần hai mét ra chỗ không có gì.
      expect(infinite?.aimPlaneId, 'B3F1C0DE-4A2E-4C1B-9E77-000000000001');
    });

    /// `null` ở tầng ước lượng là một SỰ THẬT, không phải một chỗ thiếu.
    ///
    /// `.estimatedPlane` không có `ARPlaneAnchor` nào — ARKit khớp một mặt
    /// phẳng từ hình học quanh tia và không neo nó vào đâu cả. App phải phân
    /// biệt được "không có mặt phẳng" với "có mà khác nhau", nên bù một giá trị
    /// giả ở đây là dựng ra đúng cái kết luận sai mà trường này sinh ra để chặn.
    test('tầng ước lượng không có mặt phẳng nào, aimPlaneId về null', () {
      final s = ArMeasure.parseSample({
        'status': 'ready',
        'aimLocked': true,
        'aimTarget': 'estimatedPlane',
        'aimRayAngleDeg': 12.0,
      });

      expect(s?.aimTarget, ArRaycastTarget.estimatedPlane);
      expect(s?.aimPlaneId, isNull);
    });

    test('không trúng gì thì aimPlaneId về null, mẫu vẫn hợp lệ', () {
      final s = ArMeasure.parseSample({'status': 'ready'});

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.aimTarget, isNull);
      expect(s?.aimPlaneId, isNull);
    });

    /// Chuỗi RỖNG bị loại, và đó không phải một ca kiểu cho đủ bộ.
    ///
    /// Trường này chỉ dùng để SO SÁNH BẰNG NHAU, nên hai chuỗi rỗng đọc ra
    /// "cùng một mặt phẳng" — đúng cái kết luận sai mà cả việc này sinh ra để
    /// chặn, và nó sai theo chiều nguy hiểm: im lặng, và về phía "yên tâm".
    test('aimPlaneId sai kiểu hay rỗng về null, không ném', () {
      late ArMeasureSample? saiKieu;
      late ArMeasureSample? rong;
      expect(() {
        saiKieu = ArMeasure.parseSample({
          'status': 'ready',
          'aimTarget': 'existingPlaneGeometry',
          'aimPlaneId': 42,
        });
        rong = ArMeasure.parseSample({
          'status': 'ready',
          'aimTarget': 'existingPlaneGeometry',
          'aimPlaneId': '',
        });
      }, returnsNormally);

      expect(saiKieu?.aimPlaneId, isNull);
      expect(
        rong?.aimPlaneId,
        isNull,
        reason:
            'Hai chuỗi rỗng bằng nhau, nên một chuỗi rỗng đi tiếp là hai mặt '
            'phẳng bất kỳ đọc ra "cùng một mặt phẳng".',
      );
    });
  });

  /// Chẩn đoán: ảnh chụp của ĐIỀU KIỆN mỗi điểm được chấm.
  ///
  /// Cả nhóm này neo vào một chuyện đã trả giá: một cuộc điều tra mười sáu tác
  /// nhân bác sạch mọi giả thuyết về sai lệch số đo, và bác vì cùng một lý do
  /// ở mọi giả thuyết — mẫu bắn lên Dart không mang một mẩu nào về việc phép đo
  /// ĐÃ diễn ra thế nào, nên mọi lời giải đều khớp mọi số đo và không lời nào
  /// kiểm được.
  ///
  /// Luật của cả nhóm: **không đường nào được ném, không đường nào được giết
  /// mẫu**. Chẩn đoán là thứ đi kèm; một khoá hỏng ở đây mà làm mất cả mẫu thì
  /// tầng chẩn đoán tự nó thành một lỗi sản phẩm.
  group('parseSample · chẩn đoán', () {
    Map<Object?, Object?> diemDay({String target = 'existingPlaneGeometry'}) =>
        {
          'target': target,
          'tracking': 'normal',
          'sessionAgeMs': 4210,
          'cameraDistanceMm': 612.5,
          'rayAngleDeg': 63.25,
          'planeAlignment': 'horizontal',
          'planeWidthMm': 1200.0,
          'planeHeightMm': 800.0,
        };

    test('hai điểm, đủ trường, đúng THỨ TỰ chấm', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
        'snappedToEdge': false,
        'diagnostics': {
          'points': [diemDay(), diemDay(target: 'estimatedPlane')],
        },
      });

      final points = s?.diagnostics?.points;
      expect(points, hasLength(2));
      expect(points?[0].target, ArRaycastTarget.existingPlaneGeometry);
      expect(points?[0].tracking, ArTrackingSnapshot.normal);
      expect(points?[0].sessionAgeMs, 4210);
      expect(points?[0].cameraDistanceMm, 612.5);
      expect(points?[0].rayAngleDeg, 63.25);
      expect(points?[0].planeAlignment, ArPlaneAlignment.horizontal);
      expect(points?[0].planeWidthMm, 1200.0);
      expect(points?[0].planeHeightMm, 800.0);
      // Điểm thứ hai KHÁC điểm đầu ở đúng tầng trúng. Hai điểm giống hệt nhau
      // thì ca kiểm không phân biệt được "đọc đúng thứ tự" với "đọc điểm đầu
      // hai lần".
      expect(points?[1].target, ArRaycastTarget.estimatedPlane);
    });

    test('mới một điểm thì chẩn đoán cũng chỉ có một', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [diemDay()],
        },
      });

      expect(s?.diagnostics?.points, hasLength(1));
    });

    // Bản Swift cũ hơn tầng chẩn đoán không gửi khoá này. `null` chứ không
    // phải một đối tượng rỗng: rỗng đọc ra "đã đo và không có gì", còn `null`
    // đọc đúng nghĩa "bản nền này không nói".
    test('thiếu khoá thì diagnostics về null, mẫu vẫn sống', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
      });

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement?.mm, 812);
      expect(s?.diagnostics, isNull);
    });

    test('danh sách rỗng cũng về null, không phải một danh sách rỗng', () {
      final s = ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {'points': <Object?>[]},
      });

      expect(s?.diagnostics, isNull);
    });

    // Khuôn hình là chuyện của cả PHIÊN, không phải của một điểm — và nó phải
    // đọc được TRƯỚC khi có điểm nào, vì đó đúng là lúc người ta cần biết vì
    // sao chưa chấm nổi điểm nào.
    test('khuôn hình đang chạy đọc được khi chưa có điểm nào', () {
      final s = ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {
          'video': {'width': 1920, 'height': 1440, 'fps': 60},
        },
      });

      expect(s?.diagnostics, isNotNull);
      expect(s?.diagnostics?.points, isEmpty);
      expect(s?.diagnostics?.video?.width, 1920);
      expect(s?.diagnostics?.video?.height, 1440);
      expect(s?.diagnostics?.video?.fps, 60);
    });

    test('khuôn hình đi cùng chẩn đoán từng điểm, không loại nhau', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [diemDay()],
          'video': {'width': 3840, 'height': 2160, 'fps': 30},
        },
      });

      expect(s?.diagnostics?.points, hasLength(1));
      expect(s?.diagnostics?.video?.width, 3840);
      expect(s?.diagnostics?.video?.fps, 30);
    });

    test('thiếu khuôn hình thì về null, chẩn đoán điểm vẫn sống', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [diemDay()],
        },
      });

      expect(s?.diagnostics?.points, hasLength(1));
      expect(s?.diagnostics?.video, isNull);
    });

    test('khuôn hình sai kiểu không ném, ba ô về null', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'ready',
          'diagnostics': {
            'video': {
              'width': 'rong',
              'height': null,
              'fps': <int>[60],
            },
          },
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.diagnostics?.video?.width, isNull);
      expect(s?.diagnostics?.video?.height, isNull);
      expect(s?.diagnostics?.video?.fps, isNull);
    });

    // Đếm điểm đặc trưng: PHÉP ĐO của 0.5.0, xem [ArFeatureCensus]. Cùng lối
    // với khuôn hình — chuyện của KHUNG HÌNH chứ không của một điểm, và nó
    // phải đọc được lúc chưa chấm nổi điểm nào, vì đó đúng là lúc câu hỏi nó
    // sinh ra để trả lời đang được hỏi.
    test('đếm vân đọc được khi chưa có điểm nào và chưa có khuôn hình', () {
      final s = ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {
          'features': {'total': 312, 'nearRay': 14},
        },
      });

      expect(s?.diagnostics, isNotNull);
      expect(s?.diagnostics?.points, isEmpty);
      expect(s?.diagnostics?.video, isNull);
      expect(s?.diagnostics?.features?.total, 312);
      expect(s?.diagnostics?.features?.nearRay, 14);
    });

    test('đếm vân đi cùng khuôn hình và chẩn đoán điểm, không loại nhau', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [diemDay()],
          'video': {'width': 3840, 'height': 2160, 'fps': 30},
          'features': {'total': 980, 'nearRay': 0},
        },
      });

      expect(s?.diagnostics?.points, hasLength(1));
      expect(s?.diagnostics?.video?.fps, 30);
      expect(s?.diagnostics?.features?.total, 980);
      expect(s?.diagnostics?.features?.nearRay, 0);
    });

    // `0` và `null` KHÔNG được đổ chung. `0` là "ARKit có đám mây và đám mây
    // rỗng" — một sự thật, và là sự thật quyết định phép đo này. `null` là
    // "bản nền này không nói". Gộp hai thứ là xoá đúng câu trả lời.
    test('không có khối vân thì về null, hai khoá kia vẫn sống', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [diemDay()],
          'video': {'width': 1920, 'height': 1440, 'fps': 60},
        },
      });

      expect(s?.diagnostics?.points, hasLength(1));
      expect(s?.diagnostics?.video, isNotNull);
      expect(s?.diagnostics?.features, isNull);
    });

    test('đếm vân sai kiểu không ném, hai ô về null', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'ready',
          'diagnostics': {
            'features': {'total': 'nhieu', 'nearRay': null},
          },
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.ready);
      expect(s?.diagnostics?.features, isNotNull);
      expect(s?.diagnostics?.features?.total, isNull);
      expect(s?.diagnostics?.features?.nearRay, isNull);
    });

    /// Tiêu cự tính bằng ĐIỂM ẢNH — `ARFrame.camera.intrinsics[0][0]`. Từ 0.7.0.
    ///
    /// Mẫu số thứ hai của `ε = d · Δu / (fx · sin θ)`. Không có nó thì app
    /// không tính nổi một milimét dung sai nào, và cách duy nhất còn lại là ước
    /// bừa một con số.
    test('tiêu cự đọc được khi chưa có điểm nào', () {
      final s = ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {
          'camera': {'fx': 2883.6, 'width': 3840, 'height': 2160},
        },
      });

      expect(s?.diagnostics, isNotNull);
      expect(s?.diagnostics?.points, isEmpty);
      expect(s?.diagnostics?.camera?.fx, 2883.6);
      expect(s?.diagnostics?.camera?.width, 3840);
      expect(s?.diagnostics?.camera?.height, 2160);
    });

    /// **Ca này canh một lỗi VÔ HÌNH: ghim `fx` thành một hằng số.**
    ///
    /// Con số 1442 mà mọi bài viết về máy iOS dẫn ra là tiêu cự của khuôn
    /// 1920×1440. Gói đang chạy khuôn to nhất máy hỗ trợ — 3840×2160 trên máy
    /// thật — và `fx` co giãn theo bề rộng khuôn, nên nó gần gấp đôi. Ghim cứng
    /// thì mọi con số dung sai lệch đúng một hệ số 2, và cả hai giá trị đều nằm
    /// gọn trong khoảng "trông hợp lý": vài milimét.
    ///
    /// Chuyện khuôn hình đổi không phải một giả định xa xôi — khối chọn khuôn
    /// trong gói là một PHÉP THỬ chưa nghiệm thu (0.4.0), và chú thích của
    /// chính nó nói **"nhịp khung tụt mà thời gian chờ không giảm thì bỏ hẳn
    /// đoạn này"**. Ngày ai đó bỏ nó, `fx` phải tự đổi theo.
    test('fx đi CÙNG khuôn hình đã đo nó, và đổi theo khuôn ấy', () {
      final hd = ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {
          'camera': {'fx': 1442.0, 'width': 1920, 'height': 1440},
        },
      });
      final uhd = ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {
          'camera': {'fx': 2884.0, 'width': 3840, 'height': 2160},
        },
      });

      expect(hd?.diagnostics?.camera?.fx, 1442.0);
      expect(hd?.diagnostics?.camera?.width, 1920);
      expect(uhd?.diagnostics?.camera?.fx, 2884.0);
      expect(uhd?.diagnostics?.camera?.width, 3840);
    });

    /// Vì sao `fx` KHÔNG nằm chung khối với [ArVideoFormat].
    ///
    /// `video` là ảnh chụp **lúc `run`**, đọc từ `config.videoFormat` — khuôn
    /// được CẤU HÌNH. `camera` là khung hình vừa tới — khuôn đang CHẠY, và là
    /// hệ toạ độ điểm ảnh mà `fx` được biểu diễn trên đó. Hai thứ lệch nhau
    /// được thật: ARKit không hứa giao đúng khuôn đã xin, và `fx` còn nhúc nhích
    /// theo lấy nét tự động (gói bật `isAutoFocusEnabled`) trong khi `video`
    /// đứng im cả phiên.
    ///
    /// Trộn hai khối là đọc `fx` trên một bề rộng không phải bề rộng của nó, và
    /// con số sai ra được vẫn là một con số milimét trông bình thường.
    test('khối camera nói khuôn hình của CHÍNH nó, không mượn của video', () {
      final s = ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {
          'video': {'width': 3840, 'height': 2160, 'fps': 30},
          'camera': {'fx': 1442.0, 'width': 1920, 'height': 1440},
        },
      });

      expect(s?.diagnostics?.video?.width, 3840);
      expect(s?.diagnostics?.video?.height, 2160);
      expect(s?.diagnostics?.camera?.width, 1920);
      expect(s?.diagnostics?.camera?.height, 1440);
      expect(s?.diagnostics?.camera?.fx, 1442.0);
    });

    test(
      'tiêu cự đi cùng khuôn hình, đếm vân và chẩn đoán điểm, không loại nhau',
      () {
        final s = ArMeasure.parseSample({
          'status': 'firstPointPlaced',
          'diagnostics': {
            'points': [diemDay()],
            'video': {'width': 3840, 'height': 2160, 'fps': 30},
            'features': {'total': 26, 'nearRay': 1},
            'camera': {'fx': 2883.6, 'width': 3840, 'height': 2160},
          },
        });

        expect(s?.diagnostics?.points, hasLength(1));
        expect(s?.diagnostics?.video?.fps, 30);
        expect(s?.diagnostics?.features?.nearRay, 1);
        expect(s?.diagnostics?.camera?.fx, 2883.6);
      },
    );

    test('không có khối camera thì về null, ba khoá kia vẫn sống', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [diemDay()],
          'video': {'width': 1920, 'height': 1440, 'fps': 60},
          'features': {'total': 26, 'nearRay': 1},
        },
      });

      expect(s?.diagnostics?.points, hasLength(1));
      expect(s?.diagnostics?.video, isNotNull);
      expect(s?.diagnostics?.features, isNotNull);
      expect(s?.diagnostics?.camera, isNull);
    });

    /// `fx` là MẪU SỐ, nên nó qua cùng một cửa với cái van chứ không qua cửa
    /// của một con số để đọc.
    ///
    /// `0` không phải "một thấu kính có tiêu cự bằng không" — không có thấu
    /// kính nào như thế. Cho `0` đi tiếp là `ε` thành vô cực; cho `NaN` đi tiếp
    /// là mọi phép so sánh với `ε` đều `false`, và ngưỡng cảnh báo lặng lẽ
    /// không bao giờ đúng. Cả hai đều là cái van câm mà không ai biết.
    test('fx không hữu hạn hoặc không dương về null, không ném', () {
      late ArMeasureSample? khong;
      late ArMeasureSample? am;
      late ArMeasureSample? voCuc;
      late ArMeasureSample? saiKieu;
      expect(() {
        khong = ArMeasure.parseSample({
          'status': 'ready',
          'diagnostics': {
            'camera': {'fx': 0, 'width': 3840, 'height': 2160},
          },
        });
        am = ArMeasure.parseSample({
          'status': 'ready',
          'diagnostics': {
            'camera': {'fx': -1442.0, 'width': 3840, 'height': 2160},
          },
        });
        voCuc = ArMeasure.parseSample({
          'status': 'ready',
          'diagnostics': {
            'camera': {'fx': double.infinity, 'width': 3840, 'height': 2160},
          },
        });
        saiKieu = ArMeasure.parseSample({
          'status': 'ready',
          'diagnostics': {
            'camera': {'fx': 'dai', 'width': 'rong', 'height': null},
          },
        });
      }, returnsNormally);

      expect(khong?.diagnostics?.camera?.fx, isNull);
      expect(am?.diagnostics?.camera?.fx, isNull);
      expect(voCuc?.diagnostics?.camera?.fx, isNull);
      expect(saiKieu?.diagnostics?.camera?.fx, isNull);
      // Khối vẫn sống với hai ô còn lại: một `fx` hỏng không được kéo theo bề
      // rộng khuôn, vì bề rộng ấy còn nói được một chuyện khác.
      expect(khong?.diagnostics?.camera?.width, 3840);
      expect(saiKieu?.diagnostics?.camera?.width, isNull);
      expect(saiKieu?.diagnostics?.camera?.height, isNull);
    });

    test('mặt ước lượng: không có mặt phẳng nào, bốn khoá mp về null', () {
      final s = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'diagnostics': {
          'points': [
            {
              'target': 'estimatedPlane',
              'tracking': 'limitedInsufficientFeatures',
              'sessionAgeMs': 900,
              'cameraDistanceMm': 310.0,
              'rayAngleDeg': 12.0,
            },
          ],
        },
      });

      final p = s?.diagnostics?.points.single;
      expect(p?.target, ArRaycastTarget.estimatedPlane);
      expect(p?.tracking, ArTrackingSnapshot.limitedInsufficientFeatures);
      expect(p?.planeAlignment, isNull);
      expect(p?.planeWidthMm, isNull);
      expect(p?.planeHeightMm, isNull);
      expect(
        p?.planeId,
        isNull,
        reason:
            'Tầng ước lượng không có `ARPlaneAnchor` nào để mà khai tên. `null` '
            'ở đây là SỰ THẬT — "không có mặt phẳng" — và nó phải phân biệt '
            'được với "có mặt phẳng, và là một mặt phẳng khác".',
      );
      expect(
        p?.overshootMm,
        isNull,
        reason:
            'Mặt ước lượng không có biên nào để vượt. Một con số ở đây đọc ra '
            '"đã đo quãng vượt biên và nó bằng chừng ấy" — một khẳng định không '
            'có phép tính nào đứng sau.',
      );
    });

    /// Lai lịch của một điểm ĐÃ chấm: nó là điểm quan sát được hay điểm suy ra.
    ///
    /// Đây là nửa còn lại của cái van. Tia đang ngắm nói về cú bấm SẮP tới;
    /// khối này nói về hai cú bấm ĐÃ xảy ra — và một số đo lưu lại rồi đọc sau
    /// một tuần mà trông y hệt một số đo trên mặt phẳng đã xác nhận thì cái van
    /// chỉ hoãn được lỗi đúng một tuần.
    test('điểm ngoại suy mang theo quãng vượt biên của chính nó', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
        'diagnostics': {
          'points': [
            {'target': 'existingPlaneGeometry', 'planeWidthMm': 1200.0},
            {'target': 'existingPlaneInfinite', 'overshootMm': 63.5},
          ],
        },
      });

      final points = s?.diagnostics?.points;
      expect(points?[0].target, ArRaycastTarget.existingPlaneGeometry);
      expect(
        points?[0].overshootMm,
        isNull,
        reason: 'điểm nằm TRONG biên thì không có quãng vượt biên nào',
      );
      expect(points?[1].target, ArRaycastTarget.existingPlaneInfinite);
      expect(points?[1].overshootMm, 63.5);
    });

    /// Định danh mặt phẳng của mỗi điểm ĐÃ chấm.
    ///
    /// Cả cụm này canh đúng một câu hỏi mà app không trả lời nổi bằng chín
    /// trường cũ: **hai đầu mút có nằm trên cùng một mặt phẳng không.**
    ///
    /// Hai cảnh hỏng trên máy thật, và cả hai lọt qua sạch:
    ///
    /// 1. Điểm cuối lơ lửng trên tường nằm trên mặt phẳng MẶT BÀN kéo dài gần
    ///    hai mét (`overshootMm` +1946) — `planeAlignment` vẫn `horizontal` y
    ///    hệt điểm đầu.
    /// 2. Điểm bị bắt xuống dưới chân bàn rơi lên mặt SÀN, vì lúc ấy mặt bàn
    ///    chưa được dò. Sàn và mặt bàn ĐỀU ngang.
    ///
    /// Gói KHÔNG kết luận "cùng hay khác" — cùng một ranh giới với
    /// [ArPointDiagnostics.overshootMm]. Nó trả định danh; app so.
    test('hai điểm trên HAI mặt phẳng khác nhau ra hai định danh khác nhau', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
        'diagnostics': {
          'points': [
            {
              'target': 'existingPlaneGeometry',
              'planeAlignment': 'horizontal',
              'planeId': 'B3F1C0DE-4A2E-4C1B-9E77-000000000001',
            },
            {
              'target': 'existingPlaneGeometry',
              'planeAlignment': 'horizontal',
              'planeId': 'B3F1C0DE-4A2E-4C1B-9E77-000000000002',
            },
          ],
        },
      });

      final points = s?.diagnostics?.points;
      expect(points, hasLength(2));
      // Cảnh hỏng số 2, dựng lại nguyên vẹn: mặt SÀN và mặt BÀN, cả hai đều
      // `horizontal`, cả hai đều ở tầng hình học đã xác nhận. Thứ DUY NHẤT
      // phân biệt chúng là hai định danh này.
      expect(points?[0].planeAlignment, points?[1].planeAlignment);
      expect(points?[0].target, points?[1].target);
      expect(
        points?[0].planeId,
        isNot(points?[1].planeId),
        reason:
            'Hai mặt phẳng khác nhau mà ra cùng một định danh thì app kết luận '
            '"cùng mặt phẳng" ở đúng cảnh trường này sinh ra để bắt.',
      );
    });

    /// Nửa còn lại, và nó KHÔNG hiển nhiên: đây là chỗ một phép "rút gọn" cẩu
    /// thả (lấy tám ký tự đầu, băm xuống một `int`) làm hai mặt phẳng khác nhau
    /// đụng độ cùng một giá trị. Hai `UUID` dưới đây khác nhau ở ĐUÔI, và hai
    /// cái nữa khác nhau ở ĐẦU — cắt bên nào cũng đỏ.
    test('định danh KHÔNG bị rút gọn: khác đuôi hay khác đầu vẫn khác nhau', () {
      final khacDuoi = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 400.0,
        'tolMm': 8.0,
        'diagnostics': {
          'points': [
            {'planeId': '1A2B3C4D-5E6F-4A8B-9C0D-E1F2A3B4C5D6'},
            {'planeId': '1A2B3C4D-5E6F-4A8B-9C0D-E1F2A3B4C5D7'},
          ],
        },
      });
      final khacDau = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 400.0,
        'tolMm': 8.0,
        'diagnostics': {
          'points': [
            {'planeId': '1A2B3C4D-5E6F-4A8B-9C0D-E1F2A3B4C5D6'},
            {'planeId': '2A2B3C4D-5E6F-4A8B-9C0D-E1F2A3B4C5D6'},
          ],
        },
      });

      expect(
        khacDuoi?.diagnostics?.points[0].planeId,
        isNot(khacDuoi?.diagnostics?.points[1].planeId),
        reason: 'cắt đuôi (`prefix(8)`) làm hai mặt phẳng này bằng nhau',
      );
      expect(
        khacDau?.diagnostics?.points[0].planeId,
        isNot(khacDau?.diagnostics?.points[1].planeId),
        reason: 'cắt đầu (`suffix(8)`) làm hai mặt phẳng này bằng nhau',
      );
    });

    test('hai điểm trên CÙNG một mặt phẳng ra CÙNG một định danh', () {
      const banId = 'B3F1C0DE-4A2E-4C1B-9E77-000000000001';
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
        'diagnostics': {
          'points': [
            {'target': 'existingPlaneGeometry', 'planeId': banId},
            // Đầu kia đã ra ngoài biên mặt bàn — TẦNG khác, mặt phẳng thì vẫn
            // là một. Định danh không được đổi theo tầng: nếu nó đổi thì cảnh
            // hỏng số 1 (mặt bàn kéo dài gần hai mét) đọc ra "khác mặt phẳng",
            // tức là đúng kết luận nhưng vì một lý do bịa, và cùng cái mã ấy
            // sẽ nói dối ở cảnh mép bàn thật.
            {
              'target': 'existingPlaneInfinite',
              'overshootMm': 1946.0,
              'planeId': banId,
            },
          ],
        },
      });

      final points = s?.diagnostics?.points;
      expect(points?[0].planeId, banId);
      expect(points?[1].planeId, banId);
      expect(points?[0].planeId, points?[1].planeId);
    });

    /// Cảnh GỘP mặt phẳng, và hành vi đã chọn cho nó.
    ///
    /// ARKit gộp hai `ARPlaneAnchor` thành một: anchor bị nuốt đi qua
    /// `didRemove`, anchor sống sót lớn ra. Một định danh lưu từ lúc chấm có
    /// thể trỏ vào một mặt phẳng không còn tồn tại.
    ///
    /// **Gói để NGUYÊN.** Trường này là định danh **lúc chấm**, và nó không bao
    /// giờ bị viết lại — lý do đầy đủ nằm ở [ArPointDiagnostics.planeId], gọn
    /// lại là: ARKit không nói mặt phẳng bị nuốt đã nhập vào mặt phẳng NÀO, nên
    /// đuổi theo lượt gộp là đoán, và một cú đoán sai in ra đúng chữ "cùng mặt
    /// phẳng" mà cả việc này sinh ra để chặn.
    ///
    /// Ca này dựng lại đúng cảnh ấy: mặt bàn vừa được dò xong và nuốt mảnh gần,
    /// nên tia đang ngắm khai mặt phẳng MỚI trong khi điểm đã chấm vẫn khai mặt
    /// phẳng CŨ. Gói bày cả hai ra và không hoà giải.
    test('lượt GỘP mặt phẳng không viết lại định danh của điểm đã chấm', () {
      const manhGan = 'B3F1C0DE-4A2E-4C1B-9E77-000000000001';
      const banGopXong = 'B3F1C0DE-4A2E-4C1B-9E77-00000000000F';

      final truocGop = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'aimTarget': 'existingPlaneGeometry',
        'aimPlaneId': manhGan,
        'diagnostics': {
          'points': [
            {'target': 'existingPlaneGeometry', 'planeId': manhGan},
          ],
        },
      });
      final sauGop = ArMeasure.parseSample({
        'status': 'firstPointPlaced',
        'aimTarget': 'existingPlaneGeometry',
        'aimPlaneId': banGopXong,
        'diagnostics': {
          'points': [
            {'target': 'existingPlaneGeometry', 'planeId': manhGan},
          ],
        },
      });

      expect(truocGop?.aimPlaneId, manhGan);
      expect(
        sauGop?.diagnostics?.points.single.planeId,
        manhGan,
        reason:
            'Định danh của một điểm đã chấm là định danh LÚC CHẤM. Viết lại nó '
            'theo lượt gộp đòi một phép đoán mà ARKit không cung cấp dữ liệu để '
            'làm, và cú đoán sai in ra đúng chữ "cùng mặt phẳng".',
      );
      expect(
        sauGop?.aimPlaneId,
        banGopXong,
        reason:
            'Tia ĐANG ngắm luôn khai mặt phẳng của lượt bắn NÀY. Nó không bị '
            'kéo về theo điểm đã chấm — hai trường nói về hai khoảnh khắc.',
      );
      expect(
        sauGop?.aimPlaneId,
        isNot(sauGop?.diagnostics?.points.single.planeId),
        reason:
            'Gói bày ra hai định danh khác nhau và KHÔNG hoà giải chúng. Sau '
            'một lượt gộp, "khác nhau" có thể là báo động nhầm — chiều sai an '
            'toàn, vì app còn thấy được. Chiều kia im lặng.',
      );
    });

    /// Dời một đầu mút SANG MỘT MẶT PHẲNG KHÁC, đọc trên dây.
    ///
    /// Cảnh dời trong CÙNG một mặt phẳng không phân biệt được hai cách cài —
    /// giữ lai lịch cũ và ghi lai lịch mới cho ra cùng một khối chẩn đoán — nên
    /// nó là một ca mù. Cảnh dưới đây đổi cả ba thứ cùng lúc: định danh mặt
    /// phẳng, TẦNG tia, và cái van đi kèm tầng ấy.
    test('điểm vừa dời khai lai lịch MỚI, và điểm kia không đổi gì', () {
      const banGoc = 'B3F1C0DE-4A2E-4C1B-9E77-0000000000A1';
      const tuong = 'B3F1C0DE-4A2E-4C1B-9E77-0000000000B2';

      Map<Object?, Object?> mau(Map<Object?, Object?> diemDuoc) => {
        'status': 'measured',
        'mm': 812.0,
        'tolMm': 12.0,
        'diagnostics': {
          'points': [
            {
              'target': 'existingPlaneGeometry',
              'tracking': 'normal',
              'sessionAgeMs': 4210,
              'cameraDistanceMm': 612.5,
              'rayAngleDeg': 63.25,
              'planeId': banGoc,
              'planeAlignment': 'horizontal',
            },
            diemDuoc,
          ],
        },
      };

      final truocDoi = ArMeasure.parseSample(
        mau({
          'target': 'existingPlaneGeometry',
          'tracking': 'normal',
          'sessionAgeMs': 4380,
          'cameraDistanceMm': 640.0,
          'rayAngleDeg': 58.0,
          'planeId': banGoc,
          'planeAlignment': 'horizontal',
        }),
      );
      final sauDoi = ArMeasure.parseSample(
        mau({
          'target': 'existingPlaneInfinite',
          'tracking': 'limitedExcessiveMotion',
          'sessionAgeMs': 9120,
          'cameraDistanceMm': 1810.0,
          'rayAngleDeg': 11.5,
          'planeId': tuong,
          'planeAlignment': 'vertical',
          'overshootMm': 1946.0,
        }),
      );

      final cu = truocDoi?.diagnostics?.points[1];
      final moi = sauDoi?.diagnostics?.points[1];

      // MỌI trường của điểm đã dời là của lần dời MỚI. Một cách cài giữ khối cũ
      // rồi vá vài trường lên trên cho ra đúng một điểm mang tầng mới với định
      // danh cũ — và lúc ấy mọi tín hiệu trung thực của gói đều nói dối về đúng
      // cái điểm vừa đổi chỗ.
      expect(moi?.target, ArRaycastTarget.existingPlaneInfinite);
      expect(moi?.planeId, tuong);
      expect(moi?.planeAlignment, ArPlaneAlignment.vertical);
      expect(moi?.tracking, ArTrackingSnapshot.limitedExcessiveMotion);
      expect(moi?.sessionAgeMs, 9120);
      expect(moi?.cameraDistanceMm, 1810.0);
      expect(moi?.rayAngleDeg, 11.5);

      // Bất biến của van đi theo lai lịch mới, không đi theo lai lịch cũ: điểm
      // cũ ở tầng hình học nên KHÔNG có van, điểm mới ở tầng ngoại suy nên PHẢI
      // có. Đây là chỗ một khối chẩn đoán vá nửa vời lộ ra.
      expect(cu?.overshootMm, isNull);
      expect(moi?.overshootMm, 1946.0);
      expect(
        moi?.overshootMm != null,
        moi?.target == ArRaycastTarget.existingPlaneInfinite,
      );

      // Đầu KHÔNG bị dời không nhúc nhích. Một cách cài dựng lại cả hai khối
      // chẩn đoán bằng một tia mới sẽ đổi luôn điểm này — và nó đổi sang lai
      // lịch của một cú bấm chưa từng xảy ra.
      expect(
        sauDoi?.diagnostics?.points[0].planeId,
        truocDoi?.diagnostics?.points[0].planeId,
      );
      expect(
        sauDoi?.diagnostics?.points[0].sessionAgeMs,
        truocDoi?.diagnostics?.points[0].sessionAgeMs,
      );
    });

    test('planeId của điểm sai kiểu hay rỗng về null, không ném', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 400.0,
          'tolMm': 8.0,
          'diagnostics': {
            'points': [
              {'target': 'existingPlaneGeometry', 'planeId': 7},
              {'target': 'existingPlaneGeometry', 'planeId': ''},
            ],
          },
        });
      }, returnsNormally);

      expect(s?.diagnostics?.points, hasLength(2));
      expect(s?.diagnostics?.points[0].planeId, isNull);
      expect(
        s?.diagnostics?.points[1].planeId,
        isNull,
        reason:
            'Hai chuỗi rỗng bằng nhau. Để chúng đi tiếp là hai điểm bất kỳ đọc '
            'ra "cùng một mặt phẳng" — im lặng, và về phía "yên tâm".',
      );
      expect(
        s?.diagnostics?.points[0].target,
        ArRaycastTarget.existingPlaneGeometry,
        reason: 'một định danh hỏng không được kéo theo cả lai lịch của điểm',
      );
    });

    test('overshootMm của điểm sai kiểu hay vô cực về null, không ném', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'firstPointPlaced',
          'diagnostics': {
            'points': [
              {'target': 'existingPlaneInfinite', 'overshootMm': 'xa'},
              {'target': 'existingPlaneInfinite', 'overshootMm': double.nan},
            ],
          },
        });
      }, returnsNormally);

      expect(s?.diagnostics?.points, hasLength(2));
      expect(s?.diagnostics?.points[0].overshootMm, isNull);
      expect(s?.diagnostics?.points[1].overshootMm, isNull);
      expect(
        s?.diagnostics?.points[1].target,
        ArRaycastTarget.existingPlaneInfinite,
        reason: 'một quãng hỏng không được kéo theo cả lai lịch của điểm',
      );
    });

    // Sáu nhánh bám tách nhau ra vì mỗi nhánh là một giả thuyết KHÁC về vì sao
    // một số đo lệch. Gộp cả năm nhánh `.limited` thành một chữ "limited" là
    // xoá đúng phần phân biệt được chúng.
    test('sáu nhánh trạng thái bám đọc ra sáu giá trị khác nhau', () {
      ArTrackingSnapshot? doc(String raw) => ArMeasure.parseSample({
        'status': 'ready',
        'diagnostics': {
          'points': [
            {'tracking': raw},
          ],
        },
      })?.diagnostics?.points.single.tracking;

      expect(doc('normal'), ArTrackingSnapshot.normal);
      expect(
        doc('limitedInitializing'),
        ArTrackingSnapshot.limitedInitializing,
      );
      expect(
        doc('limitedExcessiveMotion'),
        ArTrackingSnapshot.limitedExcessiveMotion,
      );
      expect(
        doc('limitedInsufficientFeatures'),
        ArTrackingSnapshot.limitedInsufficientFeatures,
      );
      expect(
        doc('limitedRelocalizing'),
        ArTrackingSnapshot.limitedRelocalizing,
      );
      expect(doc('notAvailable'), ArTrackingSnapshot.notAvailable);
    });

    test('chuỗi lạ ở target/tracking/planeAlignment về null, không ném', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 812.0,
          'tolMm': 12.0,
          'diagnostics': {
            'points': [
              {
                'target': 'vệ tinh',
                'tracking': 'vệ tinh',
                'planeAlignment': 'vệ tinh',
              },
            ],
          },
        });
      }, returnsNormally);

      final p = s?.diagnostics?.points.single;
      expect(s?.measurement?.mm, 812, reason: 'khoá lạ không được giết số đo');
      expect(p?.target, isNull);
      expect(p?.tracking, isNull);
      expect(p?.planeAlignment, isNull);
    });

    test('số sai kiểu (chuỗi) về null, không ném', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'ready',
          'diagnostics': {
            'points': [
              {
                'sessionAgeMs': 'not-a-number',
                'cameraDistanceMm': 'not-a-number',
                'rayAngleDeg': 'not-a-number',
                'planeWidthMm': 'not-a-number',
                'planeHeightMm': 'not-a-number',
              },
            ],
          },
        });
      }, returnsNormally);

      final p = s?.diagnostics?.points.single;
      expect(p?.sessionAgeMs, isNull);
      expect(p?.cameraDistanceMm, isNull);
      expect(p?.rayAngleDeg, isNull);
      expect(p?.planeWidthMm, isNull);
      expect(p?.planeHeightMm, isNull);
    });

    test('diagnostics sai kiểu (không phải map) về null, mẫu vẫn sống', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 400.0,
          'tolMm': 6.0,
          'diagnostics': 'not-a-map',
        });
      }, returnsNormally);

      expect(s?.status, ArMeasureStatus.measured);
      expect(s?.measurement?.mm, 400);
      expect(s?.diagnostics, isNull);
    });

    test('points sai kiểu (không phải danh sách) về null, mẫu vẫn sống', () {
      late ArMeasureSample? s;
      expect(() {
        s = ArMeasure.parseSample({
          'status': 'measured',
          'mm': 400.0,
          'tolMm': 6.0,
          'diagnostics': {'points': 'not-a-list'},
        });
      }, returnsNormally);

      expect(s?.measurement?.mm, 400);
      expect(s?.diagnostics, isNull);
    });

    // Một phần tử hỏng KHÔNG được rơi ra khỏi danh sách: rơi ra là điểm thứ
    // hai trượt lên chỗ điểm thứ nhất, và cả dải chẩn đoán nói dối về việc
    // điểm nào được chấm trong điều kiện nào — im lặng, không lỗi nào nổ.
    test('phần tử hỏng giữ NGUYÊN CHỖ, thành một điểm trống', () {
      final s = ArMeasure.parseSample({
        'status': 'measured',
        'mm': 400.0,
        'tolMm': 6.0,
        'diagnostics': {
          'points': ['not-a-map', diemDay(target: 'estimatedPlane')],
        },
      });

      final points = s?.diagnostics?.points;
      expect(points, hasLength(2));
      expect(points?[0].target, isNull);
      expect(points?[0].tracking, isNull);
      expect(
        points?[1].target,
        ArRaycastTarget.estimatedPlane,
        reason:
            'điểm thứ hai phải còn ở CHỖ THỨ HAI, không được trượt lên chỗ đầu',
      );
    });
  });

  group('isAvailable', () {
    // Thiếu plugin (chạy trên máy không phải iOS, hoặc gói chưa đăng ký) phải trả
    // false chứ KHÔNG ném: app gọi hàm này để quyết định ẩn hay hiện một nút.
    test('kênh ném thì trả false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => throw MissingPluginException(),
          );

      expect(await ArMeasure.isAvailable(), isA<ArAvailability>());
      expect((await ArMeasure.isAvailable()).arSupported, isFalse);
    });
  });

  group('ArMeasureController', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async {
              calls.add(call);
              return call.method == 'placePoint' ? 'placed' : null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            null,
          );
    });

    // Mười lệnh, và MỖI lệnh phải chở theo viewId. Thiếu id thì tầng Swift
    // không tra được view nào trong sổ đăng ký, và lệnh rơi vào chỗ trống mà
    // không có gì nổ — đúng dạng lỗi câm mà ca kiểm này tồn tại để chặn.
    test('mọi lệnh gửi đúng tên và kèm viewId', () async {
      const c = ArMeasureController(7);

      await c.placePoint();
      await c.movePoint(1);
      await c.grabPoint(0);
      await c.releasePoint();
      await c.undoPoint();
      await c.reset();
      await c.pause();
      await c.resume();
      await c.captureFrame();
      await c.dispose();

      expect(calls.map((c) => c.method), [
        'placePoint',
        'movePoint',
        'grabPoint',
        'releasePoint',
        'undoPoint',
        'reset',
        'pause',
        'resume',
        'captureFrame',
        'dispose',
      ]);
      for (final call in calls) {
        expect((call.arguments as Map)['viewId'], 7);
      }
      // `movePoint` và `grabPoint` là hai lệnh DUY NHẤT mang thêm một tham số,
      // và tham số ấy là toàn bộ nội dung của chúng: một lệnh không nói đụng
      // vào đầu nào thì tầng Swift phải đoán, và đoán sai là dời nhầm đầu —
      // một điểm nhảy chỗ, một con số mới, và không có gì nổ.
      expect(
        calls.firstWhere((c) => c.method == 'movePoint').arguments,
        {'viewId': 7, 'index': 1},
      );
      expect(
        calls.firstWhere((c) => c.method == 'grabPoint').arguments,
        {'viewId': 7, 'index': 0},
      );
      // `releasePoint` thì KHÔNG mang chỉ số, và đó là chủ đích: phiên đang
      // nắm đúng một đầu và chỉ nó biết đầu nào. Bắt app nói lại chỉ số ở lúc
      // buông là dựng một nguồn sự thật thứ hai, và hai nguồn ấy lệch nhau ở
      // đúng những đường gói TỰ buông (gián đoạn, mất bám, `reset`).
      expect(
        calls.firstWhere((c) => c.method == 'releasePoint').arguments,
        {'viewId': 7},
      );
    });

    // Bốn kết quả, và ba trong bốn là "không có điểm nào đặt" vì ba lý do KHÁC
    // NHAU. Một `bool` gộp cả ba lại thành một câu duy nhất, mà ba lời khuyên
    // đúng thì ngược nhau: rê máy tìm bề mặt, chờ phiên bám lại, hay bấm Chốt.
    test('placePoint đọc được cả bốn kết quả tầng nền nói', () async {
      Future<ArMeasurePlaceResult> place(Object? reply) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              (call) async => reply,
            );
        return const ArMeasureController(1).placePoint();
      }

      expect(await place('placed'), ArMeasurePlaceResult.placed);
      expect(await place('missed'), ArMeasurePlaceResult.missed);
      expect(await place('notReady'), ArMeasurePlaceResult.notReady);
      expect(
        await place('alreadyComplete'),
        ArMeasurePlaceResult.alreadyComplete,
      );
    });

    // Nền tảng trả null (vd. một bản Swift cũ chỉ biết trả `bool`), trả một
    // chuỗi lạ, hoặc không có plugin nào để trả: cả ba đều là KHÔNG có điểm nào
    // đặt, và lời khuyên duy nhất không sai ở đó là "chưa chấm được" — chứ
    // không phải "rê máy tìm bề mặt", vì rê cả ngày cũng không cứu một kênh
    // chết.
    test('placePoint không đọc được thì về notReady, không ném', () async {
      Future<ArMeasurePlaceResult> place(
        Future<Object?> Function(MethodCall) handler,
      ) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              handler,
            );
        return const ArMeasureController(1).placePoint();
      }

      expect(await place((_) async => null), ArMeasurePlaceResult.notReady);
      expect(
        await place((_) async => 'sao chổi'),
        ArMeasurePlaceResult.notReady,
      );
      expect(await place((_) async => true), ArMeasurePlaceResult.notReady);
      expect(
        await place((_) async => throw MissingPluginException()),
        ArMeasurePlaceResult.notReady,
      );
      expect(
        await place((_) async => throw PlatformException(code: 'boom')),
        ArMeasurePlaceResult.notReady,
      );
    });

    // Bốn kết quả, cùng một lối với `placePoint`: ba trong bốn là "không có gì
    // dời đi đâu cả" vì ba lý do KHÁC NHAU, và ba câu nói với người dùng cũng
    // khác nhau — rê máy tìm bề mặt, chờ phiên bám lại, hay không nói gì cả vì
    // chính app vừa hỏi về một điểm không tồn tại.
    test('movePoint đọc được cả bốn kết quả tầng nền nói', () async {
      Future<ArMeasureMoveResult> move(Object? reply) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              (call) async => reply,
            );
        return const ArMeasureController(1).movePoint(0);
      }

      expect(await move('moved'), ArMeasureMoveResult.moved);
      expect(await move('missed'), ArMeasureMoveResult.missed);
      expect(await move('notReady'), ArMeasureMoveResult.notReady);
      expect(await move('noSuchPoint'), ArMeasureMoveResult.noSuchPoint);
    });

    // Giá trị canh gác là `notReady`, KHÔNG phải `noSuchPoint`. Một kênh câm
    // không biết gì về việc app đang có mấy điểm, nên trả `noSuchPoint` ở đó là
    // nói dối app VỀ DỮ LIỆU CỦA CHÍNH NÓ — và app tin lời ấy sẽ giấu luôn cái
    // nút dời, vĩnh viễn, vì một điểm nó đang vẽ trên màn.
    test('movePoint không đọc được thì về notReady, không ném', () async {
      Future<ArMeasureMoveResult> move(
        Future<Object?> Function(MethodCall) handler,
      ) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              handler,
            );
        return const ArMeasureController(1).movePoint(0);
      }

      expect(await move((_) async => null), ArMeasureMoveResult.notReady);
      expect(await move((_) async => 'sao chổi'), ArMeasureMoveResult.notReady);
      expect(await move((_) async => true), ArMeasureMoveResult.notReady);
      // Một bản Swift cũ hơn lệnh này trả `FlutterMethodNotImplemented`, và nó
      // tới Dart dưới dạng `MissingPluginException`.
      expect(
        await move((_) async => throw MissingPluginException()),
        ArMeasureMoveResult.notReady,
      );
      expect(
        await move((_) async => throw PlatformException(code: 'boom')),
        ArMeasureMoveResult.notReady,
      );
    });

    // Luật "chỉ số nào hợp lệ" nằm ở ĐÚNG MỘT chỗ, và chỗ ấy là tầng Swift —
    // nơi duy nhất biết đang có mấy điểm. Dart chặn thêm một lượt ở đây là dựng
    // một bản chép của luật ấy, và bản chép lệch ngay lượt đầu ai đó đổi số
    // điểm tối đa: Dart trả `noSuchPoint` cho một chỉ số mà Swift chấp nhận, và
    // lệnh không bao giờ rời máy.
    test('movePoint KHÔNG tự quyết chỉ số nào hợp lệ', () async {
      final sent = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async {
              sent.add(call);
              return 'noSuchPoint';
            },
          );

      const c = ArMeasureController(3);
      expect(await c.movePoint(-1), ArMeasureMoveResult.noSuchPoint);
      expect(await c.movePoint(99), ArMeasureMoveResult.noSuchPoint);

      expect(sent.map((c) => c.arguments), [
        {'viewId': 3, 'index': -1},
        {'viewId': 3, 'index': 99},
      ]);
    });

    // `captureFrame` là lệnh DUY NHẤT trả về một tài nguyên (một tệp trên
    // đĩa), nên nó là lệnh duy nhất mà "không đọc được" phải phân biệt được
    // với "đọc được một chuỗi rỗng". `null` nói KHÔNG có tệp nào; một chuỗi
    // rỗng đi tiếp vào `File('')` và nổ ở tầng khác, xa chỗ hỏng.
    test('captureFrame trả đúng đường dẫn tầng nền báo', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => '/tmp/ar-frame-1.jpg',
          );

      expect(
        await const ArMeasureController(1).captureFrame(),
        '/tmp/ar-frame-1.jpg',
      );
    });

    test('captureFrame không đọc được thì về null, không ném', () async {
      Future<String?> capture(
        Future<Object?> Function(MethodCall) handler,
      ) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(ArMeasure.methodChannelName),
              handler,
            );
        return const ArMeasureController(1).captureFrame();
      }

      // Không có khung hình nào để ghi (phiên chưa chạy, view đã chết).
      expect(await capture((_) async => null), isNull);
      // Một bản Swift lệch pha trả sai kiểu.
      expect(await capture((_) async => 12), isNull);
      expect(
        await capture((_) async => throw MissingPluginException()),
        isNull,
      );
      expect(
        await capture((_) async => throw PlatformException(code: 'boom')),
        isNull,
      );
    });

    test('thiếu plugin: lệnh khác không ném', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => throw MissingPluginException(),
          );

      const c = ArMeasureController(1);
      await expectLater(c.undoPoint(), completes);
      await expectLater(c.reset(), completes);
      await expectLater(c.pause(), completes);
      await expectLater(c.resume(), completes);
      await expectLater(c.dispose(), completes);
    });

    test('nền tảng ném PlatformException thì cũng không ném ra', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(ArMeasure.methodChannelName),
            (call) async => throw PlatformException(code: 'boom'),
          );

      await expectLater(const ArMeasureController(1).dispose(), completes);
    });
  });

  group('samples', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(ArMeasure.eventChannelName),
            null,
          );
    });

    test('khung hợp lệ thành ArMeasureSample', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(ArMeasure.eventChannelName),
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({
                  'status': 'measured',
                  'mm': 812.0,
                  'tolMm': 12.0,
                  'snappedToEdge': false,
                });
              },
            ),
          );

      final got = await ArMeasure.samples.first;

      expect(got.status, ArMeasureStatus.measured);
      expect(got.measurement?.mm, 812);
      expect(got.measurement?.tolMm, 12);
    });

    // Một khung hỏng KHÔNG được giết luồng. Luồng này nuôi màn hình đang đo:
    // nó chết thì màn đông cứng ở khung cuối, và không có gì trên màn nói ra.
    test('khung hỏng bị bỏ, khung sau vẫn tới', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(ArMeasure.eventChannelName),
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({'status': 'vệ tinh'});
                sink.success('không phải map');
                sink.error(code: 'boom');
                sink.success({'status': 'ready'});
              },
            ),
          );

      final got = <ArMeasureSample>[];
      final sub = ArMeasure.samples.listen(got.add);
      await pumpEventQueue();
      await sub.cancel();

      expect(got.map((s) => s.status), [ArMeasureStatus.ready]);
    });
  });

  // Lớp phủ: hai đầu đoạn thẳng ở toạ độ MÀN, và số đo đang chạy.
  //
  // Toạ độ 3D chỉ tầng Swift chiếu được, nên mọi thứ dưới đây là hợp đồng ĐỌC
  // một khung đã chiếu sẵn. Cả nhóm canh cùng một kiểu hỏng CÂM: một trường sai
  // kiểu mà ném thì cả luồng chết, và lớp phủ đông cứng ở khung cuối — tức là
  // một đoạn thẳng nằm lại giữa màn, đọc ra "đã chấm xong".
  group('parseOverlay', () {
    test('đủ trường', () {
      final o = ArMeasure.parseOverlay({
        'ax': 120.0,
        'ay': 240.5,
        'bx': 300.0,
        'by': 90.0,
        'bIsLive': true,
        'distanceMm': 382.0,
      });

      expect(o.pointA, const Offset(120, 240.5));
      expect(o.pointB, const Offset(300, 90));
      expect(o.bIsLive, isTrue);
      expect(o.distanceMm, 382);
    });

    // Khung RỖNG là một khung hợp lệ, không phải một khung hỏng: nó là cách
    // tầng nền nói "không còn gì để vẽ" sau một lượt Hoàn tác hay một lượt mất
    // bám. Bỏ nó đi thì đoạn thẳng cũ nằm lại trên màn.
    test('khung rỗng: mọi trường null, không ném', () {
      late ArMeasureOverlay o;
      expect(() => o = ArMeasure.parseOverlay({}), returnsNormally);

      expect(o.pointA, isNull);
      expect(o.pointB, isNull);
      expect(o.bIsLive, isFalse);
      expect(o.distanceMm, isNull);
    });

    // Một nửa toạ độ KHÔNG dựng nổi một điểm. Lấy nửa còn lại rồi bù 0 là đặt
    // một đầu đoạn thẳng lên mép trên màn — một chỗ trông hoàn toàn hợp lệ.
    test('thiếu một nửa toạ độ thì cả điểm về null, không bù 0', () {
      expect(ArMeasure.parseOverlay({'ax': 120.0}).pointA, isNull);
      expect(ArMeasure.parseOverlay({'ay': 240.0}).pointA, isNull);
      expect(ArMeasure.parseOverlay({'bx': 300.0}).pointB, isNull);
      expect(ArMeasure.parseOverlay({'by': 90.0}).pointB, isNull);
    });

    test('toạ độ sai kiểu không ném, điểm về null', () {
      late ArMeasureOverlay o;
      expect(() {
        o = ArMeasure.parseOverlay({
          'ax': 'không phải số',
          'ay': 240.0,
          'bx': 300.0,
          'by': 90.0,
        });
      }, returnsNormally);

      expect(o.pointA, isNull);
      expect(o.pointB, const Offset(300, 90));
    });

    test('distanceMm sai kiểu không ném, và không kéo hai điểm theo', () {
      late ArMeasureOverlay o;
      expect(() {
        o = ArMeasure.parseOverlay({
          'ax': 10.0,
          'ay': 20.0,
          'distanceMm': 'không phải số',
        });
      }, returnsNormally);

      expect(o.distanceMm, isNull);
      expect(o.pointA, const Offset(10, 20));
    });

    test('bIsLive sai kiểu về false, không ném', () {
      expect(
        ArMeasure.parseOverlay({'bIsLive': 'không phải bool'}).bIsLive,
        isFalse,
      );
    });

    // Toạ độ ÂM là toạ độ HỢP LỆ: một đầu đoạn thẳng ra ngoài mép màn trong khi
    // đầu kia còn trong khung là chuyện thường ở tầm đo gần. Lọc số âm ở đây là
    // cắt cụt đúng những đoạn dài nhất, và cắt im lặng.
    //
    // Thứ phân biệt "ngoài mép màn" với "sau lưng camera" là thành phần z của
    // phép chiếu, và nó được kiểm ở tầng Swift chứ không ở đây: tới Dart thì z
    // đã không còn.
    test('toạ độ âm giữ nguyên, không bị lọc', () {
      final o = ArMeasure.parseOverlay({
        'ax': -40.0,
        'ay': 120.0,
        'bx': 300.0,
        'by': -18.0,
      });

      expect(o.pointA, const Offset(-40, 120));
      expect(o.pointB, const Offset(300, -18));
    });

    // NaN đi qua `Offset` không ném gì cả, và `Canvas.drawLine` chỉ lặng lẽ
    // không vẽ. Một đoạn thẳng biến mất mà không lỗi nào nổ là đúng dạng hỏng
    // cả gói này đi tránh, nên chặn ngay ở cửa.
    test('toạ độ không hữu hạn về null, không dựng Offset câm', () {
      expect(
        ArMeasure.parseOverlay({'ax': double.nan, 'ay': 10.0}).pointA,
        isNull,
      );
      expect(
        ArMeasure.parseOverlay({'bx': double.infinity, 'by': 10.0}).pointB,
        isNull,
      );
      expect(
        ArMeasure.parseOverlay({
          'ax': 1.0,
          'ay': 2.0,
          'distanceMm': double.nan,
        }).distanceMm,
        isNull,
      );
    });

    test('số nguyên đọc được y như số thực', () {
      final o = ArMeasure.parseOverlay({
        'ax': 120,
        'ay': 240,
        'distanceMm': 382,
      });

      expect(o.pointA, const Offset(120, 240));
      expect(o.distanceMm, 382.0);
    });
  });

  group('overlay', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        ..setMockStreamHandler(
          const EventChannel(ArMeasure.overlayChannelName),
          null,
        )
        ..setMockStreamHandler(
          const EventChannel(ArMeasure.eventChannelName),
          null,
        );
    });

    test('khung hợp lệ thành ArMeasureOverlay', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(ArMeasure.overlayChannelName),
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({
                  'ax': 120.0,
                  'ay': 240.0,
                  'bx': 300.0,
                  'by': 90.0,
                  'bIsLive': true,
                  'distanceMm': 382.0,
                });
              },
            ),
          );

      final got = await ArMeasure.overlay.first;

      expect(got.pointA, const Offset(120, 240));
      expect(got.pointB, const Offset(300, 90));
      expect(got.bIsLive, isTrue);
      expect(got.distanceMm, 382);
    });

    // Cùng lý lẽ với `samples`: luồng này nuôi một lớp vẽ 30 Hz, nên nó chết là
    // lớp phủ đông cứng ở khung cuối và không có gì trên màn nói ra.
    test(
      'khung hỏng bị bỏ, lỗi kênh không giết luồng, khung sau vẫn tới',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              const EventChannel(ArMeasure.overlayChannelName),
              MockStreamHandler.inline(
                onListen: (arguments, sink) {
                  sink.success('không phải map');
                  sink.error(code: 'boom');
                  sink.success({'ax': 1.0, 'ay': 2.0});
                },
              ),
            );

        final got = <ArMeasureOverlay>[];
        final sub = ArMeasure.overlay.listen(got.add);
        await pumpEventQueue();
        await sub.cancel();

        expect(got.map((o) => o.pointA), [const Offset(1, 2)]);
      },
    );

    // HAI kênh, không phải một. `samples` mang trạng thái và chẩn đoán ở nhịp
    // thấp; gộp lớp phủ 30 Hz vào đó là bắt mọi người nghe trạng thái lọc ba
    // mươi khung mỗi giây để tìm một thay đổi mỗi vài giây.
    test('khung trạng thái KHÔNG rơi vào luồng lớp phủ', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(ArMeasure.eventChannelName),
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({
                  'status': 'measured',
                  'mm': 812.0,
                  'tolMm': 12.0,
                });
              },
            ),
          );

      final got = <ArMeasureOverlay>[];
      final sub = ArMeasure.overlay.listen(got.add);
      await pumpEventQueue();
      await sub.cancel();

      expect(got, isEmpty);
      expect(ArMeasure.overlayChannelName, isNot(ArMeasure.eventChannelName));
    });
  });
}
