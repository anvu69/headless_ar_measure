import 'dart:async';

import 'package:flutter/material.dart';
import 'package:headless_ar_measure/headless_ar_measure.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: MeasureScreen());
}

class MeasureScreen extends StatefulWidget {
  const MeasureScreen({super.key});

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  ArAvailability? _availability;
  ArMeasureController? _controller;
  ArMeasureSample? _sample;
  StreamSubscription<ArMeasureSample>? _sub;
  ArMeasurePlaceResult? _lastPlace;

  @override
  void initState() {
    super.initState();
    // Ask at runtime. A simulator, a host that is not iOS, or a build with no
    // native side registered all land in the same place: arSupported false.
    ArMeasure.isAvailable().then((a) {
      if (mounted) setState(() => _availability = a);
    });
    _sub = ArMeasure.samples.listen((s) {
      if (mounted) setState(() => _sample = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    // iOS has no dispose callback for a platform view, so this explicit
    // channel command is the only thing that turns the camera off on time.
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _place() async {
    final result =
        await _controller?.placePoint() ?? ArMeasurePlaceResult.notReady;
    if (mounted) setState(() => _lastPlace = result);
  }

  /// Three of the four results mean "no point was placed" — and each one asks
  /// the user for something different. A single boolean would collapse them
  /// into one sentence that is wrong two times out of three.
  static String? _placeAdvice(ArMeasurePlaceResult? result) => switch (result) {
    null || ArMeasurePlaceResult.placed => null,
    ArMeasurePlaceResult.missed =>
      'nothing under the crosshair — move slowly around the object '
          'until it locks',
    ArMeasurePlaceResult.notReady => 'not ready yet — see the status above',
    ArMeasurePlaceResult.alreadyComplete =>
      'both points are down — read the number, or undo',
  };

  @override
  Widget build(BuildContext context) {
    final availability = _availability;

    return Scaffold(
      appBar: AppBar(title: const Text('headless_ar_measure')),
      body: availability == null
          ? const Center(child: CircularProgressIndicator())
          : availability.arSupported
          ? _measuring()
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ARKit is not supported on this device.\n'
                  'Simulators always land here — so does any host that is '
                  'not an iPhone or iPad.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }

  Widget _measuring() {
    final sample = _sample;
    final measurement = sample?.measurement;
    final locked = sample?.aimLocked ?? false;
    final advice = _placeAdvice(_lastPlace);

    return Stack(
      fit: StackFit.expand,
      children: [
        ArMeasureView(
          onPlatformViewCreated: (id) =>
              setState(() => _controller = ArMeasureController(id)),
        ),
        // Every label below is drawn here, in Flutter. The package draws
        // nothing — that is the whole point of it being headless.
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: Text(
            [
              'status: ${sample?.status.name ?? '—'}',
              if (measurement != null)
                '${measurement.mm.toStringAsFixed(0)} mm '
                    '± ${measurement.tolMm.toStringAsFixed(0)}',
              ?advice,
            ].join('\n'),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        // The crosshair says what the button is about to do. Without it, a
        // tap that misses is indistinguishable from a dead button — which is
        // exactly how it read on a real device, aimed at a glossy screen.
        Center(
          child: Icon(
            locked ? Icons.add_circle_outline : Icons.add,
            color: locked ? Colors.greenAccent : Colors.white54,
            size: locked ? 44 : 32,
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 24,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              FilledButton(onPressed: _place, child: const Text('Place')),
              OutlinedButton(
                onPressed: () => _controller?.undoPoint(),
                child: const Text('Undo'),
              ),
              OutlinedButton(
                onPressed: () => _controller?.reset(),
                child: const Text('Reset'),
              ),
              OutlinedButton(
                onPressed: () => _controller?.pause(),
                child: const Text('Pause'),
              ),
              OutlinedButton(
                onPressed: () => _controller?.resume(),
                child: const Text('Resume'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
