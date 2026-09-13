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
  headless_ar_measure: ^0.9.0
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
| `ArMeasureController.movePoint(i)` | Moves an already-placed endpoint to where the centre ray is hitting now; returns an `ArMeasureMoveResult` |
| `ArMeasureController.grabPoint(i)` | Takes hold of an endpoint; it follows the crosshair every frame until released. Returns an `ArMeasureGrabResult` |
| `ArMeasureController.releasePoint()` | Lets go and pins the endpoint at the drag's last hit; returns an `ArMeasureReleaseResult` |
| `ArMeasureController.undoPoint()` | Drops the last point |
| `ArMeasureController.reset()` | Drops both points and rebuilds the coordinate system |
| `ArMeasureController.pause()` / `.resume()` | Stops and restarts the camera, keeping both points |
| `ArMeasureController.captureFrame()` | Writes a snapshot of the **scene** — camera feed plus every world-anchored node — to a JPEG in the temp directory and returns its path, or `null` |
| `ArMeasureController.dispose()` | **Required.** Stops the session and turns the camera off |

### The crosshair has to say what it is on

`ArMeasureSample.aimTarget` is what a ray from the centre of the screen is
hitting right now. Four answers, not two:

| `aimTarget` | What a tap would do | What to draw |
|---|---|---|
| `existingPlaneGeometry` | land on a plane ARKit has confirmed | the confident crosshair |
| `estimatedPlane` | land on a plane ARKit just guessed around the ray | a weaker crosshair — placeable, but the depth can be off |
| `existingPlaneInfinite` | land on a plane ARKit has confirmed, **extended past its own boundary** | a distinctly different crosshair, plus `aimOvershootMm` — see "Extrapolation announces itself" |
| `null` | **miss** | the empty crosshair, plus a line telling the user where to aim instead |

`ArMeasureSample.aimLocked` is the older two-value form of the same probe
(`aimTarget != null`), kept so existing code does not have to change. Both come
from one raycast, so they cannot disagree.

`ArMeasureSample.aimPlaneId` rides the same probe and says **which** plane, not
what kind — the piece that lets you warn before the second tap lands on a
different surface. See "Which plane, not just what kind of plane".

This is not polish. Without it, a miss and a broken button look identical: a
real device, aimed at a glossy black tablet screen at close range — reflective,
untextured, near-zero feature points, the worst surface ARKit can be handed —
produced a "Place" button that did nothing at all, with `ready` on screen the
whole time. The ray was missing, correctly; nothing said so.

It is probed with the **same** raycast `placePoint()` uses, and it is live in
the three states where ARKit is tracking normally: `ready`, `firstPointPlaced`
and `measured`. Everywhere else it is `null`.

`measured` joined that list in 0.10.0, and it is a reversal: through 0.9.1 the
flag was documented as always `false` there, because "once both points are down
there is nothing left to aim at". `movePoint()` broke that premise — with two
points down there is still a tap that places a point. See "Moving an endpoint".

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
| `alreadyComplete` | both points are down; read the number, undo, or move an end |

`notReady` is also what you get when the channel cannot answer at all — a
missing plugin, a disposed view. Never `missed`: inviting someone to keep
moving the phone will not revive a dead channel.

### Grazing is a number, and it arrives before the tap

`ArMeasureSample.aimRayAngleDeg` is the angle between the aiming ray and the
**surface** it is currently on: 90° is dead-on, 0° is grazing. Since 0.7.0 it
is sampled on the same raycast, at the same 10Hz, as `aimTarget` and
`aimOvershootMm`.

It exists because grazing is the fastest-growing term in a measurement's
tolerance, and it sits in the *denominator*:

```
ε = d · Δu / (fx · sin θ)
```

