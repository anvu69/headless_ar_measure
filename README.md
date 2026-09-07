# headless_ar_measure

A headless AR distance measurement surface for iOS: a typed stream of status
and distance samples over an ARKit camera view.

Every number, every label, every unit conversion is left to you. This
package hands back millimetres and a tolerance; how you display them is not
its business.

Headless does not mean it draws nothing. It draws exactly the two things
Flutter cannot draw for you, and nothing else:

- **The two points and the segment between them.** They are 3D coordinates in
  ARKit's world, so only the native layer knows where they land on screen after
  the phone turns. Flutter only ever receives a millimetre value.
- **Surface-scanning guidance** — Apple's `ARCoachingOverlayView`, in the
  system's own words and the device's own language. It turns itself on while
  the session is not ready and off once ARKit has found a plane.

No text of ours, no numbers, no buttons, no product vocabulary.

## Install

```yaml
dependencies:
  headless_ar_measure: ^0.1.0
```

iOS only. There is no Android implementation, and that is deliberate — this
package wraps ARKit, and everything in it is Apple's semantics.

Your app's `Info.plist` needs an `NSCameraUsageDescription`. Without it the
app is killed the moment the session starts.

### The camera prompt is ours to raise

Your app does not need a permission plugin. When authorization is still
`notDetermined`, this package asks for it with `AVCaptureDevice.requestAccess`
**before** starting the session, and starts the session only once the answer is
in. A refusal arrives as `ArMeasureStatus.cameraUnauthorized`.

That ordering is load-bearing, not tidiness. Calling `ARSession.run()` while the
permission is undecided makes the camera pipeline depend on a grant that happens
*after* `run` — nothing in Apple's contract says ARKit rebuilds that pipeline
when the user taps Allow, and no session callback reports that it did not.
`didFailWithError` stays silent and the tracking state stays silent. The AR
surface is **transparent** until SceneKit draws its first frame, so what the
user sees is their own app's background, with nothing anywhere saying why.

## Use

```dart
final availability = await ArMeasure.isAvailable();
if (!availability.arSupported) return;

ArMeasureController? controller;

// The stream feeds the screen; the controller drives the session.
ArMeasure.samples.listen((sample) {
  print(sample.status);
  if (sample.measurement case final m?) {
    print('${m.mm.toStringAsFixed(0)}mm ±${m.tolMm.toStringAsFixed(0)}mm');
  }
});

ArMeasureView(
  onPlatformViewCreated: (id) => controller = ArMeasureController(id),
);

// Later, from a button:
final placed = await controller?.placePoint() ?? false;
if (!placed) { /* the ray hit nothing — tell the user to aim at a surface */ }

// And from State.dispose():
controller?.dispose();
```

| Call | What it does |
|---|---|
| `ArMeasure.isAvailable()` | `ARWorldTrackingConfiguration.isSupported`, asked **at runtime** |
| `ArMeasure.samples` | Status and distance, one broadcast stream |
| `ArMeasure.parseSample()` | Builds an `ArMeasureSample` from raw channel data |
| `ArMeasureView` | A thin `UiKitView` wrapper around the native camera surface. Takes no touches — put your buttons on top of it |
| `ArMeasureController.placePoint()` | Places a point under the screen centre; `false` if the ray hit nothing |
| `ArMeasureController.undoPoint()` | Drops the last point |
| `ArMeasureController.reset()` | Drops both points and rebuilds the coordinate system |
| `ArMeasureController.pause()` / `.resume()` | Stops and restarts the camera, keeping both points |
| `ArMeasureController.dispose()` | **Required.** Stops the session and turns the camera off |

### `dispose()` is not optional

iOS has no dispose callback for a platform view — `FlutterPlatformView` has
exactly one method, `view()`. Nothing on the native side is told when Flutter
drops the widget. So `ArMeasureController.dispose()` from your
`State.dispose()` is the only thing that turns the camera off on time; without
it the session runs until the engine happens to release the view.

### The number drifts, and that is the point

Once both points are down, the distance is recomputed **from every ARKit
frame**, and a new sample goes out whenever it has moved by more than 0.5mm —
paced to at most 15Hz, with a trailing emit so the last refinement is never the
one that gets dropped. You watch the number settle, and that settling is the
signal that the reading is worth keeping. Freezing it is your job; this package
keeps reporting.

The two points are `ARAnchor`s, which is how you tell ARKit that you care about
those spots. But nothing here relies on ARKit updating them: `ARAnchor.transform`
is read-only, Apple's own guidance for a moving object is to remove the anchor
and add a new one, and the classes Apple documents as self-updating are
subclasses (`ARPlaneAnchor`, `ARGeoAnchor`) rather than a plain app-added
anchor. `session(_:didUpdate anchors:)` only promises that ARKit *may* update.

So the transforms are read back out of `ARFrame.anchors`, matched by
`identifier`, on every frame. If ARKit revises a point, that revision shows up.
If it never does, the number is simply constant — which is the truth, rather
than a stale reading dressed up as a live one.

### The surface takes no touches

`ARSCNView` is created with `isUserInteractionEnabled = false`, so UIKit's hit
test never stops there and every touch falls straight through to Flutter. Put
your buttons in a `Stack` on top of the view and treat it as a picture.

One consequence worth knowing: the Reset button Apple's coaching overlay shows
during relocalization is not tappable either. Nothing is stranded by that — the
session gives up on relocalization after five seconds by itself, and
`ArMeasureController.reset()` does the same job from your own UI.

### Tolerance

`tolMm` is `max(2mm, 0.5%)` on a device with scene reconstruction and
`max(5mm, 1.5%)` without. These are working assumptions, not measured
constants — but a number shipped without a tolerance is a promise of precision
the sensor cannot keep.

## It never throws

A missing plugin registration, a simulator, a ray that hit nothing, a command
aimed at a view that is already gone — all of them surface as sentinel values
(`isAvailable() => ArAvailability(false, false)`, `parseSample() => null`,
`placePoint() => false`, every other command a silent no-op). The sample
stream swallows both malformed frames and channel errors, because a stream
that dies leaves the screen frozen on its last frame with nothing to say why.

You do not need a `try` around any call in this package.

## Why a package and not a few files in your app

Dropping a `.swift` file into `ios/Runner/` only compiles it **if it is in
the Xcode target**. With a classic `project.pbxproj`, adding the file by hand
does not add it to the target — and nothing fails loudly. The code is simply
never built.

A plugin package has its own podspec, so every Swift file in it is compiled.
That is the whole reason this exists as a package.

## License

MIT.
