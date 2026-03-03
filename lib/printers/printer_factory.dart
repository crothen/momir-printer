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

/// Wrapper that provides write capability for protocols
class _PrinterWriter {
  final ConnectedPrinter? _printer;
  final BleManager? _legacyBluetooth;
  
  _PrinterWriter.fromPrinter(ConnectedPrinter printer) 
      : _printer = printer, _legacyBluetooth = null;
  
  _PrinterWriter.fromBleManager(BleManager bluetooth) 
      : _printer = null, _legacyBluetooth = bluetooth;
  
  Future<bool> write(Uint8List data) {
    if (_printer != null) {
      return _printer!.write(data);
    }
    return _legacyBluetooth?.write(data) ?? Future.value(false);
  }
}

/// Unified printer interface that auto-selects the right protocol
class UnifiedPrinter {
  final _PrinterWriter _writer;
  final PrinterType _type;
  final String? deviceName;
  
  late final PhomemoProtocolWithWriter? _phomemo;
  late final CatPrinterProtocolWithWriter? _catPrinter;
  
  /// Create from BleManager (legacy, uses selected printer)
  UnifiedPrinter(BleManager bluetooth, String? deviceName)
      : _writer = _PrinterWriter.fromBleManager(bluetooth),
        _type = PrinterFactory.detectType(deviceName),
        deviceName = deviceName {
    _initProtocols();
  }
  
  /// Create from a specific ConnectedPrinter
  UnifiedPrinter.fromPrinter(ConnectedPrinter printer)
      : _writer = _PrinterWriter.fromPrinter(printer),
        _type = PrinterFactory.detectType(printer.name),
        deviceName = printer.name {
    _initProtocols();
  }
  
