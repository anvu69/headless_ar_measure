## 0.3.0

A photo of a measurement is a different artefact from a measurement. It outlives
the session, it leaves the app, and it is the only thing left when someone asks
you a week later how wide the doorway was.

* **`ArMeasureController.captureFrame()`** — writes the current camera frame to
  a JPEG in the temp directory and returns its path. `null` means there is no
  file, for any reason at all: no session, dead view, dead channel, unwritable
  disk. It never throws, and it never returns an empty string, because an empty
  string travels one more layer before it fails.
* The frame is **bare**. No dots, no segment, no coaching card. `snapshot()`
  would have been one line and would have returned all three — including
  Apple's coaching card, a white slab across the middle of the picture — while
  still not returning the number, which is the thing people keep a photo for.
  Your app draws the number; composing on a bare frame draws it once.
* The image is the size of the **viewport** times the screen scale, not the
  sensor's full 12MP. The point coordinates from `ArMeasure.overlay` therefore
  land on it with a single multiply. A full-sensor image has a different aspect
  ratio from the viewport, and an overlay drawn on it sits somewhere other than
  where the person just saw it.
* Rotation is baked into the **pixels**, through `ARFrame.displayTransform` for
  the current interface orientation — not written as an EXIF orientation flag.
  A viewer that ignores the flag is not a rare viewer.
* The file belongs to the caller. This package does not delete it.

Not verified on a device yet: whether the baked rotation is right in all four
interface orientations, and whether the overlay coordinates land where they
should on the composed image at @2x and @3x.

## 0.2.0

Until now the segment only appeared once *both* points were down. Everything
before that was a crosshair and a hope: you aimed, tapped, aimed somewhere else,
and only then found out what you had measured. Apple's Measure app has drawn a
live segment since 2018, and the reason is not decoration — the segment is how
you see that you are about to measure the wrong edge, while you can still move.

* **A live segment.** With one point placed, every ARKit frame draws a segment
  from it to whatever the centre ray is currently hitting. A ray that hits
  nothing draws **nothing**: a segment left standing where the last hit was
  reads as a finished measurement, and it is the reading a still image cannot
  distinguish from a real one.
* **`ArMeasure.overlay`** — a new `Stream<ArMeasureOverlay>` carrying both
  endpoints already projected to screen coordinates, in **points** (Flutter's
  unit, origin top-left), plus `bIsLive` and the running `distanceMm`. It exists
  because Dart cannot do the projection: it is `SCNSceneRenderer.projectPoint`,
  and it has to run in the same pass that draws the frame or the label lags a
  frame behind the segment it is labelling.
* An endpoint that is **behind the camera** comes back `null`, not a
  coordinate. The projection runs through the origin, so a point behind you
  lands at a perfectly plausible spot in front of you and neither x nor y says
  so; only z does. An endpoint merely off the edge of the screen keeps its
  coordinate, negative or not — the segment reaching it still crosses the frame.
* `distanceMm` is computed in 3D and shares its formula with
  `ArMeasurement.mm`, so the running number and the settled number cannot
  disagree; it survives an endpoint that will not project.
* A **second event channel**, not a wider `samples`. The overlay runs at up to
  30Hz and `samples` stays capped at 15Hz: merging them would make every status
  listener filter thirty frames a second looking for a change that arrives every
  few seconds. Identical consecutive frames are not re-sent, so silence on this
  stream means nothing moved.
* The crosshair probe and the live endpoint now read **one** raycast per frame
  instead of two — and the probe runs every frame (not at 10Hz) for exactly as
  long as a live segment is on screen.

Not verified on a device yet: whether the projected coordinates land on the
segment on a @2x/@3x screen, and whether the live segment tracks the crosshair
without visible lag.

## 0.1.0

A tile edge measured 382mm against a true 400 (−4.5%); two tiles measured 795
against 800 (−0.6%). Sixteen agents went looking for the cause and came back
with nothing — every hypothesis fitted both numbers, because the sample the
package pushes to Dart carried not one bit about *how* the measurement had
happened. This release does not touch the measurement. It records what the
machine did.

* **`ArMeasureSample.diagnostics`** — an `ArMeasureDiagnostics` carrying one
  `ArPointDiagnostics` per placed point, in the order they were placed: one
  entry after the first tap, two once both are down. `null` when no point has
  been placed, and `null` on older native builds. Never an empty list: empty
  reads as "measured, and there was nothing", `null` reads as "this build does
  not say".
