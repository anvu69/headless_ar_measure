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
  bool _lastPlaceMissed = false;

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
    final ok = await _controller?.placePoint() ?? false;
    if (mounted) setState(() => _lastPlaceMissed = !ok);
  }

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
              if (_lastPlaceMissed) 'last tap hit nothing — aim at a surface',
            ].join('\n'),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        const Center(child: Icon(Icons.add, color: Colors.white, size: 32)),
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
