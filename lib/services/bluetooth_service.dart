import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// Manages BLE connections to thermal printers
class BleManager {
  static final BleManager _instance = BleManager._internal();
  factory BleManager() => _instance;
  BleManager._internal();

  // Connection state
  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _writeCharacteristic;
  fbp.BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;

  // State streams
  final _connectionStateController = StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get connectionState => _connectionStateController.stream;

  // Current state
  BleConnectionState _currentState = BleConnectionState.disconnected;
  BleConnectionState get currentState => _currentState;

  fbp.BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get connectedDeviceName => _connectedDevice?.platformName;
  
  /// Get info about the connected characteristic for debugging
  String? get connectedCharacteristicInfo {
    if (_writeCharacteristic == null) return null;
    final svcFull = _writeCharacteristic!.serviceUuid.toString().toLowerCase();
    final charFull = _writeCharacteristic!.uuid.toString().toLowerCase();
    // Extract the short UUID (e.g., "ae30" from "0000ae30-...")
    final svc = svcFull.length >= 8 ? svcFull.substring(4, 8) : svcFull;
    final char = charFull.length >= 8 ? charFull.substring(4, 8) : charFull;
    final notify = _notifyCharacteristic != null ? ', notify: on' : '';
    return 'Svc: $svc, Char: $char$notify';
  }

  /// Check if Bluetooth is available and on
  Future<bool> isBluetoothAvailable() async {
    final supported = await fbp.FlutterBluePlus.isSupported;
    if (!supported) return false;
    
    final state = await fbp.FlutterBluePlus.adapterState.first;
    return state == fbp.BluetoothAdapterState.on;
  }

  /// Start scanning for BLE devices
  Stream<List<fbp.ScanResult>> scanForDevices({Duration timeout = const Duration(seconds: 10)}) {
    // Stop any existing scan
    fbp.FlutterBluePlus.stopScan();
    
    // Start scanning
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

  /// Connect to a BLE device
  Future<bool> connect(fbp.BluetoothDevice device) async {
    try {
      _updateState(BleConnectionState.connecting);
      
      // Connect to device
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;
      
      // Listen for disconnection
      _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });
      
      // Discover services and find write characteristic
      final services = await device.discoverServices();
      _writeCharacteristic = _findWriteCharacteristic(services);
      
      if (_writeCharacteristic == null) {
        await disconnect();
        return false;
      }
      
      // Find and enable notifications on ae02 (required by some printers)
      _notifyCharacteristic = _findNotifyCharacteristic(services);
      if (_notifyCharacteristic != null) {
        try {
          await _notifyCharacteristic!.setNotifyValue(true);
        } catch (e) {
          // Ignore notification errors - not all printers need this
        }
      }
      
      _updateState(BleConnectionState.connected);
      return true;
    } catch (e) {
      _updateState(BleConnectionState.disconnected);
      return false;
    }
  }

  /// Find the write characteristic for thermal printers
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
    
    // Priority 3: Generic printer characteristics (ae01, ae02)
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

  /// Find the notify characteristic for thermal printers (ae02)
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

  /// Disconnect from current device
  Future<void> disconnect() async {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    
    if (_notifyCharacteristic != null) {
      try {
        await _notifyCharacteristic!.setNotifyValue(false);
      } catch (e) {
        // Ignore
      }
    }
    
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _updateState(BleConnectionState.disconnected);
  }

  /// Handle unexpected disconnection
  void _handleDisconnection() {
    _connectedDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _updateState(BleConnectionState.disconnected);
  }

  /// Write data to the connected printer
  Future<bool> write(Uint8List data) async {
    if (_writeCharacteristic == null) return false;
    
    try {
      // Split into chunks if needed (BLE has MTU limits)
      const chunkSize = 180; // Safe chunk size for most devices
      
      for (var i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize > data.length) ? data.length : i + chunkSize;
        final chunk = data.sublist(i, end);
        
        await _writeCharacteristic!.write(chunk, withoutResponse: true);
        
        // Small delay between chunks
        if (end < data.length) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  void _updateState(BleConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  /// Dispose resources
  void dispose() {
    _connectionSubscription?.cancel();
    _connectionStateController.close();
  }
}

enum BleConnectionState {
  disconnected,
  connecting,
  connected,
}
