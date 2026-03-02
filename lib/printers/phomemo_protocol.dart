import 'dart:typed_data';
import '../services/bluetooth_service.dart';

/// Phomemo T02 BLE thermal printer protocol
/// Based on: https://github.com/vivier/phomemo-tools
class PhomemoProtocol {
  final BleManager _bluetooth;
  
  // Printer specs
  static const int printerWidth = 384; // pixels (48 bytes per line)
  static const int bytesPerLine = 48;
  
  PhomemoProtocol(this._bluetooth);
  
  /// Check if a device name matches Phomemo printers
  static bool matchesDevice(String deviceName) {
    final name = deviceName.toLowerCase();
    return name.startsWith('t02') || 
           name.startsWith('t04') ||
           name.startsWith('m02') ||
           name.contains('phomemo');
  }
  
  /// Initialize the printer
  Future<bool> initialize() async {
    // ESC @ - Initialize printer
    return await _bluetooth.write(Uint8List.fromList([0x1b, 0x40]));
  }
  
  /// Set print density (0.0 - 1.0)
  Future<bool> setDensity(double density) async {
    // Clamp to valid range
    final d = density.clamp(0.0, 1.0);
    // Map to 0x00-0xFF
    final value = (d * 255).round();
    
    // 1F 11 02 XX - Set energy/density
    return await _bluetooth.write(Uint8List.fromList([0x1f, 0x11, 0x02, value]));
  }
  
  /// Feed paper by specified number of lines
  Future<bool> feedPaper(int lines) async {
    // ESC d XX - Feed XX lines
    return await _bluetooth.write(Uint8List.fromList([0x1b, 0x64, lines.clamp(0, 255)]));
  }
  
  /// Print a 1-bit image
  /// [imageData] - packed bytes, MSB first, black=1
  /// [width] - pixels per line (should be 384)
  /// [height] - number of lines
  Future<bool> printImage(Uint8List imageData, int width, int height) async {
    final bytesPerLine = (width + 7) ~/ 8;
    
    // Process line by line
    for (var y = 0; y < height; y++) {
      final lineStart = y * bytesPerLine;
      final lineEnd = lineStart + bytesPerLine;
      
      if (lineEnd > imageData.length) break;
      
      final lineData = imageData.sublist(lineStart, lineEnd);
      
      // Build print command: GS v 0 mode wL wH hL hH [data]
      // mode=0 (normal), w=bytes per line, h=1 (one line at a time)
      final command = <int>[
        0x1d, 0x76, 0x30, 0x00, // GS v 0 mode
        bytesPerLine, 0x00,      // width in bytes (low, high)
        0x01, 0x00,              // height = 1 line (low, high)
        ...lineData,
      ];
      
      final success = await _bluetooth.write(Uint8List.fromList(command));
      if (!success) return false;
      
      // Throttle to prevent buffer overflow
      if (y % 8 == 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
    
    return true;
  }
  
  /// Print a full image with automatic initialization and paper feed
  Future<bool> printFullImage(Uint8List imageData, int width, int height, {
    double density = 0.6,
    int feedLines = 40,
  }) async {
    // Initialize
    if (!await initialize()) return false;
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Set density
    if (!await setDensity(density)) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Print image
    if (!await printImage(imageData, width, height)) return false;
    
    // Feed paper
    await Future.delayed(const Duration(milliseconds: 100));
    if (!await feedPaper(feedLines)) return false;
    
    return true;
  }
}
