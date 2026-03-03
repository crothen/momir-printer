import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// Represents a connected printer with its characteristics
class ConnectedPrinter {
  final fbp.BluetoothDevice device;
  final fbp.BluetoothCharacteristic writeCharacteristic;
  final fbp.BluetoothCharacteristic? notifyCharacteristic;
  final StreamSubscription<fbp.BluetoothConnectionState> connectionSubscription;
  
  ConnectedPrinter({
    required this.device,
    required this.writeCharacteristic,
    this.notifyCharacteristic,
    required this.connectionSubscription,
  });
  
  String get name => device.platformName;
  String get id => device.remoteId.str;
  
  /// Get info about the characteristic for debugging
  String get characteristicInfo {
    final svcFull = writeCharacteristic.serviceUuid.toString().toLowerCase();
    final charFull = writeCharacteristic.uuid.toString().toLowerCase();
    final svc = svcFull.length >= 8 ? svcFull.substring(4, 8) : svcFull;
    final char = charFull.length >= 8 ? charFull.substring(4, 8) : charFull;
    final notify = notifyCharacteristic != null ? ', notify: on' : '';
    return 'Svc: $svc, Char: $char$notify';
  }
  
  /// Write data to this printer
  Future<bool> write(Uint8List data) async {
    try {
      final useWithoutResponse = writeCharacteristic.properties.writeWithoutResponse;
      const chunkSize = 120;
      
      for (var i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize > data.length) ? data.length : i + chunkSize;
        final chunk = data.sublist(i, end);
        
        await writeCharacteristic.write(chunk, withoutResponse: useWithoutResponse);
        
        if (end < data.length) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Manages BLE connections to multiple thermal printers
class BleManager {
  static final BleManager _instance = BleManager._internal();
  factory BleManager() => _instance;
  BleManager._internal();

  // Connected printers
  final List<ConnectedPrinter> _printers = [];
  ConnectedPrinter? _selectedPrinter;

  // State streams
  final _printersController = StreamController<List<ConnectedPrinter>>.broadcast();
  Stream<List<ConnectedPrinter>> get printersStream => _printersController.stream;
  
  final _selectedController = StreamController<ConnectedPrinter?>.broadcast();
  Stream<ConnectedPrinter?> get selectedStream => _selectedController.stream;

  // Getters
  List<ConnectedPrinter> get connectedPrinters => List.unmodifiable(_printers);
  ConnectedPrinter? get selectedPrinter => _selectedPrinter;
  int get printerCount => _printers.length;
  bool get hasConnectedPrinter => _printers.isNotEmpty;
  
  // Legacy compatibility getters
  BleConnectionState get currentState => 
      _printers.isNotEmpty ? BleConnectionState.connected : BleConnectionState.disconnected;
  fbp.BluetoothDevice? get connectedDevice => _selectedPrinter?.device;
  String? get connectedDeviceName => _selectedPrinter?.name;
  String? get connectedCharacteristicInfo => _selectedPrinter?.characteristicInfo;
  
  // Legacy compatibility stream
  Stream<BleConnectionState> get connectionState => 
      _printersController.stream.map((list) => 
          list.isNotEmpty ? BleConnectionState.connected : BleConnectionState.disconnected);

  /// Check if Bluetooth is available and on
  Future<bool> isBluetoothAvailable() async {
    final supported = await fbp.FlutterBluePlus.isSupported;
    if (!supported) return false;
    
    final state = await fbp.FlutterBluePlus.adapterState.first;
    return state == fbp.BluetoothAdapterState.on;
  }

  /// Start scanning for BLE devices
  Stream<List<fbp.ScanResult>> scanForDevices({Duration timeout = const Duration(seconds: 10)}) {
    fbp.FlutterBluePlus.stopScan();
    
    fbp.FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );
    
    return fbp.FlutterBluePlus.scanResults;
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  /// Check if a device is already connected
  bool isConnected(fbp.BluetoothDevice device) {
    return _printers.any((p) => p.id == device.remoteId.str);
  }

  /// Connect to a BLE device (adds to list, doesn't replace)
  Future<bool> connect(fbp.BluetoothDevice device) async {
    // Already connected?
    if (isConnected(device)) {
      // Just select it
      _selectedPrinter = _printers.firstWhere((p) => p.id == device.remoteId.str);
      _selectedController.add(_selectedPrinter);
      return true;
    }
    
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      
      final services = await device.discoverServices();
      final writeChar = _findWriteCharacteristic(services);
      
      if (writeChar == null) {
        await device.disconnect();
        return false;
      }
      
      final notifyChar = _findNotifyCharacteristic(services);
      if (notifyChar != null) {
        try {
          await notifyChar.setNotifyValue(true);
        } catch (e) {
          // Ignore
        }
      }
      
      final subscription = device.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _handleDisconnection(device.remoteId.str);
        }
      });
      
      final printer = ConnectedPrinter(
        device: device,
        writeCharacteristic: writeChar,
        notifyCharacteristic: notifyChar,
        connectionSubscription: subscription,
      );
      
      _printers.add(printer);
      
      // Auto-select if it's the first printer
      if (_selectedPrinter == null) {
        _selectedPrinter = printer;
        _selectedController.add(_selectedPrinter);
      }
      
      _printersController.add(_printers);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Select a printer by its device ID
  void selectPrinter(String deviceId) {
    final printer = _printers.cast<ConnectedPrinter?>().firstWhere(
      (p) => p?.id == deviceId,
      orElse: () => null,
    );
    if (printer != null) {
      _selectedPrinter = printer;
      _selectedController.add(_selectedPrinter);
    }
  }
  
  /// Select a printer directly
  void selectPrinterDirect(ConnectedPrinter printer) {
    if (_printers.contains(printer)) {
      _selectedPrinter = printer;
      _selectedController.add(_selectedPrinter);
    }
  }

  fbp.BluetoothCharacteristic? _findWriteCharacteristic(List<fbp.BluetoothService> services) {
    // Priority 1: Cat printer service 0xAE30, characteristic 0xAE01
    for (final svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();
      if (svcUuid.contains('ae30')) {
        for (final char in svc.characteristics) {
          final charUuid = char.uuid.toString().toLowerCase();
          if (charUuid.contains('ae01') && 
              (char.properties.write || char.properties.writeWithoutResponse)) {
            return char;
          }
        }
      }
    }
    
    // Priority 2: Phomemo T02 uses service 0xff00, characteristic 0xff02
    for (final svc in services) {
      for (final char in svc.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid.contains('ff02')) {
            return char;
          }
        }
      }
    }
    
