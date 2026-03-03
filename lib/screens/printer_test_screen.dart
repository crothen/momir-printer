import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/printer_factory.dart';
import '../printers/phomemo_protocol.dart';
import '../printers/cat_printer_protocol.dart';

class PrinterTestScreen extends StatefulWidget {
  const PrinterTestScreen({super.key});

  @override
  State<PrinterTestScreen> createState() => _PrinterTestScreenState();
}

class _PrinterTestScreenState extends State<PrinterTestScreen> {
  final _bluetooth = BleManager();
  
  // Settings
  PrinterType _selectedProtocol = PrinterType.catPrinter;
  double _energy = 0.6;
  int _speed = 0x19;
  int _feedLines = 80;
  bool _useCompression = false;
  int _rowDelayMs = 5;
  bool _invertImage = false;
  
  // Test patterns
  String _selectedPattern = 'gradient';
  
  // State
  bool _isPrinting = false;
  String _status = '';
  List<String> _log = [];
  
  // Preview
  Uint8List? _previewData;
  int _previewWidth = 384;
  int _previewHeight = 100;

  @override
  void initState() {
    super.initState();
    _generatePreview();
    
    // Auto-detect protocol from connected device
    final deviceName = _bluetooth.connectedDeviceName;
    if (deviceName != null) {
      setState(() {
        _selectedProtocol = PrinterFactory.detectType(deviceName);
        _addLog('Auto-detected protocol: ${_selectedProtocol.name} for $deviceName');
      });
    }
  }

  void _addLog(String message) {
    setState(() {
      _log.insert(0, '[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  void _copyLog() {
    final logText = _log.reversed.join('\n');
    Clipboard.setData(ClipboardData(text: logText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copied to clipboard')),
    );
  }

  Future<void> _generatePreview() async {
    var data = _generateTestPattern(_selectedPattern, _previewWidth, _previewHeight);
    if (_invertImage) {
      data = Uint8List.fromList(data.map((b) => b ^ 0xFF).toList());
    }
    setState(() {
      _previewData = data;
    });
  }

  Uint8List _generateTestPattern(String pattern, int width, int height) {
    final bytesPerLine = (width + 7) ~/ 8;
    final data = Uint8List(bytesPerLine * height);
    
    switch (pattern) {
      case 'gradient':
        // Horizontal gradient with dithering
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final threshold = (x / width * 255).round();
            final dither = ((x + y) % 2 == 0) ? 20 : -20;
            final value = (y / height * 255).round();
            final isBlack = value > (threshold + dither);
            
            if (isBlack) {
              final byteIndex = y * bytesPerLine + (x ~/ 8);
              final bitIndex = 7 - (x % 8);
              data[byteIndex] |= (1 << bitIndex);
            }
          }
        }
        break;
        
      case 'checkerboard':
        // 8x8 checkerboard
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final isBlack = ((x ~/ 8) + (y ~/ 8)) % 2 == 0;
            if (isBlack) {
              final byteIndex = y * bytesPerLine + (x ~/ 8);
              final bitIndex = 7 - (x % 8);
              data[byteIndex] |= (1 << bitIndex);
            }
          }
        }
        break;
        
      case 'stripes':
        // Horizontal stripes (4px each)
        for (var y = 0; y < height; y++) {
          if ((y ~/ 4) % 2 == 0) {
            for (var x = 0; x < bytesPerLine; x++) {
              data[y * bytesPerLine + x] = 0xFF;
            }
          }
        }
        break;
        
      case 'border':
        // Border with cross
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final isBorder = x < 2 || x >= width - 2 || y < 2 || y >= height - 2;
            final isCrossH = y >= height ~/ 2 - 1 && y <= height ~/ 2 + 1;
            final isCrossV = x >= width ~/ 2 - 1 && x <= width ~/ 2 + 1;
            
            if (isBorder || isCrossH || isCrossV) {
              final byteIndex = y * bytesPerLine + (x ~/ 8);
              final bitIndex = 7 - (x % 8);
              data[byteIndex] |= (1 << bitIndex);
            }
          }
        }
        break;
        