At 0.6m with 2px of aiming error, that is 0.83mm at θ=90°, 4.00mm at θ=12° and
9.55mm at θ=5° — and crouching low to sight along a table edge is exactly how
people hold a phone to measure one. `ArPointDiagnostics.rayAngleDeg` has
carried the same number for a placed point since 0.3.0, but a warning built on
that one arrives **after** the tap it should have prevented.

Unlike `aimOvershootMm`, it is meaningful at **every** tier. A ray grazing a
confirmed plane at 4° is still grazing at 4°; gating the angle behind the
extrapolation tier would silence the warning on the tier people trust most. It
is `null` only when the ray hits nothing — there is no surface to measure an
angle against — and on a native build older than the field.

The other half of that formula is `fx`, and the package supplies it too:
`ArMeasureDiagnostics.camera` — see "The lens is not a constant". `d` is
`cameraDistanceMm` for a placed point; there is **no live camera distance** for
an unplaced one, so a pre-tap warning has to substitute its own working range.
`Δu` is yours: the package does not know it, does not compute `ε`, and sets no
threshold. Where "too grazing" falls depends on what the app is measuring —
the same boundary as `overshootMm`.

### Extrapolation announces itself

Since 0.6.0 the ray has a **third** tier, tried last: `.existingPlaneInfinite`,
a plane ARKit has already detected, extended past its own boundary. A point from
that tier is **inferred, not observed** — and this package refused to use it
until 0.6.0, for a reason that still stands: it extends a tabletop straight
through whatever you are actually aiming at and returns a point at *tabletop
height*, and a number that looks normal and is wrong is the worst thing this
package can hand you.

What changed is that the tier is no longer allowed to look normal. Every
tier-three hit carries **how far outside the plane's real boundary it landed**:

| Field | Which ray |
|---|---|
| `ArMeasureSample.aimOvershootMm` | the ray being aimed right now |
| `ArPointDiagnostics.overshootMm` | a point that was already placed |

Both are `null` on the other two tiers, and that `null` is a fact rather than a
gap — a point inside the real boundary, or on a plane ARKit merely estimated,
has no boundary to overshoot. A `0` there would claim a measurement happened.

Read it as a confidence signal, not a distance to display:

- **tens of millimetres** — a table edge the detected boundary has not grown out
  to yet. The extrapolation is roughly as good as the plane it came from.
- **hundreds of millimetres to metres** — the plane has been extended somewhere
  there is nothing. This is the failure case, and this number is the only thing
  that reports it.

**The package sets no threshold, deliberately.** Which overshoot counts as "too
far", and what to do about it — widen the tolerance, refuse to draw a
conclusion, say so in words — depends on what your app measures and what the
number is used for. The package reports which tier and how far past the
boundary; the policy is yours. `tolMm` is unchanged for the same reason.

A hit that cannot state its overshoot is **discarded** and reported as a miss.
That is also how "never extrapolate before any plane exists" is enforced: with
no detected plane there is no anchor to extend, so the hit falls out on its own.

On screen the package draws the two kinds of endpoint differently: a filled dot
for an observed point, an open ring for an extrapolated one — same size, same
ink. The difference is shape rather than colour because the scene has no lights,
so a second colour would have to glow, and a glowing colour on a camera feed
reads as an error rather than as lower confidence. Shape also survives
colour-blindness and greyscale, and it can be read on one endpoint alone instead
of needing both on screen to compare.

Since `0.13.0` `captureFrame()` snapshots the scene, so a saved photo carries
that distinction by itself — the ring is a node like everything else. If you
want the tier in *text*, it is on the samples stream:
`diagnostics.points[i].target` for each placed end, `aimTarget` for the live
one. `ArMeasure.overlay` deliberately does not repeat the tier: it would be a
second path saying the same thing at a different rate, and two such paths drift
apart.

Why the reversal happened at all: on a real device the raw feature-point cloud
for the whole frame held **26 points, sometimes 2** — around the ray, **1,
sometimes 0**. That is not enough material for any plane fit, so the choice was
never "extrapolate or measure correctly". It was extrapolate with a label, or
measure nothing.

