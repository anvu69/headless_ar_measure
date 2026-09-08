## 0.7.0

Two numbers, and neither is a feature. The app on top of this package finished a
tolerance term and could not add it up, because two of its inputs did not exist
anywhere on the wire:

```
ε = d · Δu / (fx · sin θ)
```

The aiming error projected onto the surface is divided by `sin θ`, where θ is the
angle between the ray and the **plane**. At 0.6m with 2px of aiming error: 0.83mm
at θ=90°, 4.00mm at θ=12°, 9.55mm at θ=5°. That is not a corner case — crouching
low and sighting along the edge is exactly how a person holds a phone to measure
a table.

**The package still computes none of it.** It does not know `Δu`, does not
compute `ε`, and sets no threshold. Where "too grazing" falls depends on what the
app is measuring, the same boundary `overshootMm` already draws. What 0.7.0 adds
is the two facts a device can actually report: how long the lens is, and how
grazing the ray is.

* **`ArMeasureSample.aimRayAngleDeg`** — the angle between the ray you are
  aiming **right now** and the surface it is on. Sampled on the same raycast, at
  the same 10Hz grid, as `aimTarget` and `aimOvershootMm`: three numbers that
  only mean anything together are read from one shot at one surface from one
  camera pose. Re-measuring it a step later measures a different ray, and the
  answer is still a plausible number of degrees.

  `ArPointDiagnostics.rayAngleDeg` has carried this number for a *placed* point
  since 0.3.0. A warning built on that one arrives after the tap it should have
  prevented, which is no warning at all.

  **It does not follow the valve's rule, on purpose.** The old invariant is
  untouched — `aimOvershootMm != null` still means exactly
  `aimTarget == existingPlaneInfinite`, because it describes a boundary being
  crossed and the other two tiers cross none. The angle is different in kind: a
  ray grazing an ARKit-*confirmed* plane at 4° is still grazing at 4°. Gating it
  behind the extrapolation tier would switch the grazing warning off on the tier
  people trust most. It is `null` only when the ray hits nothing — there is no
  surface to measure an angle against.

  It is in the sample coalescer, and that is not redundant with `featureCensus`
  pulling nearly every sample along today: `ArFeatureCensus` is an instrument
  with an expiry date, and its own docs say so. The day it leaves, an angle
  outside the coalescer would freeze at its first value while the user tilts the
  phone — the exact failure the valve already paid for once, in a different
  number.

* **`ArMeasureDiagnostics.camera`** — `fx` (focal length in **pixels**,
  `ARFrame.camera.intrinsics[0][0]`) with the `width` and `height` of the frame
  it was read from. Both off one `ARCamera`, in one statement. No part of `ios/`
  or `lib/` mentioned `intrinsics` before this release.

  **Nobody may hardcode this.** 1442 — the figure every article about iOS
  devices quotes — is the focal length of the 1920×1440 format. This package
  picks the largest format the device supports (3840×2160 on the device we
  measured on), and `fx` scales with frame width, so the real number is nearly
  double. A hardcoded one is wrong by a factor of two, and both values land
  inside the range that looks reasonable: a few millimetres.

  Two more reasons it cannot be a constant, and both are already written into
  this package: the format choice is the **unresolved experiment** of 0.4.0,
  whose own revert condition is recorded in 0.4.1 — the day someone acts on it,
  `fx` has to move with it; and `isAutoFocusEnabled` is on, so the focal length
  drifts *within* a session. Reading it once at `run` is the same hardcoding
  wearing a different coat, so it is read from every frame instead.

  **Why the resolution ships with it rather than being borrowed from
  `ArMeasureDiagnostics.video`.** That block is a snapshot of the format that was
  *asked for*, taken once at `run` from `config.videoFormat`. This one is the
  frame that actually *arrived*, and it is the pixel coordinate system
  `intrinsics` is expressed in. ARKit does not promise the two agree, and `fx`
  read against the wrong width is a wrong division whose answer is still a
  plausible number of millimetres. A reader of the diagnostics strip cannot
  interpret 1442 or 2884 without the width beside it either.

  `fx` is deliberately **outside** the sample coalescer, the opposite call from
  the angle. Autofocus nudges it almost every frame; putting it in would turn
  the status channel into a 60Hz firehose for a number nobody watches in real
  time — an app reads it once and puts it in a formula. It rides along on samples
  already being emitted, exactly like `video`. It is also the one diagnostics
  block **never** gated by session state: it describes the device, not an aim,
  and it is needed at the two moments the aim gates cut — once both points are
  down, and before any point exists.