  void _initProtocols() {
    switch (_type) {
      case PrinterType.catPrinter:
        _catPrinter = CatPrinterProtocolWithWriter(_writer);
        _phomemo = null;
        break;
      case PrinterType.phomemo:
      case PrinterType.unknown:
        _phomemo = PhomemoProtocolWithWriter(_writer);
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

/// Phomemo protocol variant that uses _PrinterWriter
class PhomemoProtocolWithWriter {
  final _PrinterWriter _writer;
  
  static const int printerWidth = 384;
  static const int bytesPerLine = 48;
  
  PhomemoProtocolWithWriter(this._writer);
  
  Future<bool> initialize() async {
    return await _writer.write(Uint8List.fromList([0x1b, 0x40]));
  }
  
  Future<bool> setDensity(double density) async {
    final d = density.clamp(0.0, 1.0);
    final value = (d * 255).round();
    return await _writer.write(Uint8List.fromList([0x1f, 0x11, 0x02, value]));
  }
  
  Future<bool> feedPaper(int lines) async {
    final n = lines.clamp(0, 255);
    await _writer.write(Uint8List.fromList([0x1b, 0x4a, n]));
    await Future.delayed(const Duration(milliseconds: 50));
    await _writer.write(Uint8List.fromList([0x1b, 0x64, n]));
    return true;
  }
  
  Future<bool> printImage(Uint8List imageData, int width, int height) async {
    final bytesPerLine = (width + 7) ~/ 8;
    
    for (var y = 0; y < height; y++) {
      final lineStart = y * bytesPerLine;
      final lineEnd = lineStart + bytesPerLine;
      if (lineEnd > imageData.length) break;
      
      final lineData = imageData.sublist(lineStart, lineEnd);
      final command = <int>[
        0x1d, 0x76, 0x30, 0x00,
        bytesPerLine, 0x00,
        0x01, 0x00,
        ...lineData,
      ];
      
      if (!await _writer.write(Uint8List.fromList(command))) return false;
      if (y % 8 == 0) await Future.delayed(const Duration(milliseconds: 10));
    }
    return true;
  }
  
  Future<bool> printFullImage(Uint8List imageData, int width, int height, {
    double density = 0.6,
    int feedLines = 80,
  }) async {
    if (!await initialize()) return false;
    await Future.delayed(const Duration(milliseconds: 100));
    if (!await setDensity(density)) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    if (!await printImage(imageData, width, height)) return false;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!await feedPaper(feedLines)) return false;
    return true;
  }
}

/// Cat printer protocol variant that uses _PrinterWriter
class CatPrinterProtocolWithWriter {
  final _PrinterWriter _writer;
  
  static const int printerWidth = 384;
  bool useCrc8 = true;
  bool lsbFirst = true;
  bool newFormat = false;
  
  CatPrinterProtocolWithWriter(this._writer);
  
  int _crc8(List<int> data) {
    int crc = 0;
    for (final b in data) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x80) != 0) {
          crc = ((crc << 1) ^ 0x07) & 0xFF;
        } else {
          crc = (crc << 1) & 0xFF;
        }
      }
    }
    return crc;
  }
  
  int _crcSum(List<int> data) {
    int sum = 0;
    for (final b in data) sum += b;
    return sum & 0xff;
  }
  
  Uint8List _buildCommand(int cmdType, List<int> payload) {
    final len = payload.length;
    final data = <int>[
      0x51, 0x78, cmdType, 0x00,
      len & 0xff, (len >> 8) & 0xff,
      ...payload,
      useCrc8 ? _crc8(payload) : _crcSum(payload),
      0xff,
    ];
    if (newFormat) return Uint8List.fromList([0x12, ...data]);
    return Uint8List.fromList(data);
  }
  
  int _reverseBits(int byte) {
    int result = 0;
    for (var i = 0; i < 8; i++) {
      if ((byte >> i) & 1 == 1) result |= 1 << (7 - i);
    }
    return result;
  }
  
  Future<bool> setEnergy(double energy) async {
    final e = energy.clamp(0.0, 1.0);
    final value = (e * 0xFFFF).round();
    return await _writer.write(_buildCommand(0xaf, [value & 0xff, (value >> 8) & 0xff]));
  }
  
  Future<bool> setSpeed(int speed) async {
    return await _writer.write(_buildCommand(0xbd, [speed & 0xff]));
  }
  
  Future<bool> initialize() async {
    await _writer.write(_buildCommand(0xa8, [0x00]));
    await Future.delayed(const Duration(milliseconds: 50));
    await _writer.write(_buildCommand(0xa3, [0x00]));
    await Future.delayed(const Duration(milliseconds: 50));
    await _writer.write(_buildCommand(0xbb, [0x01, 0x07]));
    return true;
  }
  
  Future<bool> startLattice() async {
    final payload = [0xaa, 0x55, 0x17, 0x38, 0x44, 0x5f, 0x5f, 0x5f, 0x44, 0x38, 0x2c];
    return await _writer.write(_buildCommand(0xa6, payload));
  }
  
  Future<bool> endLattice() async {
    final payload = [0xaa, 0x55, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17];
    return await _writer.write(_buildCommand(0xa6, payload));
  }
  
  Future<bool> feedPaper(int lines) async {
    return await _writer.write(_buildCommand(0xa1, [lines & 0xff, (lines >> 8) & 0xff]));
  }
  
  Future<bool> printImage(Uint8List imageData, int width, int height) async {
    final bytesPerLine = (width + 7) ~/ 8;
    
    if (!await initialize()) return false;
    await Future.delayed(const Duration(milliseconds: 100));
    if (!await startLattice()) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    
    for (var y = 0; y < height; y++) {
      final lineStart = y * bytesPerLine;
      final lineEnd = lineStart + bytesPerLine;
      if (lineEnd > imageData.length) break;
      
      final lineData = imageData.sublist(lineStart, lineEnd);
      final data = lsbFirst 
          ? lineData.map((b) => _reverseBits(b)).toList()
          : lineData.toList();
      
      if (!await _writer.write(_buildCommand(0xa2, data))) return false;
    }
    
    if (!await endLattice()) return false;
    await Future.delayed(const Duration(milliseconds: 100));
    return true;
  }
  
  Future<bool> printFullImage(Uint8List imageData, int width, int height, {
    double energy = 0.6,
    int feedLines = 80,
  }) async {
    if (!await setEnergy(energy)) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    if (!await setSpeed(0x19)) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    if (!await printImage(imageData, width, height)) return false;
    if (!await feedPaper(feedLines)) return false;
    return true;
  }
}
