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
* Points are `ARAnchor`s, so they follow ARKit's corrections to the world
  coordinate system instead of drifting silently away from them.
* Relocalization is attempted after an interruption. If it has not succeeded
  within five seconds, both points are dropped and the session returns to
  `ready` rather than measuring across two different coordinate systems.
* iOS only. No network calls, no permissions requested by this package — your
  app needs `NSCameraUsageDescription` in its own `Info.plist`.