* **The angle calculation moved to one place.** `rayAngleDeg(from:hitTransform:)`
  is now a single static function, called by both `makeDiagnostics` and
  `probeReticle`. Two copies of it would have let the live warning show one angle
  while the diagnostics strip for that very tap recorded another — both valid
  degrees, and nobody could tell. Same law as `raycastTarget(of:)` and
  `PlaneOvershoot`.

* **`probeReticle` now takes the frame.** The angle is measured against a camera
  pose, and it has to be the pose of the frame the raycast happened on. Reading
  `session.currentFrame` inside the method leans on an assumption that is true
  and that nothing guards — that ARKit has swapped the frame in before calling
  the delegate.

**What is still missing, and an app has to work around it:** there is no *live*
camera distance. `d` exists for a placed point (`cameraDistanceMm`) and for the
finished segment (`ArMeasureOverlay.distanceMm`, which is the segment length, not
the camera-to-target range), but a pre-tap warning has no `d` of its own and has
to substitute a working range. Adding one is a separate decision; it is not
implied by this release.

Tests: 18 new — nine parsing the wire on the Dart side, nine pinning the Swift
rules that break silently. Two existing ones changed on purpose: the pinned
coalescer condition grew a term, and the "angle is measured to the plane, not the
normal" case now watches the shared function it moved into.

## 0.6.0

**This release reverses a decision this package had pinned in a test.** Until
now `raycastFromReticle` tried exactly two targets, and a test named *"two ray
tiers, in order, and NO infinite-plane tier"* held it there. The reason it gave
is quoted here in full, because it is still correct:

> `.existingPlaneInfinite` would "rescue" the scene in the device photo — it
> extends the tabletop through the iPad and returns a point. But that point sits
> at TABLETOP HEIGHT, not at the iPad's surface, and aimed at a far wall it
> returns a point somewhere along the extended floor. A number that looks normal
> and is wrong is the worst failure this package has.

Nothing in that argument is withdrawn. What changed is the three words *looks
normal*: a tier-three hit is now **only accepted if it can declare how far
outside the plane's real boundary it landed**, and that distance travels to Dart
alongside the ray tier. The scene the old test described — a tabletop extended
through an iPad — now announces itself with a number in the hundreds of
millimetres instead of arriving silently.

**What forced the reversal** is the 0.5.0 instrument, on a real device: the raw
feature-point cloud for the **whole frame** held **26 points, sometimes 2**;
around the ray, **1, sometimes 0**. That is not enough material for any plane
fit, hand-written or otherwise, so the RANSAC idea 0.5.0 was built to evaluate
is dead. The real choice was never "extrapolate or measure correctly" — it was
**"extrapolate with a label, or measure nothing at all"**.

* **A third raycast tier, tried LAST.** `.existingPlaneGeometry`, then
  `.estimatedPlane`, then `.existingPlaneInfinite`. The first two tiers are
  byte-for-byte unchanged — they are the path currently producing 4–8mm on tile
  floors, and nothing here touches it. Order is a contract, pinned by a test that
  fails on any permutation: an infinite plane hits from nearly every direction,
  so promoting it would mean the two observed-point tiers are never reached
  again, and the whole package would quietly switch to measuring inferred points.

