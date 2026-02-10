import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config_store.dart';
import '../core/moonraker_config.dart';
import '../data/moonraker/moonraker_repository.dart';
import '../state/printer_controller.dart';
import 'fluidd/dashboard_page.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _host = TextEditingController(text: '172.31.204.78');
  final _port = TextEditingController(text: '7125');
  final _apiKey = TextEditingController(text: '');
  StatusProfile _profile = StatusProfile.basic;
  bool _useHttps = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final loaded = await ConfigStore().load();
    if (!mounted || loaded == null) return;

    final (cfg, profile) = loaded;
    _host.text = cfg.host;
    _port.text = cfg.port.toString();
    _apiKey.text = cfg.apiKey ?? '';
    _useHttps = cfg.useHttps;
    setState(() {
      _profile = profile;
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final config = MoonrakerConfig(
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
        useHttps: _useHttps,
      );

      final controller = context.read<PrinterController>();
      await controller.connect(config, profile: _profile);
      await ConfigStore().save(config, _profile);

      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DashboardPage()));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to Moonraker')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Host/IP'),
            ),
            TextField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _apiKey,
              decoration: const InputDecoration(
                labelText: 'API Key (optional)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<StatusProfile>(
              initialValue: _profile,
              items: StatusProfile.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _profile = v ?? _profile),
              decoration: const InputDecoration(labelText: 'Profile'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _connect,
                child: Text(_busy ? 'Connecting...' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
