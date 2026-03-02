import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Processes images for thermal printing
class ImageProcessor {
  /// Standard thermal printer width in pixels
  static const defaultWidth = 384;

  /// Convert an image to 1-bit thermal printer format
  /// 
  /// Returns packed bytes (MSB first) ready to send to printer
  static Uint8List processForPrinting(
    Uint8List imageBytes, {
    int width = defaultWidth,
  }) {
    // Decode the image
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ImageProcessingException('Failed to decode image');
    }

    // Resize to printer width, maintaining aspect ratio
    final resized = img.copyResize(image, width: width);
    
    // Convert to grayscale
    final grayscale = img.grayscale(resized);
    
    // Apply Floyd-Steinberg dithering
    final dithered = _floydSteinbergDither(grayscale);
    
    // Pack into bytes
    return _packBits(dithered);
  }

  /// Floyd-Steinberg dithering algorithm
  static img.Image _floydSteinbergDither(img.Image image) {
    final result = img.Image.from(image);
    final width = result.width;
    final height = result.height;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = result.getPixel(x, y);
        final oldValue = img.getLuminance(pixel).toInt();
        final newValue = oldValue < 128 ? 0 : 255;
        
        // Set the new value
        result.setPixelRgb(x, y, newValue, newValue, newValue);
        
        // Calculate error
        final error = oldValue - newValue;
        
        // Distribute error to neighbors
        _addError(result, x + 1, y, error * 7 ~/ 16);
        _addError(result, x - 1, y + 1, error * 3 ~/ 16);
        _addError(result, x, y + 1, error * 5 ~/ 16);
        _addError(result, x + 1, y + 1, error * 1 ~/ 16);
      }
    }

    return result;
  }

  static void _addError(img.Image image, int x, int y, int error) {
    if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
      return;
    }
    
    final pixel = image.getPixel(x, y);
    final oldValue = img.getLuminance(pixel).toInt();
    final newValue = (oldValue + error).clamp(0, 255);
    image.setPixelRgb(x, y, newValue, newValue, newValue);
  }

  /// Pack a dithered image into 1-bit bytes (MSB first)
  static Uint8List _packBits(img.Image image) {
    final width = image.width;
    final height = image.height;
    final bytesPerLine = (width + 7) ~/ 8;
    final result = Uint8List(bytesPerLine * height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final isBlack = img.getLuminance(pixel) < 128;
        
        if (isBlack) {
          final byteIndex = y * bytesPerLine + (x ~/ 8);
          final bitIndex = 7 - (x % 8); // MSB first
          result[byteIndex] |= (1 << bitIndex);
        }
      }
    }

    return result;
  }

  /// Get image dimensions after processing
  static ({int width, int height}) getProcessedDimensions(
    Uint8List imageBytes, {
    int targetWidth = defaultWidth,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ImageProcessingException('Failed to decode image');
    }

    final aspectRatio = image.height / image.width;
    final height = (targetWidth * aspectRatio).round();
    
    return (width: targetWidth, height: height);
  }
}

class ImageProcessingException implements Exception {
  final String message;
  ImageProcessingException(this.message);
  
  @override
  String toString() => message;
}
