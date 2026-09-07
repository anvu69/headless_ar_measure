// Integration test — must run on a real device.
//
// `isAvailable()` is false everywhere at this stage (no native
// implementation exists yet), so the only thing that can be asserted is that
// the call reaches the platform channel and comes back without throwing.
import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('isAvailable answers without throwing', (tester) async {
    final availability = await ArMeasure.isAvailable();

    expect(availability, isA<ArAvailability>());
  });
}
