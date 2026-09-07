## Unreleased

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

## 0.1.0

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
