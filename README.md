# headless_ar_measure

A headless AR distance measurement surface for iOS: a typed stream of status
and distance samples over an ARKit camera view.

Every number, every label, every unit conversion is left to you. This
package hands back millimetres and a tolerance; how you display them is not
its business.

Headless does not mean it draws nothing. It draws exactly the two things
Flutter cannot draw for you, and nothing else:

- **The two points and the segment between them** — including the *live*
  segment that follows the crosshair once the first point is down. They are 3D
  coordinates in ARKit's world, so only the native layer knows where they land
  on screen after the phone turns.
- **Surface-scanning guidance** — Apple's `ARCoachingOverlayView`, in the
  system's own words and the device's own language. It turns itself on while
  the session is not ready and off once ARKit has found a plane.

No text of ours, no numbers, no buttons, no product vocabulary.

## Install

```yaml
dependencies:
  headless_ar_measure: ^0.4.0
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
switch (await controller?.placePoint()) {
  case ArMeasurePlaceResult.placed:            // haptic, and carry on
  case ArMeasurePlaceResult.missed:            // "move around until it locks"
  case ArMeasurePlaceResult.alreadyComplete:   // "read the number, or undo"
  case ArMeasurePlaceResult.notReady || null:  // the status already says why
}

// And from State.dispose():
controller?.dispose();
```

| Call | What it does |
|---|---|
| `ArMeasure.isAvailable()` | `ARWorldTrackingConfiguration.isSupported`, asked **at runtime** |
| `ArMeasure.samples` | Status and distance, one broadcast stream |
| `ArMeasure.overlay` | The segment's two endpoints in **screen points**, plus the running distance. A second stream, up to 30Hz |
| `ArMeasure.parseSample()` | Builds an `ArMeasureSample` from raw channel data |
| `ArMeasure.parseOverlay()` | Builds an `ArMeasureOverlay` from raw channel data |
| `ArMeasureView` | A thin `UiKitView` wrapper around the native camera surface. Takes no touches — put your buttons on top of it |
| `ArMeasureController.placePoint()` | Places a point under the screen centre; returns an `ArMeasurePlaceResult` saying why not, when not |
| `ArMeasureController.undoPoint()` | Drops the last point |
| `ArMeasureController.reset()` | Drops both points and rebuilds the coordinate system |
| `ArMeasureController.pause()` / `.resume()` | Stops and restarts the camera, keeping both points |
| `ArMeasureController.captureFrame()` | Writes the current camera frame to a JPEG in the temp directory and returns its path, or `null` |
| `ArMeasureController.dispose()` | **Required.** Stops the session and turns the camera off |

### The crosshair has to say what it is on

`ArMeasureSample.aimTarget` is what a ray from the centre of the screen is
hitting right now. Three answers, not two:

| `aimTarget` | What a tap would do | What to draw |
|---|---|---|
| `existingPlaneGeometry` | land on a plane ARKit has confirmed | the confident crosshair |
| `estimatedPlane` | land on a plane ARKit just guessed around the ray | a weaker crosshair — placeable, but the depth can be off |
| `null` | **miss** | the empty crosshair, plus a line telling the user where to aim instead |

`ArMeasureSample.aimLocked` is the older two-value form of the same probe
(`aimTarget != null`), kept so existing code does not have to change. Both come
from one raycast, so they cannot disagree.

This is not polish. Without it, a miss and a broken button look identical: a
real device, aimed at a glossy black tablet screen at close range — reflective,
untextured, near-zero feature points, the worst surface ARKit can be handed —
produced a "Place" button that did nothing at all, with `ready` on screen the
whole time. The ray was missing, correctly; nothing said so.

It is probed with the **same** raycast `placePoint()` uses, and it is always
`null` outside `ready` and `firstPointPlaced` — once both points are down there
is nothing left to aim at.

**There is no grace period, and that is a fix, not an omission.** Until 0.4.0
the flag stayed `true` for 0.3s after the first missing probe, and every hit
re-armed that window. On a surface that only catches now and then, a single hit
every 0.3s pinned the crosshair to "locked" continuously while most taps missed
— the user sees the lock, taps, misses, sees the lock again. On a real device
that loop cost 130 seconds for the first point and 136 for the second. The
value now always comes from a real raycast, at most one 10Hz sample old. It
does flicker on a marginal surface; the flicker is the information.

And when a tap does miss anyway, `placePoint()` says which kind of nothing
happened:

| `ArMeasurePlaceResult` | What to say |
|---|---|
| `placed` | nothing — fire a haptic |
| `missed` | move slowly around the object until the crosshair locks |
| `notReady` | the current `ArMeasureStatus` already carries the reason |
| `alreadyComplete` | both points are down; read the number, or undo |

`notReady` is also what you get when the channel cannot answer at all — a
missing plugin, a disposed view. Never `missed`: inviting someone to keep
moving the phone will not revive a dead channel.

### The segment is live before the second tap

Once the first point is down, the package draws a segment from it to whatever
the centre ray is currently hitting, refreshed every ARKit frame — the way
Apple's Measure app behaves. When the ray hits nothing, the segment is **not
drawn at all**; a segment left standing where the last hit was reads as a
finished measurement.

`ArMeasure.overlay` is the same thing in Flutter's coordinates, for the label
you want to hang off it:

```dart
final overlayFrame = ValueNotifier<ArMeasureOverlay?>(null);
ArMeasure.overlay.listen((frame) => overlayFrame.value = frame);
```

