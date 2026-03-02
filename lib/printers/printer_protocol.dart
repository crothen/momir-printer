import 'dart:typed_data';

/// Abstract interface for thermal printer protocols
abstract class PrinterProtocol {
  /// Human-readable name for this protocol
  String get name;

  /// Check if a device name matches this protocol
  bool matchesDevice(String deviceName);

  /// Initialize the printer connection
  Future<void> initialize();

  /// Set print density/darkness (0.0 - 1.0)
  Future<void> setDensity(double density);

  /// Print a 1-bit image
  /// [imageData] is packed bytes, MSB first
  /// [width] is pixels per line (usually 384)
  /// [height] is number of lines
  Future<void> printImage(Uint8List imageData, int width, int height);

  /// Feed paper by [lines] number of lines
  Future<void> feedPaper(int lines);

  /// Disconnect and cleanup
  Future<void> disconnect();
}