### Which plane, not just what kind of plane

Since 0.8.0 every hit carries the identity of the `ARPlaneAnchor` it landed on:

| Field | Which ray |
|---|---|
| `ArMeasureSample.aimPlaneId` | the ray being aimed right now |
| `ArPointDiagnostics.planeId` | a point that was already placed |

It exists because two real-device failures walked straight through every other
diagnostic field. An endpoint left floating on a wall was sitting on the
*tabletop* plane extended nearly two metres — `planeAlignment` `horizontal`,
identical to the first point. Points that snapped below the table legs were on
the *floor*, because the tabletop had not been detected yet — and floor and
tabletop are **both horizontal**. Same alignment, same tier, extents that
conclude nothing. Comparing identities is the only thing that separates them.

It is an **opaque string, compared for equality only.** Do not parse it, display
it, or persist it across sessions: ARKit regenerates every plane identity each
session, so two sessions are not comparable.

`null` means **there is no plane** — a different claim from *there is one, and
it is a different one*, and your code has to keep those apart. It arrives on
three routes: the hit landed on `estimatedPlane` (that tier fits a plane from the
geometry around the ray and anchors it to nothing), a native build older than the
field, or an empty string, which is rejected at the door because `'' == ''` would
make any two points read as the same plane.

**It is the identity at placement time, and nothing rewrites it.** ARKit
**merges** planes: two anchors become one and the swallowed one is removed, so an
identity stored at tap time can point at a plane that no longer exists. The
package does not chase merges, because ARKit never says *which* plane absorbed
the removed one — reconstructing that needs a geometric guess, and a wrong guess
prints exactly the words "same plane", silently. A stale but honest answer beats
that.

The consequence to design for: after a merge, two points on what is physically
one tabletop may report two identities. That is a false alarm, and it is the safe
direction — you can see it and decide. The other direction cannot be seen at all.

**The package draws no conclusion.** Whether two identities mean "same surface"
depends on what you are measuring, the same boundary `overshootMm` draws. The
package reports which plane; the policy is yours.

### The segment is live before the second tap

Once the first point is down, the package draws a segment from it to whatever
the centre ray is currently hitting, refreshed every ARKit frame — the way
Apple's Measure app behaves. When the ray has been hitting nothing for **more
than about 100 ms**, the segment is **not drawn at all**; a segment left
standing where the last hit was reads as a finished measurement.

That 100 ms window is deliberate, and 0.9.1 added it. The live end is a fresh
raycast sixty times a second, and two things ride on it: single frames where the
ray misses, and consecutive frames that resolve against *different surfaces*
because the three raycast tiers are tried in order. Dropping the segment on the
first miss turns a hit-miss-hit sequence into a **flicker** at the endpoint,
which is what it looks like on a device — not "the ray is missing". So the live
end is held briefly across dropouts and lightly smoothed (0.03 s time constant,
roughly a centimetre of lag while panning, zero once the hand stops).

Two things this does *not* touch. The promise "tap now and it will land" is
`aimLocked` / `aimTarget` on the samples stream, and those still go to `null` on
the miss, on their own 10Hz grid — the hold does not swallow a warning. And
`placePoint()` fires its own ray at the moment of the tap, so neither the hold
nor the smoothing moves the point you actually place.

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

### Moving an endpoint

Two points down and one of them landed a few millimetres off. Re-measuring both
ends to fix one is the wrong price, and the obvious alternative — a pair of
+/- buttons that nudge the *number* — is worse. From a real device:

> when the two ends are chosen a plus/minus button appears, but it **confuses
> the user to change the number while the point on screen does not move**

A number and a picture describing the same segment, disagreeing, on one screen.
`movePoint(i)` inverts the causality: the user moves the point, and the number
changes **because the picture changed**.

