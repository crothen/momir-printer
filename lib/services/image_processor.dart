import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Dithering algorithm options
enum DitheringAlgorithm {
  floydSteinberg,  // Classic, good for photos
  atkinson,        // Lighter, good for text/line art
  ordered,         // Bayer matrix, retro look
  threshold,       // Simple black/white cutoff
}

/// Processes images for thermal printing
class ImageProcessor {
  /// Standard thermal printer width in pixels
  static const defaultWidth = 384;

  /// Bottom padding in pixels (~80 = 1cm at 203 DPI)
  static const defaultBottomPadding = 80;

  /// Convert an image to 1-bit thermal printer format
  /// 
  /// Returns packed bytes (MSB first) ready to send to printer
  static Uint8List processForPrinting(
    Uint8List imageBytes, {
    int width = defaultWidth,
    DitheringAlgorithm algorithm = DitheringAlgorithm.atkinson,
    double contrast = 1.0,
    double brightness = 0.0,
    int bottomPadding = defaultBottomPadding,
  }) {
    // Decode the image
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ImageProcessingException('Failed to decode image');
    }

    // Resize to printer width, maintaining aspect ratio
    final resized = img.copyResize(image, width: width);
    
    // Convert to grayscale
    var grayscale = img.grayscale(resized);
    
    // Apply contrast and brightness adjustments
    if (contrast != 1.0 || brightness != 0.0) {
      grayscale = _adjustContrastBrightness(grayscale, contrast, brightness);
    }
    
    // Apply dithering
    final dithered = _applyDithering(grayscale, algorithm);
    
    // Add bottom padding (white space)
    final paddedImage = _addBottomPadding(dithered, bottomPadding);
    
    // Pack into bytes
    return _packBits(paddedImage);
  }
  
  /// Add white padding to the bottom of an image
  static img.Image _addBottomPadding(img.Image image, int padding) {
    if (padding <= 0) return image;
    
    final newHeight = image.height + padding;
    final padded = img.Image(width: image.width, height: newHeight);
    
    // Fill with white
    img.fill(padded, color: img.ColorRgb8(255, 255, 255));
    
    // Copy original image to top
    img.compositeImage(padded, image, dstX: 0, dstY: 0);
    
    return padded;
  }

  /// Create a PNG preview of the processed image
  static Uint8List createPreview(
    Uint8List imageBytes, {
    int width = defaultWidth,
    DitheringAlgorithm algorithm = DitheringAlgorithm.atkinson,
    double contrast = 1.0,
    double brightness = 0.0,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ImageProcessingException('Failed to decode image');
    }

    final resized = img.copyResize(image, width: width);
    var grayscale = img.grayscale(resized);
    
    if (contrast != 1.0 || brightness != 0.0) {
      grayscale = _adjustContrastBrightness(grayscale, contrast, brightness);
    }
    
    final dithered = _applyDithering(grayscale, algorithm);
    
    return Uint8List.fromList(img.encodePng(dithered));
  }

  /// Adjust contrast and brightness
  static img.Image _adjustContrastBrightness(img.Image image, double contrast, double brightness) {
    final result = img.Image.from(image);
    
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        var value = img.getLuminance(pixel).toDouble();
        
        // Apply brightness (-1 to 1 range, mapped to -255 to 255)
        value += brightness * 255;
        
        // Apply contrast (centered at 128)
        value = ((value - 128) * contrast) + 128;
        
        final clamped = value.clamp(0, 255).toInt();
        result.setPixelRgb(x, y, clamped, clamped, clamped);
      }
    }
    
    return result;
  }

  /// Apply selected dithering algorithm
  static img.Image _applyDithering(img.Image image, DitheringAlgorithm algorithm) {
    switch (algorithm) {
      case DitheringAlgorithm.floydSteinberg:
        return _floydSteinbergDither(image);
      case DitheringAlgorithm.atkinson:
        return _atkinsonDither(image);
      case DitheringAlgorithm.ordered:
        return _orderedDither(image);
      case DitheringAlgorithm.threshold:
        return _thresholdDither(image);
    }
  }

  /// Floyd-Steinberg dithering algorithm (best for photos)
  static img.Image _floydSteinbergDither(img.Image image) {
    final result = img.Image.from(image);
    final width = result.width;
    final height = result.height;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = result.getPixel(x, y);
        final oldValue = img.getLuminance(pixel).toInt();
        final newValue = oldValue < 128 ? 0 : 255;
        
        result.setPixelRgb(x, y, newValue, newValue, newValue);
        
        final error = oldValue - newValue;
        
        // Distribute error: 7/16 right, 3/16 bottom-left, 5/16 bottom, 1/16 bottom-right
        _addError(result, x + 1, y, error * 7 ~/ 16);
        _addError(result, x - 1, y + 1, error * 3 ~/ 16);
        _addError(result, x, y + 1, error * 5 ~/ 16);
        _addError(result, x + 1, y + 1, error * 1 ~/ 16);
      }
    }

    return result;
  }

  /// Atkinson dithering (lighter, better for text/line art)
  static img.Image _atkinsonDither(img.Image image) {
    final result = img.Image.from(image);
    final width = result.width;
    final height = result.height;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = result.getPixel(x, y);
        final oldValue = img.getLuminance(pixel).toInt();
        final newValue = oldValue < 128 ? 0 : 255;
        
        result.setPixelRgb(x, y, newValue, newValue, newValue);
        
        // Atkinson only propagates 6/8 of the error (lighter result)
        final error = (oldValue - newValue) ~/ 8;
        
        _addError(result, x + 1, y, error);
        _addError(result, x + 2, y, error);
        _addError(result, x - 1, y + 1, error);
        _addError(result, x, y + 1, error);
        _addError(result, x + 1, y + 1, error);
        _addError(result, x, y + 2, error);
      }
    }

    return result;
  }

  /// Ordered dithering using Bayer matrix (retro/stylized look)
  static img.Image _orderedDither(img.Image image) {
    final result = img.Image.from(image);
    
    // 4x4 Bayer matrix
    const bayer = [
      [ 0, 8, 2, 10],
      [12, 4, 14, 6],
      [ 3, 11, 1, 9],
      [15, 7, 13, 5],
    ];
    
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        final value = img.getLuminance(pixel).toInt();
        
        // Threshold from Bayer matrix (scaled to 0-255)
        final threshold = (bayer[y % 4][x % 4] * 16) + 8;
        final newValue = value > threshold ? 255 : 0;
        
        result.setPixelRgb(x, y, newValue, newValue, newValue);
      }
    }

    return result;
  }

  /// Simple threshold dithering
  static img.Image _thresholdDither(img.Image image, [int threshold = 128]) {
    final result = img.Image.from(image);
    
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        final value = img.getLuminance(pixel).toInt();
        final newValue = value < threshold ? 0 : 255;
        result.setPixelRgb(x, y, newValue, newValue, newValue);
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
    int bottomPadding = defaultBottomPadding,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ImageProcessingException('Failed to decode image');
    }

    final aspectRatio = image.height / image.width;
    final height = (targetWidth * aspectRatio).round() + bottomPadding;
    
    return (width: targetWidth, height: height);
  }
}

class ImageProcessingException implements Exception {
  final String message;
  ImageProcessingException(this.message);
  
  @override
  String toString() => message;
}