* **`overshootMm` — the valve, and the only reason the reversal is legitimate.**
  When tier three hits, the package measures from the touch point to the nearest
  **edge** of that same plane's `ARPlaneAnchor.geometry.boundaryVertices`, and
  ships it in millimetres beside the tier. Tens of millimetres means a table edge
  the detected boundary has not grown out to yet; hundreds of millimetres to
  metres is exactly the failure the old test warned about, and it now shows up as
  a large number instead of nothing at all.

  It arrives on both existing paths, not a new one: `ArMeasureSample.aimOvershootMm`
  for the ray being aimed right now, and `ArPointDiagnostics.overshootMm` for
  each placed point. Both are `null` on the other two tiers — and that `null` is a
  fact, not a gap: a point inside the real boundary, or on a plane ARKit just
  estimated, has no boundary to overshoot. Filling in `0` there would claim a
  measurement was taken.

* **A tier-three hit that cannot declare its overshoot is discarded**, returned
  as a miss. No plane anchor on the result, fewer than three boundary vertices, a
  non-finite vertex — all of them drop the hit. This is also how "do not
  extrapolate before any plane has been detected" is enforced, and it is enforced
  exactly rather than approximately: no plane means no anchor to extend, so the
  hit falls out on its own. A separate pre-check counting the session's planes
  would cost more and answer a different question.

* **The extrapolated endpoint draws differently in SceneKit**: an open ring
  instead of a filled dot, same size, same single ink. The difference is **shape,
  not colour**, and that is deliberate. The scene has no lights, so every material
  here is self-illuminated — a second glowing colour on a camera feed reads as an
  *error*, and an extrapolated point is not an error, it is a placeable point with
  lower confidence. Colour is also the first thing lost to colour-blindness and to
  a greyscale print. And two dots in different colours can only be compared when
  both are on screen at once; hollow-versus-solid reads on each end by itself. The
  ring is billboarded, because a torus seen edge-on is a thread and seen down its
  axis is nothing at all.

**`captureFrame()` is still bare**, so the distinction reaches a saved photo only
through the overlay your app draws. Everything needed for that is on the samples
stream already: the tier of each placed point in `diagnostics.points[i].target`,
and the tier of the live end in `aimTarget`. The overlay channel deliberately
does **not** carry tiers — it would be a second path saying the same thing at a
different rate, and two such paths drift.

**Tolerance is unchanged, and that is a boundary, not an oversight.** `tolMm` is
still `max(2mm, 0.5%)` / `max(5mm, 1.5%)`. Widening it for an extrapolated
endpoint requires deciding how much overshoot is how much doubt, and that depends
on what is being measured and what the number is used for. The package reports
the truth — which tier, how far past the boundary — and the policy is the app's.

**Emit-rate cost: none beyond 0.5.0's.** `aimOvershootMm` joins the coalescer key
because it is the only field that changes while the user pans across an
extrapolated surface — the status, the limited reason and the tier all sit still
there, so without it the valve would freeze at its first reading while the ray
drifted metres away. The 10Hz ceiling from `aimProbeIntervalSeconds` still holds,
and the floor was already gone in 0.5.0.

**The geometry has a numeric test**, which is new for this package. `PlaneOvershoot`
lives in its own file importing only `Foundation` and `simd`, so `swiftc` compiles
and runs it on macOS and `flutter test` checks actual millimetres. This is not
tidiness: the two wrong implementations it rules out — measuring to the nearest
**vertex** instead of the nearest **edge**, and comparing a world-space point
against plane-space vertices without the transform — both leave plausible-looking
Swift and both return a positive, finite, correctly-scaled millimetre value. On
the fixture used, the correct answer is 300mm; measuring to a vertex gives
921.95mm and skipping the transform gives 1656.42mm. No text-reading test
separates those. The fixture's boundary is deliberately asymmetric, because a
symmetric one makes both mistakes invisible.

**Not measured on a device yet.** Everything above is a contract and a
computation; whether extrapolation with a labelled overshoot actually makes the
black-mousepad scene measurable is a question only a phone answers.
## 0.5.0

**This release adds an instrument, not a feature.** Two numbers land in
`ArMeasureDiagnostics`, they answer one open question, and they are expected to
be removed once it is answered. Read the question before reading the numbers.