```dart
// The app decides *when* to offer this. The package only performs it.
switch (await controller?.movePoint(1)) {
  case ArMeasureMoveResult.moved:        // haptic; the number is already new
  case ArMeasureMoveResult.missed:       // "move around until it locks" — the old point is intact
  case ArMeasureMoveResult.noSuchPoint:  // your bug, or a race with undoPoint()
  case ArMeasureMoveResult.notReady || null: // the status already says why
}
```

**Valid indices are the ones that name a point that exists** — `0` with one
point down, `0` and `1` with two, nothing at all before the first tap. Not
"there must be two points": the package does not know when your app offers the
control, and a placed point is a placed point even while the other end is still
chasing the crosshair. The order is placement order, the same order as
`diagnostics.points` and as `pointA`/`pointB`.

**A miss leaves the old point exactly where it was.** That is contract, not an
implementation detail: destroying a correctly placed endpoint to pay for an
operation that *did not happen* is the worst outcome available, and it arrives
precisely when the user is aiming at a difficult surface.

**The provenance travels with the new point, whole.** Tier, overshoot, plane
identity, grazing angle, camera distance and tracking state all describe the
move, measured at the tap. None of the old tap survives. This is the part that
is easy to get wrong and expensive to get wrong: a point that moves onto a
different plane while still reporting the old plane's identity makes every
honest signal in this package lie, in numbers that look completely valid.

**The moved point does not go through the live-endpoint filter.** It fires a
fresh ray at the moment of the tap, exactly like `placePoint()`. The filter
exists for a point redrawn sixty times a second, and it costs latency —
10.8 mm while panning at 0.48 m/s — which has no business inside a settled
point. Its 100 ms hold would be worse still: it would let a *missing* ray return
a stale coordinate, and the call would report `moved` for a move that never
happened.

**The package does not decide when a move is allowed.** "Snap to the endpoint
the crosshair is near" is your call, and you already have everything for it:
`ArMeasure.overlay` gives both endpoints in screen points, and the crosshair
sits at the centre of the `ArMeasureView` you laid out. There is deliberately no
"which endpoint is being aimed at" field — it would be a second source of truth
about screen geometry (some layouts push the crosshair above a bottom sheet),
and it would force the package to pick a proximity threshold, which is the one
thing it does not know enough to pick. An endpoint that is `null` leaves no gap
in that comparison: a point with no screen coordinate cannot be the one near the
crosshair.

### Grab, drag, let go

`movePoint(i)` was the right causality and the wrong gesture. From a real
device:

> aiming the crosshair at an endpoint brings up this "Move this end" function.
> But it is **unpleasant** to use — it is not grabbing that point and dragging
> until you let go; pressing "Move this end" **only nudges it one step**. It has
> to actually feel **like adjusting the two ends of a tape measure**.

`movePoint` is one stroke. A tape measure is a span.

```dart
await controller?.grabPoint(1);     // from the next frame it follows the crosshair
// …the user pans the device. Nothing crosses the channel…
await controller?.releasePoint();   // pinned at the last hit; provenance recomputed
```

`movePoint` is unchanged and not deprecated — one stroke and one span are two
gestures, and both end at the same commit.

**Do not build the span out of repeated `movePoint` calls.** It draws the same
picture, so it has no symptom other than the battery bill: thirty channel
round-trips a second, thirty `ARAnchor` remove-and-add pairs pushed into the
ARKit session, and thirty results nobody reads. The span runs in Swift, on the
raycast the reticle probe already fired for that frame — a second ray would
disagree with the first, and the point would go somewhere the crosshair did not
promise.

**A losing ray freezes the end; it does not drop it.** A tape measure does not
lose its end when your hand covers the marks. `grabAimLocked` reports the miss,
for the span's own ray — and while the span rides the crosshair (the default),
it says the same thing `aimLocked` does, because it is the same ray.

