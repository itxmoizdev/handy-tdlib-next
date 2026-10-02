import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:handy_tdlib_next/handy_tdlib_next.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmokeTestApp());
}

class SmokeTestApp extends StatelessWidget {
  const SmokeTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: SmokeTestPage(),
    );
  }
}

class SmokeTestPage extends StatefulWidget {
  const SmokeTestPage({super.key});

  @override
  State<SmokeTestPage> createState() => _SmokeTestPageState();
}

class _SmokeTestPageState extends State<SmokeTestPage> {
  final _log = StringBuffer();
  bool _running = false;

  void _append(String line) {
    setState(() {
      _log.writeln(line);
    });
  }

  Future<void> _runSmokeTest() async {
    if (_running) return;
    setState(() {
      _running = true;
      _log.clear();
    });

    try {
      _append('1) TdPlugin.initialize()...');
      await TdPlugin.initialize();
      _append('   OK — libtdjson loaded');

      _append('2) tdCreateClientId()...');
      final clientId = TdPlugin.instance.tdCreateClientId();
      _append('   clientId = $clientId');

      _append('3) tdExecute(SetLogVerbosityLevel)...');
      final syncJson = TdPlugin.instance.tdExecute(
        const SetLogVerbosityLevel(newVerbosityLevel: 1).toString(),
      );
      _append('   raw = $syncJson');
      final syncObject = convertJsonToObject(syncJson);
      _append('   parsed = ${syncObject?.currentObjectId}');

      _append('4) tdSend(GetMe) + tdReceive...');
      const extra = 42;
      TdPlugin.instance.tdSend(
        clientId,
        jsonEncode(const GetMe().toJson(extra)),
      );

      String? received;
      for (var i = 0; i < 5; i++) {
        received = TdPlugin.instance.tdReceive(1);
        if (received != null) break;
      }
      _append('   raw = $received');
      final receivedObject = convertJsonToObject(received);
      _append(
        '   parsed = ${receivedObject?.currentObjectId}'
        ' extra=${receivedObject?.extra}',
      );

      _append('');
      _append('Smoke test finished.');
      _append(
        'Note: GetMe may return an error until TDLib is authorized — '
        'that still means send/receive works.',
      );
    } catch (e, st) {
      _append('');
      _append('FAILED: $e');
      _append('$st');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('handy_tdlib_next smoke test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _running ? null : _runSmokeTest,
              child: Text(_running ? 'Running...' : 'Run smoke test'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  _log.isEmpty
                      ? 'Tap the button on an Android emulator/device.\n'
                          'macOS/Chrome will fail — this package is Android-only.'
                      : _log.toString(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