* Per point: which raycast target actually hit (`existingPlaneGeometry` vs
  `estimatedPlane` — read straight off `ARRaycastResult.target`, not inferred
  from the query order), the raw ARKit tracking state at the moment of the tap
  (six values; the five `.limited` reasons are *not* collapsed into one word,
  because each is a different explanation for the same wrong number), the
  session age in milliseconds since the last `run(...)`, the camera-to-point
  distance in mm, the ray's angle to the surface in degrees, and — when the hit
  landed on a real `ARPlaneAnchor` — that plane's alignment and extent in mm.
* Every field is nullable, deliberately. No camera frame, an `@unknown` value
  from a later iOS, an older native build: all of it comes back `null`. Inventing
  a default here would be manufacturing evidence for the very investigation the
  layer exists to serve.
* A malformed entry on the wire becomes an *empty* point rather than being
  dropped, so point two can never slide into point one's slot. A malformed
  block, or one that is not a map at all, drops the diagnostics and keeps the
  sample: a side channel that can kill the measurement stream is a product bug,
  not a diagnostic.
* **`ArMeasurement.snappedToEdge` is still a hard-coded `false`** and is now
  documented as such at every level. It is not computed anywhere in this
  package. Sitting next to a block of real measured numbers, a bare `false`
  reads exactly like a computation that ran and returned false.

### Second device run

Second run on real hardware (iPhone 16 Plus): the camera works, the coaching
overlay samples the room, the session reports `ready` — and the Place button
does nothing. Aimed at a glossy black tablet screen at close range, the raycast
was missing every time, correctly, with nothing on screen saying so.

* **`ArMeasureSample.aimLocked`** — whether a ray from the centre of the screen
  is currently hitting a surface, i.e. whether a tap would place a point. Swap
  the crosshair on it, the way Apple's Measure app does, and a miss stops
  looking like a dead button. Probed with the *same* raycast `placePoint()`
  uses — a crosshair that promises one ray and a button that fires another is
  the same failure with extra steps. Always `false` outside `ready` and
  `firstPointPlaced`.
* The probe runs at 10Hz rather than per frame: it is a boolean nobody can read
  faster than that, it stays under the 15Hz sample pacing so it can never be
  what saturates the channel, and the per-frame budget stays with the distance
  path that has to run at frame rate. It drops back to `false` only after 0.3s
  of consecutive misses, so a marginal surface does not strobe the crosshair.
  A flip of the flag bypasses the pacing entirely — that pacing is anchored on
  "the distance moved more than 0.5mm", and the flag changes precisely when
  there is no distance yet.
* **`placePoint()` returns `ArMeasurePlaceResult`, not `bool`.** Three of the
  four values mean "no point was placed", for three reasons whose remedies are
  opposite: `missed` (move around until it locks), `notReady` (the status says
  why), `alreadyComplete` (read the number, or undo). `notReady` is also the
  fallback when the channel cannot answer, because telling someone to keep
  moving the phone will not revive a dead channel. **Breaking.**
* `isAutoFocusEnabled` is now set explicitly. It is already Apple's default,
  but it is the one flag in the whole configuration that makes detection
  materially harder when it is off — at the near end of this package's 0.3–3m
  range, a focus locked at infinity blurs the image enough that ARKit extracts
  almost no feature points. A default is not a contract.
* `environmentTexturing` and `frameSemantics` stay off, deliberately, and there
  are now tests pinning that. Neither touches plane detection or raycasting:
  environment texturing builds light probes for reflections on virtual content
  that this package does not have (its marks use a `.constant` material that
  takes no light), and `.sceneDepth` only exposes `ARFrame.sceneDepth` for an
  app to read — ARKit's own raycast already consumes the LiDAR mesh through
  `sceneReconstruction`. Neither makes a single ray hit.
* The raycast keeps its two layers and does **not** gain
  `.existingPlaneInfinite`. That third layer would have "rescued" the exact
  scene that failed — it extends the table plane straight through the tablet
  sitting on it — but the point it returns is at *table* height, and aimed at a
  distant wall it returns somewhere along an extended floor. A number that
  looks ordinary and is wrong is this package's worst failure mode.

### First device run

First run on real hardware (iPhone 16 Plus), and four things it turned up.

* **The camera prompt is now this package's job.** Authorization that is still
  `notDetermined` used to share a branch with `authorized`, and `ARSession.run()`
  was called straight away. That makes the camera pipeline depend on a grant
  that lands *after* `run`, with nothing in Apple's contract promising ARKit
  rebuilds it and no callback reporting that it did not. The AR surface is
  transparent until SceneKit draws its first frame, so the failure showed up as
  the host app's own background colour and no error anywhere. Authorization is
  now requested first and the session starts on the answer.
* **The AR surface takes no touches.** `isUserInteractionEnabled = false`, so
  UIKit's hit test never stops on it and every touch falls through to the
  Flutter widgets above. (The gesture-recognizer blocking policy was not the
  problem: `Eager` blocks the *platform view's* recognizers as soon as Flutter
  claims a touch, and `ARSCNView` registers none of its own.)
