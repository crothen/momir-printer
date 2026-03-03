import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/printer_factory.dart';

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
  int _printHeight = 0;
  
  bool _isProcessing = false;
  bool _isPrinting = false;
  
  // Settings
  double _density = 0.6;
  double _contrast = 1.0;
  double _brightness = 0.0;
  DitheringAlgorithm _algorithm = DitheringAlgorithm.atkinson;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Print'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showSettingsDialog,
            tooltip: 'Image settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Preview area
          Expanded(
            child: _buildPreview(),
          ),
          
          // Quick algorithm selector
          if (_originalImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: DitheringAlgorithm.values.map((algo) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_algorithmName(algo)),
                        selected: _algorithm == algo,
                        onSelected: (_) => _setAlgorithm(algo),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          
          const SizedBox(height: 8),
          
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing || _isPrinting ? null : _showImageSourceDialog,
                    icon: const Icon(Icons.add_photo_alternate),
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

  String _algorithmName(DitheringAlgorithm algo) {
    switch (algo) {
      case DitheringAlgorithm.floydSteinberg:
        return 'Floyd-Steinberg';
      case DitheringAlgorithm.atkinson:
        return 'Atkinson';
      case DitheringAlgorithm.ordered:
        return 'Ordered';
      case DitheringAlgorithm.threshold:
        return 'Threshold';
    }
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
            '384 × $_printHeight px • ${_algorithmName(_algorithm)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null) return;
    
    final bytes = await picked.readAsBytes();
    _originalImage = bytes;
    
    await _updatePreview();
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(source: ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updatePreview() async {
    if (_originalImage == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final dims = ImageProcessor.getProcessedDimensions(_originalImage!);
      _printHeight = dims.height;
      
      _processedPreview = ImageProcessor.createPreview(
        _originalImage!,
        algorithm: _algorithm,
        contrast: _contrast,
        brightness: _brightness,
      );
      
      setState(() => _isProcessing = false);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process image: $e')),
        );
      }
    }
  }

  void _setAlgorithm(DitheringAlgorithm algo) {
    _algorithm = algo;
    _updatePreview();
  }

  bool _canPrint() {
    return _originalImage != null && 
           !_isPrinting && 
           _bluetooth.currentState == BleConnectionState.connected;
  }

  Future<void> _printImage() async {
    if (_originalImage == null) return;
    
    setState(() => _isPrinting = true);
    
    try {
      final printData = ImageProcessor.processForPrinting(
        _originalImage!,
        algorithm: _algorithm,
        contrast: _contrast,
        brightness: _brightness,
      );
      
      final printer = UnifiedPrinter(_bluetooth, _bluetooth.connectedDeviceName);
      final success = await printer.printFullImage(
        printData,
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

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Image Settings'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Print density
                  const Text('Print Density', style: TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _density,
                    min: 0.2,
                    max: 1.0,
                    divisions: 8,
                    label: '${(_density * 100).round()}%',
                    onChanged: (value) {
                      setDialogState(() => _density = value);
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Contrast
                  const Text('Contrast', style: TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _contrast,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _contrast.toStringAsFixed(1),
                    onChanged: (value) {
                      setDialogState(() => _contrast = value);
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Brightness
                  const Text('Brightness', style: TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _brightness,
                    min: -0.5,
                    max: 0.5,
                    divisions: 20,
                    label: _brightness.toStringAsFixed(2),
                    onChanged: (value) {
                      setDialogState(() => _brightness = value);
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Reset button
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setDialogState(() {
                          _density = 0.6;
                          _contrast = 1.0;
                          _brightness = 0.0;
                        });
                      },
                      child: const Text('Reset to defaults'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {}); // Update parent state
                  _updatePreview(); // Regenerate preview
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }
}