**Release pins the drag's last hit, not the smoothed trail you were watching,
and not a fresh ray fired at the release frame.** Committing the smoothed
position makes position and provenance disagree by the filter's lag — drag
across a plane boundary, let go promptly, and the point *stands* on one plane
while *declaring* the other. Firing a fresh ray means one missed frame at that
instant throws away the whole drag.

**Provenance is recomputed at release and belongs to the final position** —
tier, overshoot, plane identity, grazing angle, camera distance — measured at
the frame that put the point there, not rebuilt when you let go (the camera has
moved since; a rebuilt `rayAngleDeg` is an angle nobody ever fired). Mid-drag,
every provenance is provisional; do not read `diagnostics` from a sample inside
a span as a conclusion.

**The session lets go by itself** on `pause()`, `dispose()`, `undoPoint()`,
`movePoint()` and on interruptions (a call, Control Center, backgrounding) —
those commit. `reset()` and ARKit removing the anchor drop the grab **without**
committing, because the point it names has stopped existing.

**Read `ArMeasureSample.grabbedPointIndex`** rather than remembering what
`grabPoint` returned. It is the only source that also reports those automatic
releases; an app keeping its own copy goes on drawing "holding end A" for a span
that ended. It is deliberately not gated on `status` — a grab is a state of the
session, not of a raycast, and gating it would make your release button vanish
during half a second of hand tremor.

### The drag can follow your finger

By default a span rides the crosshair: the endpoint goes where the middle of the
screen points, and you move it by moving the device. That is half of the gesture
people expect. The other half, from a real device:

> aim the crosshair at the endpoint, then **hold your finger on the screen and
> drag** to a new place — or hold the finger still and **pan the camera**, and
> the endpoint follows that too.

Hand the package the screen point and it fires the span's ray from there:

```dart
// onPanStart, at the handle the app drew from ArMeasure.overlay
await controller?.grabPoint(1, at: details.localPosition);

// onPanUpdate — call it as often as the finger moves
await controller?.dragTo(details.localPosition);

// onPanEnd
await controller?.releasePoint();
```

**`at` and `dragTo` take points (logical pixels), in the AR surface's own
coordinate space, origin top-left** — the same space and unit as
`ArMeasureOverlay.pointA`/`pointB`. An `Offset` you read off the overlay can be
handed straight back. Do **not** multiply by `devicePixelRatio`: the package
divided its projected output by the screen scale from `0.2.0` to `0.9.0`, the
label hung off the segment by an integer factor on two devices with two
different scales, and the whole file has been in points ever since.

**This is not the repeated-`movePoint` trap.** That one is expensive because
every call is a raycast plus an `ARAnchor` remove-and-add. `dragTo` writes one
`CGPoint` into the grab state — no ray, no anchor, no sample emitted. The ray
still fires once per **frame**, whether you called ten times between two frames
or none.

**Do not compute the 3-D point in Dart.** Where an endpoint belongs is the
intersection of a *ray* with a *real plane in the scene*. Deriving it from how
far the finger slid is a 2-D interpolation standing in for a 3-D problem:
correct when the plane faces the ray, wrong in proportion to the angle, and
worst at exactly the grazing shot this package already ships a warning for
(`aimRayAngleDeg`).

**A finger off the edge of the surface is clamped to the edge, not treated as a
miss**, and `dragTo` returns `ArMeasureDragResult.clamped` to say so. Freezing
instead would kill the second half of the gesture — a pinned finger could no
longer drag the endpoint by panning. And firing from *outside* the viewport,
which looks like the honest option, is the worst of the three: that ray points
somewhere the camera has never observed, so neither the geometry tier nor the
estimated-plane tier has anything to hit, and the only tier left to answer is
extrapolation — a detected plane stretched past its own boundary, returning a
perfectly plausible coordinate on a surface the camera cannot see.

**Read `grabAimLocked`, not `aimLocked`, for a finger-driven span.** From
`0.14.0` those two flags describe **two different rays** the moment a span has
its own aim point: `aimLocked` is about the middle of the screen — where
`placePoint()` would land — and `grabAimLocked` is about where the endpoint is
being dragged. They coincide only in the default case, a `grabPoint` with no
`at`.

