// Integration test — must run on a real iOS device or simulator.
//
// It asserts almost nothing about AR itself: there is no way to place a point
// from a test, and no way to know what the camera is looking at. What it does
// assert is the one thing that breaks silently and is invisible to
// `flutter test` — that the Swift side is registered and answering.
//
// The public Dart calls all swallow `MissingPluginException` by design, so a
// missing registration looks exactly like "no ARKit here". These tests
// therefore go through the raw channel, where a missing plugin throws.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ArMeasure.methodChannelName);

  testWidgets('the plugin is registered and answers isAvailable', (
    tester,
  ) async {
    final raw = await channel.invokeMethod<Map<Object?, Object?>>(
      'isAvailable',
    );

    // A plugin that never registered throws above and never gets here.
    expect(raw, isNotNull);
    expect(raw!['arSupported'], isA<bool>());
    expect(raw['hasSceneDepth'], isA<bool>());
  });

  // A command aimed at a view that does not exist must come back as a sentinel,
  // not as an exception. This is the whole "no function throws back to Dart"
  // contract, checked at the place it is actually implemented.
  testWidgets('a command for an unknown view returns a sentinel', (
    tester,
  ) async {
    final placed = await channel.invokeMethod<bool>('placePoint', {
      'viewId': -1,
    });
    expect(placed, isFalse);

    for (final method in ['undoPoint', 'reset', 'pause', 'resume', 'dispose']) {
      await expectLater(
        channel.invokeMethod<void>(method, {'viewId': -1}),
        completes,
      );
    }
  });

  testWidgets('isAvailable never throws', (tester) async {
    expect(await ArMeasure.isAvailable(), isA<ArAvailability>());
  });
}
