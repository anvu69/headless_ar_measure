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
    test('aimTarget đọc được cả hai tầng tia gói bắn ra', () {
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

      expect(geometry?.aimTarget, ArRaycastTarget.existingPlaneGeometry);
      expect(estimated?.aimTarget, ArRaycastTarget.estimatedPlane);
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

    test('mặt ước lượng: không có mặt phẳng nào, ba khoá mp về null', () {
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

    // Bảy lệnh, và MỖI lệnh phải chở theo viewId. Thiếu id thì tầng Swift
    // không tra được view nào trong sổ đăng ký, và lệnh rơi vào chỗ trống mà
    // không có gì nổ — đúng dạng lỗi câm mà ca kiểm này tồn tại để chặn.
    test('mọi lệnh gửi đúng tên và kèm viewId', () async {
      const c = ArMeasureController(7);

      await c.placePoint();
      await c.undoPoint();
      await c.reset();
      await c.pause();
      await c.resume();
      await c.captureFrame();
      await c.dispose();

      expect(calls.map((c) => c.method), [
        'placePoint',
        'undoPoint',
        'reset',
        'pause',
        'resume',
        'captureFrame',
        'dispose',
      ]);
      for (final call in calls) {
        expect(call.arguments, {'viewId': 7});
      }
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