**The crosshair, `placePoint` and `movePoint` are untouched.** A tap still lands
where the crosshair points, whatever the finger is doing. This is an added path,
not a changed one.

**The aim point lives and dies with the span.** It is a field of the grab state,
so `releasePoint()` erases it — and so does every route the package releases on
by itself. There is no `aimAt(null)` to forget, because there is no independent
lifetime to forget it in; the alternative, a session-level aim that outlives the
grab, hands the *next* span the *previous* finger's position on its very first
frame. There is also no way back to the crosshair mid-span: let go and grab
again without `at`, which is the honest description of what that is anyway.

**Only a crosshair-riding span forces the probe to run every frame.** A span
with its own aim point fires its own ray in the drag step, so the crosshair
drops back to its 10 Hz sampling grid instead of costing a second raycast per
frame that nothing reads.

**The smoothing filter stays, for both kinds of span.** The noise it exists to
kill is tier switching — three ray tiers tried in order, so two consecutive
frames can return two different *surfaces*, both reporting a hit, and the point
jumps centimetres while the hand *and* the finger sit still. That is true
wherever on screen the ray starts. The other noise, hand tremor, does not go
away either: the second half of this very gesture is *hold the finger and pan
the camera*. And the filter's lag (τ = 0.03 s) never reaches the committed
point, because release pins the raw last hit, not the smoothed trail — the
filter is paid for by the eye, not by the measurement.

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
| `rayAngleDeg` | the ray's angle **to the surface**: 90° is dead-on, 0° is grazing. `ArMeasureSample.aimRayAngleDeg` is the same number for the ray you are aiming *now* |
| `planeId` | **which** plane was hit — an opaque identity, for equality only. `null` on an estimated plane, because that tier has no anchor. See below |
| `planeAlignment`, `planeWidthMm`, `planeHeightMm` | the `ARPlaneAnchor` that was hit, if any. All three `null` when the hit landed on an estimated plane |
| `overshootMm` | how far outside that plane's real boundary the point landed. Non-`null` **only** at `existingPlaneInfinite` — see below |

`ArMeasureDiagnostics.video` sits beside those points and describes the whole
session rather than one tap: the `width`, `height` and `fps` of the ARKit video
format actually running. It is present **before any point exists**, which is
when you most need it — that is the moment someone is asking why nothing can be
placed. See "The video format is chosen, not defaulted" below.

`ArMeasureDiagnostics.features` sits there for the same reason and is present at
the same moments, but it is an **instrument, not a feature**: `total` counts
every point in the current frame's `rawFeaturePoints`, and `nearRay` counts how
many of those fall inside a 10° cone around the centre ray, 0.2–3m out. It exists
to answer one open question — when the raycast misses continuously, is there any
material a plane fit could use? — and it is expected to be removed once that is
answered. `0` and `null` mean different things: `0` is an empty cloud, `null` is
a build that was not asked. See the 0.5.0 CHANGELOG entry, which carries the
reasoning behind all three constants and the emit-rate cost.

`ArMeasureDiagnostics.camera` (0.7.0) sits there too and is the one block that
is **never** gated by session state: it describes the device, not an aim, and
you need it most at the two moments the aim gates would cut — once both points
are down, and before any point exists. See "The lens is not a constant".

Why it exists: a tile edge measured 382mm against a true 400, two tiles measured
795 against 800, and every explanation anyone proposed fitted both numbers
equally well — because the sample said nothing about the conditions either point
was placed under. None of this feeds the distance calculation. It is a recording
layer, and it says what the machine did.

Every field is nullable on purpose. No camera frame, a value ARKit adds in a
later iOS, an older native build — all of it comes back `null` rather than a
plausible default, because a plausible default here is manufactured evidence.