| Field | What it is |
|---|---|
| `pointA` | the first point in screen **points**, origin top-left, same space as a `CustomPaint` stacked over `ArMeasureView` |
| `pointB` | the other end: the second placed point, or the live crosshair hit |
| `bIsLive` | `pointB` is the moving crosshair, not a placed point |
| `distanceMm` | distance between the two ends, live ones included |

Feed it into a `ValueNotifier` and repaint from that. This is a 30Hz stream;
calling `setState` on it rebuilds your whole subtree thirty times a second.

Three things about it that are easy to get wrong when reading the numbers:

- `pointA` and `pointB` are `null` when there is **nowhere on screen** to draw
  — no point placed, a ray that hit nothing, or a point that has gone behind the
  camera. A point merely off the edge of the screen is *not* null: its
  coordinate is negative or past the screen width, and the segment reaching it
  still crosses the frame.
- `distanceMm` is measured in 3D, so it survives an endpoint that cannot be
  projected. It is also the same computation as `ArMeasurement.mm`, so the
  running number and the settled number never disagree by formula.
- It is a **separate channel** from `samples` on purpose. Status and diagnostics
  change every few seconds; folding a 30Hz stream into them would make every
  status listener filter thirty frames a second to find one change. The package
  also never re-sends a frame identical to the previous one, so silence means
  nothing moved — not that something broke.

### Every sample carries how the measurement happened

`ArMeasureSample.diagnostics` holds one `ArPointDiagnostics` per placed point,
in the order they were placed — one entry after the first tap, two once both
are down, `null` before any point exists or on a native build older than this
field.

| Field | What it is |
|---|---|
| `target` | which raycast layer actually hit: a confirmed `existingPlaneGeometry` or a guessed `estimatedPlane`. Read off `ARRaycastResult.target`, not inferred |
| `tracking` | raw ARKit tracking state at the tap. Six values — the five `.limited` reasons are **not** collapsed into one word |
| `sessionAgeMs` | milliseconds since the last `run(...)`. Resets with the coordinate system, so it answers "was the session still warming up?" |
| `cameraDistanceMm` | camera centre to the placed point |
| `rayAngleDeg` | the ray's angle **to the surface**: 90° is dead-on, 0° is grazing |
| `planeAlignment`, `planeWidthMm`, `planeHeightMm` | the `ARPlaneAnchor` that was hit, if any. All three `null` when the hit landed on an estimated plane |

`ArMeasureDiagnostics.video` sits beside those points and describes the whole
session rather than one tap: the `width`, `height` and `fps` of the ARKit video
format actually running. It is present **before any point exists**, which is
when you most need it — that is the moment someone is asking why nothing can be
placed. See "The video format is an experiment" below.

Why it exists: a tile edge measured 382mm against a true 400, two tiles measured
795 against 800, and every explanation anyone proposed fitted both numbers
equally well — because the sample said nothing about the conditions either point
was placed under. None of this feeds the distance calculation. It is a recording
layer, and it says what the machine did.

Every field is nullable on purpose. No camera frame, a value ARKit adds in a
later iOS, an older native build — all of it comes back `null` rather than a
plausible default, because a plausible default here is manufactured evidence.

### A captured frame is bare on purpose

`captureFrame()` writes the current camera frame — and nothing else — to a JPEG
in the temp directory. No dots, no segment, no coaching card. `ARSCNView`
does have a `snapshot()`, and it would have been one line; it returns what is
on screen, which includes Apple's coaching overlay, and it does not include the
one thing a person keeps a photo for: the number. Your app already draws that
number in Flutter. Compose on a bare frame and it is drawn once.

Two properties make composing possible at all:

* the image is the size of the **viewport** times the screen scale, not the
  sensor's full 12MP — so the point coordinates from `ArMeasure.overlay` map
  onto it with a single multiply;
* the rotation is baked into the **pixels** via `ARFrame.displayTransform`, not
  written as an EXIF orientation flag. The file is upright in any viewer, not
  only the ones that read the flag.

The file belongs to the caller: this package never deletes it, and the system
clears the temp directory on a schedule of its own.

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

### The video format is an experiment

Since 0.4.0 the session picks the **highest-resolution** entry of
`ARWorldTrackingConfiguration.supportedVideoFormats` instead of taking Apple's
default (ties go to the higher frame rate; an empty list leaves the default
alone). The hypothesis is plain: ARKit pulls feature points out of the camera
image, so more pixels should mean more points on the poorly textured surfaces
where planes currently refuse to grow.

It is a hypothesis, not a promise. The highest-resolution format on some devices
runs at 30fps where the default runs at 60, and half the frames is half the
world updates — which could eat the gain, or more. That is why
`ArMeasureDiagnostics.video` reports `fps` alongside the resolution: show it on
screen during a device run. **If the frame rate drops and the wait does not,
this should be reverted.**

It still is a hypothesis after the first device run. The run landed on
3840×2160 at 30fps and the wait fell from 130 s to 7.8 s, so the revert
condition above was not met — but the same build also shipped the honest
crosshair, which plausibly accounts for most of that fall on its own. Nothing
separates the two. There is also a mechanism pointing the other way: the
highest-resolution formats are non-binned, giving up the pixel binning that
suppresses noise in dark areas, and the surface that failed was a *black*
mousepad. Treat 4K@30 as **unresolved**; a comparison that settles it has to
change exactly one thing. See the 0.4.1 CHANGELOG entry for the numbers.

`fps` here is the format's **nominal** rate — read from
`config.videoFormat.framesPerSecond` once at `run`, never updated. A session
throttled down to 20fps still reports 30. Label it as nominal wherever you show
it, and count frames yourself if you need the delivered rate.

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
