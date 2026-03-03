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
  
  /// Check if a device name matches Phomemo/ESC-POS printers
  static bool matchesDevice(String deviceName) {
    final name = deviceName.toLowerCase();
    return name.startsWith('t02') || 
           name.startsWith('t04') ||
           name.startsWith('m02') ||
           name.startsWith('m03') ||
           name.startsWith('m04') ||
           name.startsWith('d30') ||
           name.contains('phomemo');
    // Note: X18, GT01, GB02 etc. use cat printer protocol, not ESC/POS
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
    // Try multiple feed methods for compatibility
    final n = lines.clamp(0, 255);
    
    // Method 1: ESC J n - Print and feed paper n dots
    await _bluetooth.write(Uint8List.fromList([0x1b, 0x4a, n]));
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Method 2: ESC d n - Feed n lines (some printers prefer this)
    await _bluetooth.write(Uint8List.fromList([0x1b, 0x64, n]));
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Method 3: Send line feeds as fallback
    if (n > 0) {
      final lfs = List<int>.filled((n / 8).ceil(), 0x0a); // LF characters
      await _bluetooth.write(Uint8List.fromList(lfs));
    }
    
    return true;
  }
  
  /// Print a 1-bit image
  /// [imageData] - packed bytes, MSB first, black=1
  /// [width] - pixels per line (should be 384)
  /// [height] - number of lines
  /// [lineDelayMs] - delay between line batches (higher = slower but cooler)
  Future<bool> printImage(Uint8List imageData, int width, int height, {int lineDelayMs = 10}) async {
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
      
      // Throttle to prevent buffer overflow and reduce heat
      if (y % 8 == 0 && lineDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: lineDelayMs));
      }
    }
    
    return true;
  }
  
  /// Print a full image with automatic initialization and paper feed
  Future<bool> printFullImage(Uint8List imageData, int width, int height, {
    double density = 0.6,
    int feedLines = 80, // ~1cm feed after print
  }) async {
    // Initialize
    if (!await initialize()) return false;
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Set density
    if (!await setDensity(density)) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Print image
    if (!await printImage(imageData, width, height)) return false;
    
    // Wait for print to complete before feeding
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Feed paper
    if (!await feedPaper(feedLines)) return false;
    
    // Wait for feed to complete
    await Future.delayed(const Duration(milliseconds: 200));
    
    return true;
  }
}