### The measurement label lives in the scene

```dart
final png = await drawYourLabel();           // your fonts, your colours
await controller.setLabel(ArLabelImage(
  png: png,
  pixelRatio: MediaQuery.devicePixelRatioOf(context),
));
```

The package sticks that image on a node centred on the segment. It does not know
what the image says — the design system, the font file and every product concept
stay in your app.

Why it cannot be a Flutter overlay: the line and the dots are nodes in the
SceneKit scene, so ARKit moves them with the camera every frame. A number drawn
from projected coordinates runs on a different clock (the overlay channel is
capped at 30 Hz, SceneKit renders at 60) — it stutters against the line it sits
on, it is never part of that line, and it vanishes when one endpoint falls
behind the camera while SceneKit keeps drawing the rest of the segment.

The node turns about the segment's own axis to face you, flips half a turn
before the text would read upside down (with ±8° of hysteresis, or the text
jumps in a shaking hand), and holds a constant size on screen between **0.30 m
and 3.00 m**, falling off as `clamp / distance` outside that band. Nothing reads
or writes the depth buffer, and `renderingOrder` puts the label over the line —
in 3D, "drawn later" alone is not enough.

Pass `null` to take it off.

`ArMeasureOverlay.label` reports where the node ended up — centre, screen
rotation (flip included), scale. It is a statement, not a request. Its original
reader was a composed photo redrawing the label by hand; since `0.13.0` that
reader is gone, and the field stays for callers who want to put something of
their own next to the number on screen.

### A captured photo is a snapshot of the scene

`captureFrame()` writes the **scene** to a JPEG in the temp directory: the
camera feed plus every world-anchored node — the segment, both endpoints, and
the label image if you set one. What the user just looked at, by definition,
rather than by reconstruction.

Through `0.12.0` this returned a bare camera frame and you composed the drawing
yourself. That made sense while the number lived in your Flutter layer. Once the
number became a node (`setLabel`, `0.12.0`), a bare frame forced you to keep a
**second implementation** of the same drawing, with its own bugs and its own
tests to keep the two from drifting. `0.13.0` deletes that asymmetry.

What does *not* land in the photo: Apple's coaching overlay, because
`ARCoachingOverlayView` is a **subview** and `SCNView.snapshot()` renders the
scene rather than the UIView tree; and everything your app draws in Flutter
above `ArMeasureView` — reticle, buttons, text. The scene holds measurement
nodes and nothing else.

Two properties, both unchanged:

* the image is the size of the **viewport** times the screen scale — so the
  point coordinates from `ArMeasure.overlay` map onto it with a single multiply.
  That is smaller than the sensor's full 12MP (about 3.6MP against 8.3MP on a
  2× iPad): a deliberate trade, pixels for fidelity;
* the rotation is baked into the **pixels**, not written as an EXIF orientation
  flag. The file is upright in any viewer, not only the ones that read the flag.

The snapshot runs on the main thread — `SCNView.snapshot()` reaches straight
into the view's renderer, and calling it from anywhere else throws nothing and
returns black.

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

### The video format is chosen, not defaulted

The session does not take Apple's default entry of
`ARWorldTrackingConfiguration.supportedVideoFormats`. Since 0.9.0 it picks the
**highest frame rate**, and among the formats tied at that rate, the one with
the most pixels. An empty list leaves the default alone.

**This is the second criterion, and the first one was the opposite.** 0.4.0
picked the highest *resolution*, breaking ties on frame rate, on the hypothesis
that more pixels mean more feature points on the poorly textured surfaces where
planes refuse to grow. Read the order of events before changing it back, because
it is easy to misremember in either direction:

* 0.4.0 wrote its own revert condition down before there was any data: *"If a
  device run shows the frame rate dropping without the wait shrinking, revert
  this."* The device run landed on 3840×2160 at 30fps. The frame rate did drop —
  **and the wait shrank**, from 130 s to 7.8 s for the first point. By the
  condition written in advance, the experiment was not up for revert, and
  0.4.1 says so.
