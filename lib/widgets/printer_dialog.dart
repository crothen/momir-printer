import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import '../services/bluetooth_service.dart';
import '../printers/phomemo_protocol.dart';

class PrinterDialog extends StatefulWidget {
  const PrinterDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const PrinterDialog(),
    );
  }

  @override
  State<PrinterDialog> createState() => _PrinterDialogState();
}

class _PrinterDialogState extends State<PrinterDialog> {
  final _bluetooth = BleManager();
  
  List<fbp.ScanResult> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _connectingTo;
  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _checkBluetoothAndScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _bluetooth.stopScan();
    super.dispose();
  }

  Future<void> _checkBluetoothAndScan() async {
    final available = await _bluetooth.isBluetoothAvailable();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable Bluetooth')),
        );
      }
      return;
    }
    _startScan();
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _devices = [];
    });

    _scanSubscription?.cancel();
    _scanSubscription = _bluetooth.scanForDevices().listen((results) {
      // Filter for likely thermal printers
      final printers = results.where((r) {
        final name = r.device.platformName.toLowerCase();
        return name.isNotEmpty && (
          PhomemoProtocol.matchesDevice(name) ||
          name.contains('print') ||
          name.contains('thermal') ||
          name.contains('pos') ||
          name.startsWith('gt') ||
          name.startsWith('mx')
        );
      }).toList();

      setState(() {
        _devices = printers;
      });
    });

    // Stop after timeout
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isScanning) {
        setState(() => _isScanning = false);
        _bluetooth.stopScan();
      }
    });
  }

  Future<void> _connectTo(fbp.ScanResult result) async {
    setState(() {
      _isConnecting = true;
      _connectingTo = result.device.platformName;
    });

    await _bluetooth.stopScan();
    
    final success = await _bluetooth.connect(result.device);
    
    if (mounted) {
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${result.device.platformName}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _isConnecting = false;
          _connectingTo = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.bluetooth),
          const SizedBox(width: 8),
          const Text('Connect Printer'),
          const Spacer(),
          if (_isScanning)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: _isConnecting
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Connecting to $_connectingTo...'),
                  ],
                ),
              )
            : _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'Searching for printers...'
                              : 'No printers found',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        if (!_isScanning) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Make sure your printer is on',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final name = device.device.platformName;
                      final rssi = device.rssi;
                      
                      return ListTile(
                        leading: Icon(
                          PhomemoProtocol.matchesDevice(name)
                              ? Icons.print
                              : Icons.bluetooth,
                          color: PhomemoProtocol.matchesDevice(name)
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(name),
                        subtitle: Text('Signal: $rssi dBm'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _connectTo(device),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!_isScanning && !_isConnecting)
          TextButton(
            onPressed: _startScan,
            child: const Text('Scan Again'),
          ),
      ],
    );
  }
}