**The question.** A user measuring a wooden table edge — the tabletop covered by
a flat black mousepad, plain walls, indoors at night — gets `nil` from the
centre-ray raycast continuously: `.existingPlaneGeometry` and `.estimatedPlane`
both come back empty. One proposal on the table is to stop using ARKit's raycast
result and fit a plane directly, with RANSAC over `ARFrame.rawFeaturePoints`.
Before building that, it is worth knowing whether there is anything to fit —
because `.estimatedPlane` **is already** "fit a plane to the feature points
around the ray", and it returns nothing. If there are no points around the ray
either, a hand-written plane fitter returns the same emptiness at a higher cost,
and the idea should die here.

Nothing in this package had ever touched `rawFeaturePoints`, `ARPointCloud`, or
`hitTest(`. This is the first time.

* **`ArMeasureDiagnostics.features`** — an `ArFeatureCensus?` carrying `total`
  (every point in the current frame's raw cloud) and `nearRay` (how many of them
  fall inside a cone around the ray cast from screen centre). Both fields are
  nullable, and the whole block is `null` on any build older than this one.
  Sampled on the **existing** 10Hz aim grid, in the same pass and from the same
  `ARFrame` as `aimTarget` — the sentence the census exists to support is "the
  ray missed, and there were 40 points around it", and that sentence is only
  true if both halves describe one frame. Current frame only: no history, no
  accumulation. Accumulating over time is a separate decision, and it is only
  worth arguing about after the single-frame number has spoken.

* **`0` and `null` are not the same answer, and the whole measurement lives in
  that distinction.** `0` means ARKit handed over a cloud and the cloud was
  empty — a fact that closes the question. `null` means nothing was asked.

**The cone: half-angle 10°, range window 0.2–3m.** All three are chosen by
argument, not measured. A cone rather than a cylinder because the crosshair has
a fixed size *on screen*, so "around the ray" is an angular neighbourhood, not a
metric one. Deliberately **wider than the crosshair itself** (which subtends
under 5°): a plane fit does not need points under the crosshair, it needs points
on the same nearby surface, and a cone narrow enough to restate what
`.estimatedPlane` already said would answer nothing. 10° in particular is what
makes a **zero** decisive — with a narrow cone, zero could just mean the material
sat at 6°. The price of that width is stated plainly: at the far end of the
window the cone spans over a metre across, so a **high** count does not yet prove
the material lies on the aimed surface. Low counts conclude; high counts only
mean "not ruled out". The range window exists because a cone from the camera is
infinite — without a far cut, "around the ray" quietly becomes "somewhere in this
direction", and in a room the far wall wins the count. The near cut is about
triangulation quality, not geometry: raw feature points are triangulated over
time, and at very short baselines their coordinates are mostly noise.

**The cost, stated up front: the samples channel no longer goes quiet while the
user is aiming.** The census had to join the emit coalescer, because in the exact
scene under investigation `status`, `limitedReason`, `aimTarget` and `mm` are all
frozen, so `publish` would never fire and the new numbers would never reach Dart
at the one moment they were built to describe. Unlike `aimTarget`, the census
changes on nearly every sample. The 10Hz ceiling from `aimProbeIntervalSeconds`
still holds and cannot be exceeded, but the floor is gone: while `ready` or
`firstPointPlaced`, expect up to ten samples per second instead of silence. That
is the price of a measurement build, and it leaves when the measurement does.

**Nothing else changed.** No RANSAC, no new scoring, no change to raycasting,
placement, distance, or the crosshair. The numbers decide whether any of that
gets built.

## 0.4.1

Documentation only. **No behaviour change**: the video format selection, the
crosshair, and every wire field are byte-for-byte what 0.4.0 shipped. This entry
exists because the first device run produced numbers that are easy to
misremember in either direction.

**The 0.4.0 video-format experiment: the revert condition was not met, and the
experiment is still confounded.**

