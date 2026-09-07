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

  @override
  void initState() {
    super.initState();
    // Ask at runtime. There is no native implementation wired up yet at this
    // stage of the package, so this always resolves through the
    // "missing plugin" fallback — that is expected, not a bug.
    ArMeasure.isAvailable().then((a) {
      if (mounted) setState(() => _availability = a);
    });
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;

    return Scaffold(
      appBar: AppBar(title: const Text('headless_ar_measure')),
      body: Center(
        child: availability == null
            ? const CircularProgressIndicator()
            : availability.arSupported
            ? const ArMeasureView()
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ARKit is not supported on this device.\n'
                  'Simulators always land here — so does a build with no '
                  'native implementation wired up yet.',
                  textAlign: TextAlign.center,
                ),
              ),
      ),
    );
  }
}