* **The two points and the segment between them are drawn**, in SceneKit, where
  the 3D coordinates actually live. Constant lighting model (the session runs
  with no lights, so a lit material would render pure black), depth buffer off
  (so LiDAR mesh and detected planes cannot clip the marks away), and a NaN
  guard on the segment's rotation (measuring top-to-bottom yields exactly −Y,
  where the rotation axis is undefined and SceneKit silently drops a NaN
  transform).
* **Surface-scanning guidance** via `ARCoachingOverlayView` with
  `goal = .anyPlane` — Apple's own view, Apple's own words, the device's own
  language. It activates while the session is not ready and deactivates when
  ARKit has found a plane.
* The platform view factory now holds the plugin strongly. Measured on a
  simulator that it was never nil, but `create` is the only place a new view is
  wired into the plugin's registry, and a nil there would silence the whole
  sample stream with no error.

### The surface itself

First release.

* `ArMeasure.isAvailable()` — runtime check, never inferred from the device
  model. A missing plugin, a simulator, or a bundle without the native side
  all surface as `arSupported == false`.
* `ArMeasure.samples` — one broadcast stream of status and distance. Never
  throws and never ends: a malformed frame is dropped and a channel error is
  swallowed, because a dead stream leaves the screen frozen on its last frame.
* `ArMeasure.parseSample()` — builds an `ArMeasureSample` from raw channel
  data. Never throws: an unknown `status` returns `null`, and a status with no
  accompanying numbers still parses with `measurement == null`.
* `ArMeasureStatus` — eight values covering the full lifecycle of a measuring
  session, including the interruptions that are not the app's fault
  (`interrupted`, `cameraUnauthorized`).
* `ArMeasureSample.limitedReason` — `excessiveMotion` or `insufficientFeatures`
  when the status is `needsMotion`. Both ARKit reasons map to that one status,
  but the fix for them is opposite: one asks the user to slow down, the other
  to move around looking for texture. Without this field the screen has to pick
  one sentence and be wrong half the time. `null` when the platform does not
  say, so a screen still has to have a sentence that works for both.
* `ArMeasureSample.recoverable` — `false` only for permanent failures
  (`unsupportedConfiguration`, `sensorUnavailable`, and a device that cannot
  run world tracking at all). These arrive as `trackingLost`, which is true but
  makes a screen invite the user to keep moving the phone forever. Defaults to
  `true` when the key is absent.
* `ArMeasureController` — `placePoint`, `undoPoint`, `reset`, `pause`,
  `resume`, `dispose`, all aimed at one platform view id. `placePoint` returns
  `false` when the ray hit nothing; every other command is a silent no-op when
  it cannot be delivered.
* `ArMeasureView` — a thin `UiKitView` wrapper. Draws nothing itself; every
  number and every label is the caller's job.
* ARKit session: horizontal and vertical plane detection on every device,
  scene reconstruction where the device supports it, and a layered raycast
  (`.existingPlaneGeometry`, then `.estimatedPlane`). One code path — LiDAR
  changes what the second layer hits, not which branch runs.
* The distance is recomputed from every `ARFrame`, reading both point
  transforms back out of `ARFrame.anchors` by `identifier` rather than trusting
  a stored copy. Samples are still paced — 0.5mm threshold, 15Hz, trailing
  emit — so this is not a 60Hz firehose. The two points are `ARAnchor`s, which
  is how ARKit is told those spots matter, but `ARAnchor.transform` is
  read-only and `session(_:didUpdate anchors:)` only promises ARKit *may*
  update a plain app-added anchor; the frame is the trigger that always
  arrives.
* Relocalization is attempted after an interruption. If it has not succeeded
  within five seconds, both points are dropped and the session returns to
  `ready` rather than measuring across two different coordinate systems. The
  deadline re-checks the session state before it fires: it is armed by an event
  but was only ever disarmed by a tracking-state *transition*, and ARKit only
  reports transitions — so a brief interruption that never left `.normal` used
  to wipe the points of a perfectly healthy session five seconds later.
* No `SCNNode` is built for any anchor. `ARSCNView` creates and maintains one
  per `ARAnchor` by default, which on a LiDAR device with scene reconstruction
  is hundreds of nodes for geometry nobody draws. The view delegate returns
  `nil` from `renderer(_:nodeFor:)` — Apple's header: *"If nil is returned the
  anchor will be ignored."* This package draws nothing, so there is nothing to
  build.
* iOS only. No network calls, no permissions requested by this package — your
  app needs `NSCameraUsageDescription` in its own `Info.plist`.
