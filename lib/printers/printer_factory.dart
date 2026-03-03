import 'dart:typed_data';
import '../services/bluetooth_service.dart';
import 'phomemo_protocol.dart';
import 'cat_printer_protocol.dart';

/// Printer protocol types
enum PrinterType {
  phomemo,    // ESC/POS based (T02, T04, M02)
  catPrinter, // Cat printer protocol (X18, GT01, GB02, etc.)
  unknown,
}

/// Factory for creating the appropriate printer protocol
class PrinterFactory {
  /// Detect the printer type from device name
  static PrinterType detectType(String? deviceName) {
    if (deviceName == null) return PrinterType.unknown;
    
    final name = deviceName.toLowerCase();
    
    // Cat printer family (51 78 protocol)
    if (CatPrinterProtocol.matchesDevice(name)) {
      return PrinterType.catPrinter;
    }
    
    // Phomemo/ESC-POS family
    if (PhomemoProtocol.matchesDevice(name)) {
      return PrinterType.phomemo;
    }
    
    // Unknown - try Phomemo as fallback (more common)
    return PrinterType.phomemo;
  }
  
  /// Get the printer width in pixels for the given type
  static int getPrinterWidth(PrinterType type) {
    switch (type) {
      case PrinterType.catPrinter:
        return CatPrinterProtocol.printerWidth;
      case PrinterType.phomemo:
      case PrinterType.unknown:
        return PhomemoProtocol.printerWidth;
    }
  }
}

/// Unified printer interface that auto-selects the right protocol
class UnifiedPrinter {
  final BleManager _bluetooth;
  final PrinterType _type;
  
  late final PhomemoProtocol? _phomemo;
  late final CatPrinterProtocol? _catPrinter;
  
  UnifiedPrinter(this._bluetooth, String? deviceName)
      : _type = PrinterFactory.detectType(deviceName) {
    switch (_type) {
      case PrinterType.catPrinter:
        _catPrinter = CatPrinterProtocol(_bluetooth);
        _phomemo = null;
        break;
      case PrinterType.phomemo:
      case PrinterType.unknown:
        _phomemo = PhomemoProtocol(_bluetooth);
        _catPrinter = null;
        break;
    }
  }
  
  /// Get the detected printer type
  PrinterType get type => _type;
  
  /// Get printer width in pixels
  int get printerWidth => PrinterFactory.getPrinterWidth(_type);
  
  /// Print a full image with automatic initialization and paper feed
  Future<bool> printFullImage(Uint8List imageData, int width, int height, {
    double density = 0.6,
    int feedLines = 80,
  }) async {
    switch (_type) {
      case PrinterType.catPrinter:
        return await _catPrinter!.printFullImage(
          imageData, width, height,
          energy: density,
          feedLines: feedLines,
        );
      case PrinterType.phomemo:
      case PrinterType.unknown:
        return await _phomemo!.printFullImage(
          imageData, width, height,
          density: density,
          feedLines: feedLines,
        );
    }
  }
}
