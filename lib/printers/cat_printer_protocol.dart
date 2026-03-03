import 'dart:typed_data';
import '../services/bluetooth_service.dart';

/// Cat Printer BLE thermal printer protocol (X18, GT01, GB02, etc.)
/// Based on: https://github.com/rbaron/catprinter
/// And: https://github.com/lisp3r/bluetooth-thermal-printer
class CatPrinterProtocol {
  final BleManager _bluetooth;
  
  // Printer specs
  static const int printerWidth = 384; // pixels (48 bytes per line)
  static const int bytesPerLine = 48;
  
  // Protocol constants
  static const int cmdHeader1 = 0x51;
  static const int cmdHeader2 = 0x78;
  static const int cmdTerminator = 0xff;
  
  // Command types
  static const int cmdGetStatus = 0xa3;
  static const int cmdSetQuality = 0xa4;
  static const int cmdLattice = 0xa6;  // Start/end printing
  static const int cmdSetEnergy = 0xaf;
  static const int cmdUpdateDevice = 0xa9;
  static const int cmdPrintRow = 0xa2;  // Print image row (uncompressed)
  static const int cmdPrintRowCompressed = 0xbf;  // Print image row (RLE compressed)
  static const int cmdFeedPaper = 0xa1;
  static const int cmdDrawingMode = 0xbe;
  static const int cmdSetSpeed = 0xbd;
  static const int cmdControlLattice = 0xa6;
  
  CatPrinterProtocol(this._bluetooth);
  
  /// Check if a device name matches cat printer family
  static bool matchesDevice(String deviceName) {
    final name = deviceName.toLowerCase();
    return name.startsWith('gt01') ||
           name.startsWith('gt02') ||
           name.startsWith('gb01') ||
           name.startsWith('gb02') ||
           name.startsWith('gb03') ||
           name.startsWith('mx05') ||
           name.startsWith('mx06') ||
           name.startsWith('mx08') ||
           name.startsWith('mx10') ||
           name.startsWith('x18') ||   // Seven Star Technology X18
           name.startsWith('yt01') ||
           name.contains('cat');
  }
  
  /// Build a command packet
  Uint8List _buildCommand(int cmdType, List<int> payload) {
    final len = payload.length;
    final data = <int>[
      cmdHeader1, cmdHeader2,       // Header: 51 78
      cmdType,                       // Command type
      0x00,                          // Unknown (always 0)
      len & 0xff, (len >> 8) & 0xff, // Payload length (little endian)
      ...payload,
      0x00,                          // CRC placeholder
      cmdTerminator,                 // Terminator: ff
    ];
    
    // Calculate CRC (sum of payload bytes)
    data[data.length - 2] = _calculateCrc(payload);
    
    return Uint8List.fromList(data);
  }
  
  /// Calculate CRC (simple sum of bytes)
  int _calculateCrc(List<int> data) {
    int sum = 0;
    for (final b in data) {
      sum += b;
    }
    return sum & 0xff;
  }
  
  /// Initialize the printer
  Future<bool> initialize() async {
    // Get device status
    final statusCmd = _buildCommand(cmdGetStatus, [0x00]);
    return await _bluetooth.write(statusCmd);
  }
  
  /// Set print energy/density (0.0 - 1.0)
  Future<bool> setEnergy(double energy) async {
    final e = energy.clamp(0.0, 1.0);
    // Map to 0x0000-0xFFFF (little endian)
    final value = (e * 0xFFFF).round();
    final lowByte = value & 0xff;
    final highByte = (value >> 8) & 0xff;
    
    final cmd = _buildCommand(cmdSetEnergy, [lowByte, highByte]);
    return await _bluetooth.write(cmd);
  }
  
  /// Set print speed
  Future<bool> setSpeed(int speed) async {
    final cmd = _buildCommand(cmdSetSpeed, [speed & 0xff]);
    return await _bluetooth.write(cmd);
  }
  
  /// Enter drawing mode
  Future<bool> setDrawingMode(bool enabled) async {
    final cmd = _buildCommand(cmdDrawingMode, [enabled ? 0x01 : 0x00]);
    return await _bluetooth.write(cmd);
  }
  
  /// Start lattice/printing mode
  Future<bool> startLattice() async {
    // Magic bytes for start lattice
    final payload = [0xaa, 0x55, 0x17, 0x38, 0x44, 0x5f, 0x5f, 0x5f, 0x44, 0x38, 0x2c];
    final cmd = _buildCommand(cmdLattice, payload);
    return await _bluetooth.write(cmd);
  }
  
  /// End lattice/printing mode
  Future<bool> endLattice() async {
    // Magic bytes for end lattice
    final payload = [0xaa, 0x55, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17];
    final cmd = _buildCommand(cmdLattice, payload);
    return await _bluetooth.write(cmd);
  }
  
