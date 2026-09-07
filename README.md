# headless_ar_measure

A headless AR distance measurement surface for iOS. No overlays — just a
typed stream of status and distance samples over a raw ARKit camera view.

Every number, every label, every unit conversion is left to you. This
package hands back millimetres and a tolerance; how you display them is not
its business.

## Install

```yaml
dependencies:
  headless_ar_measure: ^0.1.0
```

iOS only. There is no Android implementation, and that is deliberate — this
package wraps ARKit, and everything in it is Apple's semantics.

## Use

```dart
final availability = await ArMeasure.isAvailable();
if (!availability.arSupported) return;

final sample = ArMeasure.parseSample(rawMapFromYourChannel);
if (sample?.measurement case final m?) {
  print('${m.mm.toStringAsFixed(0)}mm ±${m.tolMm.toStringAsFixed(0)}mm');
}
```

| Call | What it does |
|---|---|
| `ArMeasure.isAvailable()` | `ARWorldTrackingConfiguration.isSupported`, asked **at runtime** |
| `ArMeasure.parseSample()` | Builds an `ArMeasureSample` from raw channel data |
| `ArMeasureView` | A thin `UiKitView` wrapper around the native camera surface |

## It never throws

A missing plugin registration, a simulator, a device that has not finished
registering the platform view — all of them surface as sentinel values
(`isAvailable() => ArAvailability(false, false)`, `parseSample() => null`).
You do not need a `try` around any call in this package.

## Status

This is the Dart-only skeleton of the package: types, channel names, and the
platform view widget. There is no native (Swift) implementation behind it
yet, so every method-channel call currently resolves through the
"missing plugin" path above. That is expected at this stage — it is what
lets the whole public surface be exercised with `flutter test` on a machine
with no iPhone attached.

## Why a package and not a few files in your app

Dropping a `.swift` file into `ios/Runner/` only compiles it **if it is in
the Xcode target**. With a classic `project.pbxproj`, adding the file by hand
does not add it to the target — and nothing fails loudly. The code is simply
never built.

A plugin package has its own podspec, so every Swift file in it is compiled.
That is the whole reason this exists as a package.

## License

MIT.