0.4.0 wrote its own condition down before there was any data: *"If a device run
shows the frame rate dropping without the wait shrinking, revert this."* The run
happened — iPhone 16 Plus, no LiDAR, table edge on a black mousepad:

* **Before the selection block existed** (this is where 130 s comes from — it is
  the *reason* the block was written, not a result of it): **130 s** to land the
  first point, **136 s** for the second.
* **With the selection block**, session running 3840×2160 at 30fps: **7.8 s** and
  **17.7 s**.

The frame rate did drop. The wait shrank by roughly a factor of ten. By the
condition written down in advance, the selection stays.

That is not evidence that more pixels caused the improvement. **Two changes went
into the same build**: the format selection and the honest crosshair. The old
crosshair reported "locked" through surfaces where most taps missed, so the
130 s was largely spent in a tap-miss-tap loop that the crosshair change alone
would have ended. Nothing in the data separates the two contributions. That is a
flaw in how the experiment was staged, not a finding about resolution.

A mechanism argues the other way, and it fits the exact scene that failed: the
highest-resolution formats are **non-binned**, so they give up the pixel binning
that suppresses noise in dark areas — and the surface ARKit could not see was a
*black* mousepad. More pixels, each of them noisier, is not obviously more
feature points there.

So: 4K@30 is **unresolved**, not validated and not refuted. A comparison that
settles it has to change exactly one thing.

**`ArVideoFormat.fps` is the format's nominal rate, not a delivered one.** It
comes from `config.videoFormat.framesPerSecond`, read once at `run` and never
touched again: a session that thermally throttles to 20fps still reports 30. Any
screen showing it should say "nominal", and any future measurement that wants
the real rate has to count frames itself — this package does not.

## 0.4.0

A crosshair that says "locked" while a tap would miss is worse than a crosshair
that says nothing. This release removes one such lie and adds the resolution the
old flag was hiding.

* **`ArMeasureSample.aimTarget`** — what the centre ray is hitting right now,
  as an `ArRaycastTarget?`: `existingPlaneGeometry` (a plane ARKit has
  confirmed), `estimatedPlane` (one it guessed around the ray), or `null` for
  nothing at all. `aimLocked` stays as the two-value form of the same probe
  (`aimTarget != null`), so existing code keeps working. Both are derived from
  one raycast; they cannot disagree.
* **The 0.3s unlock grace period is gone.** It was not a debounce: every hit
  re-armed the window, so it behaved as an OR across it. A surface that catches
  once every 0.3s — one probe in three — pinned the crosshair to "locked"
  continuously while most taps missed. Measured on an iPhone 16 Plus (no LiDAR)
  against a table edge on a black mousepad: 130 seconds to land the first point,
  136 for the second, both eventually landing on confirmed plane geometry. The
  quality was never the problem; the waiting was, and the crosshair was
  encouraging it.
* What replaces it is a **sampling grid**, not a hold: the value always comes
  from a real raycast, at most one 10Hz sample old. The grid exists only because
  the probe runs every frame while a live segment is on screen, and a shape that
  changes 60 times a second reads as no state at all. On a marginal surface the
  crosshair now flickers — that flicker is the information the old constant was
  suppressing.
* **`ArMeasureDiagnostics.video`** — `width`, `height` and `fps` of the ARKit
  video format actually in use. It rides on every sample, including samples with
  no points yet, because "why can I not place anything" is a question asked
  before the first point exists.

**Experimental, not yet verified on a device:** the session now selects the
highest-resolution `supportedVideoFormats` entry instead of Apple's default,
on the hypothesis that more pixels yield more feature points on the untextured
surfaces where planes currently refuse to grow. Ties go to the higher frame
rate, and an empty list leaves the default in place. The risk is real and is why
`fps` is reported: the highest-resolution format on some devices runs at 30fps
where the default runs at 60. **If a device run shows the frame rate dropping
without the wait shrinking, revert this.**

Also not verified on a device: whether the honest crosshair reads as broken
rather than informative when a surface only catches intermittently.

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
