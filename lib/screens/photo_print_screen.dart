import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/phomemo_protocol.dart';

class PhotoPrintScreen extends StatefulWidget {
  const PhotoPrintScreen({super.key});

  @override
  State<PhotoPrintScreen> createState() => _PhotoPrintScreenState();
}

class _PhotoPrintScreenState extends State<PhotoPrintScreen> {
  final _bluetooth = BleManager();
  final _imagePicker = ImagePicker();
  
  Uint8List? _originalImage;
  Uint8List? _processedPreview;
  Uint8List? _printData;
  int _printHeight = 0;
  
  bool _isProcessing = false;
  bool _isPrinting = false;
  double _density = 0.6;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Print'),
        actions: [
          // Density slider
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showDensityDialog,
            tooltip: 'Print density',
          ),
        ],
      ),
      body: Column(
        children: [
          // Preview area
          Expanded(
            child: _buildPreview(),
          ),
          
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing || _isPrinting ? null : _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Select Image'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _canPrint() ? _printImage : null,
                    icon: _isPrinting 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print),
                    label: Text(_isPrinting ? 'Printing...' : 'Print'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_isProcessing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing image...'),
          ],
        ),
      );
    }
    
    if (_processedPreview == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate,
              size: 80,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Select an image to print',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Dithered preview
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              color: Colors.white,
            ),
            child: Image.memory(
              _processedPreview!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none, // Keep sharp pixels
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Preview (384 × $_printHeight px)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    
    setState(() {
      _isProcessing = true;
      _originalImage = null;
      _processedPreview = null;
      _printData = null;
    });
    
    try {
      final bytes = await picked.readAsBytes();
      _originalImage = bytes;
      
      // Process for printing
      _printData = ImageProcessor.processForPrinting(bytes);
      
      // Get dimensions for preview
      final dims = ImageProcessor.getProcessedDimensions(bytes);
      _printHeight = dims.height;
      
      // Create preview image (PNG for display)
      _processedPreview = _createPreviewImage(bytes);
      
      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process image: $e')),
        );
      }
    }
  }

  Uint8List _createPreviewImage(Uint8List imageBytes) {
    // Decode, resize, grayscale, dither, then encode as PNG for preview
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Failed to decode image');
    
    final resized = img.copyResize(image, width: ImageProcessor.defaultWidth);
    final grayscale = img.grayscale(resized);
    
    // Simple threshold dithering for preview (faster than Floyd-Steinberg)
    for (var y = 0; y < grayscale.height; y++) {
      for (var x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final lum = img.getLuminance(pixel);
        final newVal = lum < 128 ? 0 : 255;
        grayscale.setPixelRgb(x, y, newVal, newVal, newVal);
      }
    }
    
    return Uint8List.fromList(img.encodePng(grayscale));
  }

  bool _canPrint() {
    return _printData != null && 
           !_isPrinting && 
           _bluetooth.currentState == BleConnectionState.connected;
  }

  Future<void> _printImage() async {
    if (_printData == null) return;
    
    setState(() => _isPrinting = true);
    
    try {
      final protocol = PhomemoProtocol(_bluetooth);
      final success = await protocol.printFullImage(
        _printData!,
        ImageProcessor.defaultWidth,
        _printHeight,
        density: _density,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Print complete!' : 'Print failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print error: $e')),
        );
      }
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  void _showDensityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Print Density'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: _density,
                  min: 0.2,
                  max: 1.0,
                  divisions: 8,
                  label: '${(_density * 100).round()}%',
                  onChanged: (value) {
                    setDialogState(() => _density = value);
                    setState(() {}); // Update parent too
                  },
                ),
                Text('${(_density * 100).round()}% darkness'),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