    // Priority 3: Generic printer characteristics
    for (final svc in services) {
      for (final char in svc.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid.contains('ae01') || uuid.contains('ae02')) {
            return char;
          }
        }
      }
    }
    
    // Fallback: find any writable characteristic
    for (final svc in services) {
      for (final char in svc.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          return char;
        }
      }
    }
    
    return null;
  }

  fbp.BluetoothCharacteristic? _findNotifyCharacteristic(List<fbp.BluetoothService> services) {
    for (final svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();
      if (svcUuid.contains('ae30')) {
        for (final char in svc.characteristics) {
          final charUuid = char.uuid.toString().toLowerCase();
          if (charUuid.contains('ae02') && char.properties.notify) {
            return char;
          }
        }
      }
    }
    return null;
  }

  /// Disconnect a specific printer
  Future<void> disconnectPrinter(String deviceId) async {
    final index = _printers.indexWhere((p) => p.id == deviceId);
    if (index == -1) return;
    
    final printer = _printers[index];
    printer.connectionSubscription.cancel();
    
    if (printer.notifyCharacteristic != null) {
      try {
        await printer.notifyCharacteristic!.setNotifyValue(false);
      } catch (e) {
        // Ignore
      }
    }
    
    await printer.device.disconnect();
    _printers.removeAt(index);
    
    // Update selected printer if needed
    if (_selectedPrinter?.id == deviceId) {
      _selectedPrinter = _printers.isNotEmpty ? _printers.first : null;
      _selectedController.add(_selectedPrinter);
    }
    
    _printersController.add(_printers);
  }

  /// Disconnect all printers (legacy compatibility)
  Future<void> disconnect() async {
    for (final printer in List.of(_printers)) {
      await disconnectPrinter(printer.id);
    }
  }

  void _handleDisconnection(String deviceId) {
    final index = _printers.indexWhere((p) => p.id == deviceId);
    if (index == -1) return;
    
    _printers[index].connectionSubscription.cancel();
    _printers.removeAt(index);
    
    if (_selectedPrinter?.id == deviceId) {
      _selectedPrinter = _printers.isNotEmpty ? _printers.first : null;
      _selectedController.add(_selectedPrinter);
    }
    
    _printersController.add(_printers);
  }

  /// Write data to the selected printer (legacy compatibility)
  Future<bool> write(Uint8List data) async {
    if (_selectedPrinter == null) return false;
    return _selectedPrinter!.write(data);
  }

  void dispose() {
    for (final printer in _printers) {
      printer.connectionSubscription.cancel();
    }
    _printersController.close();
    _selectedController.close();
  }
}

enum BleConnectionState {
  disconnected,
  connecting,
  connected,
}