* 0.9.0 changes it anyway, on a symptom that condition did not cover: with a
  point down, the **live segment stutters as the phone pans**. That segment is
  drawn in SceneKit, so the only thing that can make it smooth is frame rate —
  at 30fps every step it takes is 33ms wide.
* A control observation, offered as a fact and not as a clean experiment: the
  same build on an iPad Air M3 selected 1920×1440 @ 60fps — a different format
  list — and the stutter was not reported there. Two different devices differ in
  more than one way.

**None of this concludes anything about resolution.** Whether 4K helped the
130 s → 7.8 s fall is still unknown: the same build also shipped the honest
crosshair, and nothing separates the two contributions. 4K@30 was never
validated and has not been refuted. What 0.9.0 settles is only the *order*: when
frame rate and pixel count disagree, frame rate wins.

The second tier is not decoration. Two formats at the same rate give SceneKit
the same smoothness, so the only thing left to tell them apart is how much image
ARKit gets to pull feature points from — without that tier, a device offering
both 1280×720@60 and 1920×1440@60 would run the smaller one for nothing.

The criterion lives in `VideoFormatChoice.swift`, which imports `Foundation` and
nothing else, so it compiles and runs on macOS and has a numeric test
(`test/video_format_choice_test.dart`) driving it with synthetic format lists.
`ARVideoFormat` cannot be constructed by hand and `supportedVideoFormats` is
whatever device you are holding — a criterion written directly against them can
only be checked by owning the right phone.

**The same caveat applies to this change as to the last one.** If the app on top
also changes how it draws the segment in the same build, the two are confounded
again and neither can be credited. Change one thing.

`fps` here is the format's **nominal** rate — read from
`config.videoFormat.framesPerSecond` once at `run`, never updated. A session
throttled down to 20fps still reports 30, and after 0.9.0 the gap is *wider*,
not narrower: the number will usually say 60 now, while a busy scene or a warm
device delivers less. If you need the delivered rate, count frames yourself —
this package does not.

### The lens is not a constant

`ArMeasureDiagnostics.camera` (0.7.0) carries `fx` — focal length in **pixels**,
`ARFrame.camera.intrinsics[0][0]` — alongside the `width` and `height` of the
frame it was read from. Both come off one `ARCamera`, in one statement.

`fx` is the other denominator of `ε = d · Δu / (fx · sin θ)`. Without it an app
cannot compute a millimetre of tolerance, and the only thing left is a guess.

**Do not hardcode it.** 1442 — the number every article about iOS devices quotes
— is the focal length of the 1920×1440 format. This package chooses its own
format, and that choice has already moved once: up to 0.8.0 it took the largest
format (3840×2160 on the device measured, so `fx` was nearly double), and from
0.9.0 it prefers frame rate, which on that same device selects something
smaller. A constant pinned to either release is wrong on the other, and both
wrong answers land within a few plausible-looking millimetres. `fx` also drifts
*within* a session, because the package enables autofocus.

That is why `width` and `height` ship in the same block and are **not** borrowed
from `ArMeasureDiagnostics.video`. That block is a snapshot of the format that
was *asked for*, taken once at `run`; this one is the frame that actually
*arrived*, and it is the pixel coordinate system `intrinsics` is expressed in.
ARKit does not promise the two agree. Reading `fx` against the wrong width is a
wrong division whose answer is still a plausible number of millimetres.

One unit trap while you are here: `fx` is in image pixels. Measuring `Δu` in
Flutter points and dividing by it is off by a whole `devicePixelRatio`.

`fx` is deliberately **outside** the sample coalescer. Autofocus nudges it
almost every frame, so putting it in would turn the status channel into a 60Hz
firehose for a number nobody watches in real time — you read it once and put it
in a formula. It rides along on samples already being emitted, exactly like
`video`.

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