      case 'text':
        // Simple "TEST" text pattern (hardcoded bitmap)
        _drawText(data, bytesPerLine, width, height);
        break;
        
      case 'solid':
        // Solid black
        data.fillRange(0, data.length, 0xFF);
        break;
        
      case 'empty':
        // Empty (all white) - already zeroed
        break;
    }
    
    return data;
  }

  void _drawText(Uint8List data, int bytesPerLine, int width, int height) {
    // Simple 5x7 "TEST" bitmap
    const text = [
      '##### ##### #### #####',
      '  #   #     #      #  ',
      '  #   ###   ###    #  ',
      '  #   #       #    #  ',
      '  #   ##### ####   #  ',
    ];
    
    final startY = (height - text.length * 8) ~/ 2;
    final startX = (width - text[0].length * 4) ~/ 2;
    
    for (var row = 0; row < text.length; row++) {
      for (var col = 0; col < text[row].length; col++) {
        if (text[row][col] == '#') {
          // Draw a 4x8 block
          for (var dy = 0; dy < 8; dy++) {
            for (var dx = 0; dx < 4; dx++) {
              final x = startX + col * 4 + dx;
              final y = startY + row * 8 + dy;
              if (x >= 0 && x < width && y >= 0 && y < height) {
                final byteIndex = y * bytesPerLine + (x ~/ 8);
                final bitIndex = 7 - (x % 8);
                data[byteIndex] |= (1 << bitIndex);
              }
            }
          }
        }
      }
    }
  }

  Future<void> _printTest() async {
    if (_bluetooth.currentState != BleConnectionState.connected) {
      _addLog('ERROR: Not connected to printer');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a printer first')),
      );
      return;
    }
    
    setState(() {
      _isPrinting = true;
      _status = 'Printing...';
    });
    
    _addLog('Starting print with protocol: ${_selectedProtocol.name}');
    _addLog('BLE: ${_bluetooth.connectedCharacteristicInfo ?? "unknown"}');
    _addLog('Settings: energy=$_energy, speed=$_speed, feed=$_feedLines, invert=$_invertImage');
    
    try {
      var imageData = _generateTestPattern(_selectedPattern, _previewWidth, _previewHeight);
      
      // Invert if needed
      if (_invertImage) {
        imageData = Uint8List.fromList(imageData.map((b) => b ^ 0xFF).toList());
        _addLog('Image inverted (polarity swapped)');
      }
      
      // Count black pixels for diagnostic
      int blackPixels = 0;
      for (final byte in imageData) {
        for (var i = 0; i < 8; i++) {
          if ((byte >> i) & 1 == 1) blackPixels++;
        }
      }
      final totalPixels = _previewWidth * _previewHeight;
      final density = (blackPixels / totalPixels * 100).toStringAsFixed(1);
      
      _addLog('Generated ${imageData.length} bytes (${_previewWidth}x$_previewHeight), $blackPixels black pixels ($density%)');
      
      bool success = false;
      
      if (_selectedProtocol == PrinterType.catPrinter) {
        success = await _printWithCatProtocol(imageData);
      } else {
        success = await _printWithPhomemoProtocol(imageData);
      }
      
      _addLog(success ? 'Print completed!' : 'Print failed');
      setState(() {
        _status = success ? 'Success!' : 'Failed';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Print successful!' : 'Print failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      _addLog('ERROR: $e');
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isPrinting = false;
      });
    }
  }

  Future<bool> _printWithCatProtocol(Uint8List imageData) async {
    final protocol = CatPrinterProtocol(_bluetooth);
    
    _addLog('Cat: Settings - energy=${(_energy * 100).round()}%, speed=0x${_speed.toRadixString(16)}, compression=$_useCompression, rowDelay=${_rowDelayMs}ms');
    
    _addLog('Cat: Setting energy ${(_energy * 100).round()}%');
    if (!await protocol.setEnergy(_energy)) {
      _addLog('Cat: setEnergy failed');
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    
    _addLog('Cat: Setting speed 0x${_speed.toRadixString(16)}');
    if (!await protocol.setSpeed(_speed)) {
      _addLog('Cat: setSpeed failed');
    }
    await Future.delayed(const Duration(milliseconds: 50));
    
    _addLog('Cat: Printing $_previewHeight rows (compression=$_useCompression, delay=${_rowDelayMs}ms)...');
    
    final success = await protocol.printImage(
      imageData, 
      _previewWidth, 
      _previewHeight,
      useCompression: _useCompression,
      rowDelayMs: _rowDelayMs,
      onProgress: (row, total, message) {
        _addLog('Cat: $message');
      },
    );
    
    if (!success) {
      _addLog('Cat: printImage failed');
      return false;
    }
    
    _addLog('Cat: Feeding $_feedLines lines');
    if (!await protocol.feedPaper(_feedLines)) {
      _addLog('Cat: feedPaper failed');
    }
    
    return true;
  }

  Future<bool> _printWithPhomemoProtocol(Uint8List imageData) async {
    final protocol = PhomemoProtocol(_bluetooth);
    
    _addLog('Phomemo: Initializing');
    if (!await protocol.initialize()) {
      _addLog('Phomemo: initialize failed');
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 100));
    
    _addLog('Phomemo: Setting density ${(_energy * 100).round()}%');
    if (!await protocol.setDensity(_energy)) {
      _addLog('Phomemo: setDensity failed');
    }
    await Future.delayed(const Duration(milliseconds: 50));
    
    _addLog('Phomemo: Printing $_previewHeight rows...');
    if (!await protocol.printImage(imageData, _previewWidth, _previewHeight)) {
      _addLog('Phomemo: printImage failed');
      return false;
    }
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    _addLog('Phomemo: Feeding $_feedLines lines');
    if (!await protocol.feedPaper(_feedLines)) {
      _addLog('Phomemo: feedPaper failed');
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _bluetooth.currentState == BleConnectionState.connected;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Test'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection status
            Card(
              child: ListTile(
                leading: Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: isConnected ? Colors.green : Colors.grey,
                ),
                title: Text(isConnected 
                    ? 'Connected: ${_bluetooth.connectedDeviceName}'
                    : 'Not connected'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Protocol: ${_selectedProtocol.name}'),
                    if (isConnected && _bluetooth.connectedCharacteristicInfo != null)
                      Text(
                        _bluetooth.connectedCharacteristicInfo!,
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                      ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Protocol selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Protocol', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<PrinterType>(
                      segments: const [
                        ButtonSegment(
                          value: PrinterType.catPrinter,
                          label: Text('Cat Printer'),
                          icon: Icon(Icons.pets),
                        ),
                        ButtonSegment(
                          value: PrinterType.phomemo,
                          label: Text('Phomemo'),
                          icon: Icon(Icons.print),
                        ),
                      ],
                      selected: {_selectedProtocol},
                      onSelectionChanged: (s) => setState(() => _selectedProtocol = s.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedProtocol == PrinterType.catPrinter
                          ? 'For: X18, GT01, GB02, MX10, etc.'
                          : 'For: T02, T04, M02, Phomemo, etc.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
                    // Energy/Density
                    Row(
                      children: [
                        const SizedBox(width: 80, child: Text('Energy:')),
                        Expanded(
                          child: Slider(
                            value: _energy,
                            min: 0.1,
                            max: 1.0,
                            divisions: 9,
                            label: '${(_energy * 100).round()}%',
                            onChanged: (v) => setState(() => _energy = v),
                          ),
                        ),
                        SizedBox(width: 50, child: Text('${(_energy * 100).round()}%')),
                      ],
                    ),
                    
                    // Speed (cat printer only)
                    if (_selectedProtocol == PrinterType.catPrinter)
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('Speed:')),
                          Expanded(
                            child: Slider(
                              value: _speed.toDouble(),
                              min: 0x01,
                              max: 0x40,
                              divisions: 63,
                              label: '0x${_speed.toRadixString(16)}',
                              onChanged: (v) => setState(() => _speed = v.round()),
                            ),
                          ),
                          SizedBox(width: 50, child: Text('0x${_speed.toRadixString(16)}')),
                        ],
                      ),
                    
                    // Feed lines
                    Row(
                      children: [
                        const SizedBox(width: 80, child: Text('Feed:')),
                        Expanded(
                          child: Slider(
                            value: _feedLines.toDouble(),
                            min: 0,
                            max: 200,
                            divisions: 20,
                            label: '$_feedLines lines',
                            onChanged: (v) => setState(() => _feedLines = v.round()),
                          ),
                        ),
                        SizedBox(width: 50, child: Text('$_feedLines')),
                      ],
                    ),
                    
                    // Row delay (cat printer)
                    if (_selectedProtocol == PrinterType.catPrinter)
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('Row delay:')),
                          Expanded(
                            child: Slider(
                              value: _rowDelayMs.toDouble(),
                              min: 0,
                              max: 50,
                              divisions: 50,
                              label: '$_rowDelayMs ms',
                              onChanged: (v) => setState(() => _rowDelayMs = v.round()),
                            ),
                          ),
                          SizedBox(width: 50, child: Text('${_rowDelayMs}ms')),
                        ],
                      ),
                    
                    // Compression toggle (cat printer)
                    if (_selectedProtocol == PrinterType.catPrinter)
                      SwitchListTile(
                        title: const Text('Use RLE compression'),
                        subtitle: const Text('May help with dense patterns'),
                        value: _useCompression,
                        onChanged: (v) => setState(() => _useCompression = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    
                    // Invert image toggle
                    SwitchListTile(
                      title: const Text('Invert image'),
                      subtitle: const Text('Swap black/white (test polarity)'),
                      value: _invertImage,
                      onChanged: (v) {
                        setState(() => _invertImage = v);
                        _generatePreview();
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Test pattern selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Test Pattern', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _patternChip('gradient', 'Gradient'),
                        _patternChip('checkerboard', 'Checkerboard'),
                        _patternChip('stripes', 'Stripes'),
                        _patternChip('border', 'Border'),
                        _patternChip('text', 'Text'),
                        _patternChip('solid', 'Solid'),
                        _patternChip('empty', 'Empty'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Preview
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        color: Colors.white,
                      ),
                      child: _previewData != null
                          ? CustomPaint(
                              painter: _BitmapPainter(_previewData!, _previewWidth, _previewHeight),
                              size: Size.infinite,
                            )
                          : const Center(child: CircularProgressIndicator()),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Print button
            FilledButton.icon(
              onPressed: _isPrinting ? null : _printTest,
              icon: _isPrinting 
                  ? const SizedBox(
                      width: 20, 
                      height: 20, 
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.print),
              label: Text(_isPrinting ? 'Printing...' : 'Print Test'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_status, textAlign: TextAlign.center),
            ],
            
            const SizedBox(height: 16),
            
            // Log
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Debug Log', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: _log.isEmpty ? null : _copyLog,
                          tooltip: 'Copy log',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: _log.isEmpty ? null : () => setState(() => _log.clear()),
                          tooltip: 'Clear log',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _log.length,
                        itemBuilder: (context, index) => Text(
                          _log[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _patternChip(String value, String label) {
    final isSelected = _selectedPattern == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedPattern = value);
        _generatePreview();
      },
    );
  }
}

class _BitmapPainter extends CustomPainter {
  final Uint8List data;
  final int width;
  final int height;
  
  _BitmapPainter(this.data, this.width, this.height);
  
  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / width;
    final scaleY = size.height / height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    
    final offsetX = (size.width - width * scale) / 2;
    final offsetY = (size.height - height * scale) / 2;
    
    final paint = Paint()..color = Colors.black;
    final bytesPerLine = (width + 7) ~/ 8;
    
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final byteIndex = y * bytesPerLine + (x ~/ 8);
        final bitIndex = 7 - (x % 8);
        final isBlack = (data[byteIndex] >> bitIndex) & 1 == 1;
        
        if (isBlack) {
          canvas.drawRect(
            Rect.fromLTWH(
              offsetX + x * scale,
              offsetY + y * scale,
              scale.ceilToDouble(),
              scale.ceilToDouble(),
            ),
            paint,
          );
        }
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