  /// Set quality/mode
  Future<bool> setQuality(int quality) async {
    final cmd = _buildCommand(cmdSetQuality, [quality & 0xff]);
    return await _bluetooth.write(cmd);
  }
  
  /// Feed paper
  Future<bool> feedPaper(int lines) async {
    final lowByte = lines & 0xff;
    final highByte = (lines >> 8) & 0xff;
    final cmd = _buildCommand(cmdFeedPaper, [lowByte, highByte]);
    return await _bluetooth.write(cmd);
  }
  
  /// Print a single row (uncompressed)
  Future<bool> _printRowUncompressed(Uint8List rowData) async {
    final cmd = _buildCommand(cmdPrintRow, rowData.toList());
    return await _bluetooth.write(cmd);
  }
  
  /// Print a single row with RLE compression (if beneficial)
  Future<bool> _printRowCompressed(Uint8List rowData) async {
    final compressed = _runLengthEncode(rowData);
    
    // Only use compression if it saves space
    if (compressed.length < rowData.length) {
      final cmd = _buildCommand(cmdPrintRowCompressed, compressed);
      return await _bluetooth.write(cmd);
    } else {
      return _printRowUncompressed(rowData);
    }
  }
  
  /// Run-length encode a row
  /// Format: For each run, high bit = color (1=white, 0=black), low 7 bits = length
  List<int> _runLengthEncode(Uint8List data) {
    final result = <int>[];
    
    // Convert bytes to bits
    final bits = <bool>[];
    for (final byte in data) {
      for (var i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1 == 1);
      }
    }
    
    var i = 0;
    while (i < bits.length) {
      final isBlack = bits[i];
      var runLength = 0;
      
      // Count consecutive same-color pixels (max 127)
      while (i < bits.length && bits[i] == isBlack && runLength < 127) {
        runLength++;
        i++;
      }
      
      // Encode: high bit = 1 for white (not black), low 7 bits = length
      final encoded = (isBlack ? 0x00 : 0x80) | runLength;
      result.add(encoded);
    }
    
    return result;
  }
  
  /// Print a 1-bit image
  /// [imageData] - packed bytes, MSB first, black=1
  /// [width] - pixels per line (should be 384)
  /// [height] - number of lines
  /// [useCompression] - use RLE compression (may be required for dense images)
  /// [rowDelayMs] - delay between rows in milliseconds
  /// [onProgress] - callback for progress updates
  Future<bool> printImage(
    Uint8List imageData, 
    int width, 
    int height, {
    bool useCompression = false,
    int rowDelayMs = 5,
    void Function(int row, int total, String message)? onProgress,
  }) async {
    final bytesPerLine = (width + 7) ~/ 8;
    
    onProgress?.call(0, height, 'Initializing...');
    
    // Initialize
    if (!await initialize()) {
      onProgress?.call(0, height, 'ERROR: Initialize failed');
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 100));
    
    onProgress?.call(0, height, 'Starting lattice mode...');
    
    // Start lattice mode
    if (!await startLattice()) {
      onProgress?.call(0, height, 'ERROR: Start lattice failed');
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Print each row
    for (var y = 0; y < height; y++) {
      final lineStart = y * bytesPerLine;
      final lineEnd = lineStart + bytesPerLine;
      
      if (lineEnd > imageData.length) break;
      
      final lineData = imageData.sublist(lineStart, lineEnd);
      
      bool success;
      if (useCompression) {
        success = await _printRowCompressed(lineData);
        if (y == 0) onProgress?.call(y, height, 'Using RLE compression');
      } else {
        success = await _printRowUncompressed(lineData);
        if (y == 0) onProgress?.call(y, height, 'Using uncompressed data');
      }
      
      if (!success) {
        onProgress?.call(y, height, 'ERROR: Row $y failed');
        return false;
      }
      
      // Progress update every 10 rows
      if (y % 10 == 0) {
        onProgress?.call(y, height, 'Printing row $y/$height');
      }
      
      // Throttle to prevent buffer overflow
      if (rowDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: rowDelayMs));
      }
    }
    
    onProgress?.call(height, height, 'Ending lattice mode...');
    
    // End lattice mode
    if (!await endLattice()) {
      onProgress?.call(height, height, 'ERROR: End lattice failed');
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 100));
    
    onProgress?.call(height, height, 'Done!');
    return true;
  }
  
  /// Print a full image with automatic initialization and paper feed
  Future<bool> printFullImage(Uint8List imageData, int width, int height, {
    double energy = 0.6,
    int feedLines = 80,
  }) async {
    // Set energy/density
    if (!await setEnergy(energy)) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Set speed (0x19 = moderate)
    if (!await setSpeed(0x19)) return false;
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Print the image
    if (!await printImage(imageData, width, height)) return false;
    
    // Feed paper
    if (!await feedPaper(feedLines)) return false;
    await Future.delayed(const Duration(milliseconds: 200));
    
    return true;
  }
}
