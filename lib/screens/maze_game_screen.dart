import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/printer_factory.dart';
import 'dart:ui' as ui;

class MazeGameScreen extends StatefulWidget {
  const MazeGameScreen({super.key});

  @override
  State<MazeGameScreen> createState() => _MazeGameScreenState();
}

/// Tile shapes define which edges connect through the center
enum TileShape {
  straight('I', 'Straight passage', [Direction.north, Direction.south]),
  corner('L', 'Corner turn', [Direction.north, Direction.east]),
  tJunction('T', 'T-junction', [Direction.north, Direction.east, Direction.west]),
  crossroads('+', 'Crossroads', [Direction.north, Direction.east, Direction.south, Direction.west]);

  final String symbol;
  final String name;
  final List<Direction> baseConnections;

  const TileShape(this.symbol, this.name, this.baseConnections);
}

enum Direction { north, east, south, west }

/// A secret that can appear on a tile
class MazeSecret {
  final String emoji;
  final String name;
  final String description;

  const MazeSecret(this.emoji, this.name, this.description);

  static const List<MazeSecret> allSecrets = [
    MazeSecret('💎', 'Gem', 'A sparkling gemstone'),
    MazeSecret('🗝️', 'Key', 'An ancient key'),
    MazeSecret('📜', 'Scroll', 'A mysterious scroll'),
    MazeSecret('🏺', 'Artifact', 'A strange artifact'),
    MazeSecret('💀', 'Skull', 'An ominous skull'),
    MazeSecret('🕯️', 'Candle', 'A flickering light'),
    MazeSecret('⚗️', 'Potion', 'A bubbling potion'),
    MazeSecret('🗡️', 'Sword', 'A hidden blade'),
    MazeSecret('🛡️', 'Shield', 'A dusty shield'),
    MazeSecret('🔮', 'Crystal', 'A glowing crystal'),
    MazeSecret('🪙', 'Coin', 'Ancient gold coin'),
    MazeSecret('🧪', 'Vial', 'A mysterious vial'),
  ];
}

/// A generated maze tile ready to print
class MazeTile {
  final TileShape shape;
  final int rotation; // 0, 90, 180, 270 degrees
  final MazeSecret? secret;
  final int seed; // For reproducible random cave walls

  MazeTile({
    required this.shape,
    required this.rotation,
    this.secret,
    int? seed,
  }) : seed = seed ?? Random().nextInt(999999);

  /// Get actual connections after rotation
  List<Direction> get connections {
    return shape.baseConnections.map((d) {
      int index = Direction.values.indexOf(d);
      int rotated = (index + (rotation ~/ 90)) % 4;
      return Direction.values[rotated];
    }).toList();
  }

  bool connectsTo(Direction dir) => connections.contains(dir);
}

class _MazeGameScreenState extends State<MazeGameScreen> {
  final _bluetooth = BleManager();
  final _random = Random();

  // Settings
  int _tileCount = 9;
  double _secretChance = 0.3;
  bool _demoMode = false;
  bool _blackBackground = true;

  // Shape distribution (how many of each)
  Map<TileShape, bool> _enabledShapes = {
    TileShape.straight: true,
    TileShape.corner: true,
    TileShape.tJunction: true,
    TileShape.crossroads: true,
  };

  // Generated tiles
  List<MazeTile> _tiles = [];
  int _currentPrintIndex = 0;
  bool _isPrinting = false;
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🗺️ Maze Explorer'),
        actions: [
          if (_tiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetGame,
              tooltip: 'New maze',
            ),
        ],
      ),
      body: _tiles.isEmpty ? _buildSetup() : _buildPrinting(),
    );
  }

  Widget _buildSetup() {
    final enabledCount = _enabledShapes.values.where((v) => v).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Tile count
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Number of Tiles',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed:
                          _tileCount > 4 ? () => setState(() => _tileCount--) : null,
                    ),
                    Text('$_tileCount',
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _tileCount < 25
                          ? () => setState(() => _tileCount++)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Tile shapes
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tile Shapes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...TileShape.values.map((shape) => CheckboxListTile(
                      title: Text('${shape.symbol} - ${shape.name}'),
                      subtitle: Text(_getShapeDescription(shape)),
                      value: _enabledShapes[shape],
                      onChanged: enabledCount > 1 || !_enabledShapes[shape]!
                          ? (v) => setState(() => _enabledShapes[shape] = v!)
                          : null,
                      dense: true,
                    )),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Secrets
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Secrets',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    '${(_secretChance * 100).round()}% of tiles will have a secret'),
                Slider(
                  value: _secretChance,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  label: '${(_secretChance * 100).round()}%',
                  onChanged: (v) => setState(() => _secretChance = v),
                ),
                Text(
                  'Expected: ~${(_tileCount * _secretChance).round()} secrets',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Visual options
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('🖤 Cave Style (Black Background)'),
                subtitle: Text(
                  _blackBackground
                      ? 'Paths carved into darkness'
                      : 'White background with dark paths',
                  style:
                      TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
                value: _blackBackground,
                onChanged: (v) => setState(() => _blackBackground = v),
              ),
              SwitchListTile(
                title: const Text('🎭 Demo Mode'),
                subtitle: Text(
                  _demoMode
                      ? 'Shows tiles on screen (no printer needed)'
                      : 'Requires connected printer',
                  style:
                      TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
                value: _demoMode,
                onChanged: (v) => setState(() => _demoMode = v),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Generate button
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed:
                (_bluetooth.currentState == BleConnectionState.connected || _demoMode)
                    ? _generateTiles
                    : null,
            icon: Icon(_isGenerating
                ? Icons.hourglass_empty
                : (_demoMode ? Icons.play_arrow : Icons.print)),
            label: Text(
              _isGenerating
                  ? 'Generating...'
                  : (_demoMode
                      ? 'Generate & Preview'
                      : (_bluetooth.currentState == BleConnectionState.connected
                          ? 'Generate & Print'
                          : 'Connect printer first')),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  String _getShapeDescription(TileShape shape) {
    switch (shape) {
      case TileShape.straight:
        return 'Connects two opposite sides';
      case TileShape.corner:
        return 'Connects two adjacent sides';
      case TileShape.tJunction:
        return 'Connects three sides';
      case TileShape.crossroads:
        return 'Connects all four sides';
    }
  }

  void _generateTiles() {
    setState(() => _isGenerating = true);

    final enabledShapes =
        _enabledShapes.entries.where((e) => e.value).map((e) => e.key).toList();

    final shuffledSecrets = List<MazeSecret>.from(MazeSecret.allSecrets)..shuffle(_random);
    int secretIndex = 0;

    _tiles = List.generate(_tileCount, (i) {
      final shape = enabledShapes[_random.nextInt(enabledShapes.length)];
      final rotation = [0, 90, 180, 270][_random.nextInt(4)];

      MazeSecret? secret;
      if (_random.nextDouble() < _secretChance && secretIndex < shuffledSecrets.length) {
        secret = shuffledSecrets[secretIndex++];
      }

      return MazeTile(shape: shape, rotation: rotation, secret: secret);
    });

    setState(() {
      _isGenerating = false;
      _currentPrintIndex = 0;
    });
  }

  Widget _buildPrinting() {
    if (_currentPrintIndex >= _tiles.length) {
      return _buildComplete();
    }

    final tile = _tiles[_currentPrintIndex];

    return Container(
      color: const Color(0xFF2a2a3a),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isPrinting) ...[
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 24),
                  const Text('Printing...',
                      style: TextStyle(fontSize: 24, color: Colors.white)),
                ] else ...[
                  // Tile info
                  Text(
                    'Tile ${_currentPrintIndex + 1} of ${_tiles.length}',
                    style: const TextStyle(fontSize: 20, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),

                  // Shape indicator
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        tile.shape.symbol,
                        style: const TextStyle(
                            fontSize: 48,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${tile.shape.name} (${tile.rotation}°)',
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  if (tile.secret != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Contains: ${tile.secret!.emoji} ${tile.secret!.name}',
                      style: const TextStyle(fontSize: 14, color: Colors.amber),
                    ),
                  ],

                  const SizedBox(height: 48),

                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: _printCurrentTile,
                      icon: const Icon(Icons.print, size: 28),
                      label: Text(
                        _demoMode ? 'Preview Tile' : 'Print Tile',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComplete() {
    final secretCount = _tiles.where((t) => t.secret != null).length;

    return Container(
      color: const Color(0xFF1a3a1a),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 80, color: Colors.green),
                const SizedBox(height: 24),
                const Text(
                  'Maze Complete!',
                  style: TextStyle(
                      fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  '${_tiles.length} tiles printed\n$secretCount secrets hidden',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                ElevatedButton.icon(
                  onPressed: _resetGame,
                  icon: const Icon(Icons.refresh),
                  label: const Text('New Maze'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printCurrentTile() async {
    setState(() => _isPrinting = true);

    final tile = _tiles[_currentPrintIndex];
    final imageBytes = await _generateTileImage(tile);

    if (_demoMode) {
      final ditheredBytes = ImageProcessor.createPreview(imageBytes);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.grey[800],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[900],
                child: Row(
                  children: [
                    const Icon(Icons.preview, size: 20, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text('Tile ${_currentPrintIndex + 1}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white)),
                    const Spacer(),
                    const Text('(print preview)',
                        style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
              Container(
                color: Colors.white,
                child: Image.memory(ditheredBytes,
                    fit: BoxFit.fitWidth, filterQuality: FilterQuality.none),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Continue'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final printer = UnifiedPrinter(_bluetooth, _bluetooth.connectedDeviceName);
      final printData = ImageProcessor.processForPrinting(imageBytes);
      final dims = ImageProcessor.getProcessedDimensions(imageBytes);

      await printer.printFullImage(
        printData,
        ImageProcessor.defaultWidth,
        dims.height,
        density: 0.65,
        feedLines: 80,
      );

      await Future.delayed(const Duration(seconds: 2));
    }

    setState(() {
      _isPrinting = false;
      _currentPrintIndex++;
    });
  }

  /// Generate a cave-style maze tile image
  Future<Uint8List> _generateTileImage(MazeTile tile) async {
    const size = 384.0; // Square tile matching printer width
    const center = size / 2;
    const pathWidth = 60.0;
    const edgePathWidth = pathWidth; // Width at edge for connection alignment

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    final pathColor = _blackBackground ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

    // Fill background - use dithered pattern for black to reduce printer heat
    if (_blackBackground) {
      _drawDitheredBackground(canvas, size);
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size, size),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }

    // Draw rugged cave paths
    final pathPaint = Paint()
      ..color = pathColor
      ..style = PaintingStyle.fill;

    final rng = Random(tile.seed);

    // Draw paths for each connection
    for (final dir in tile.connections) {
      _drawRuggedPath(canvas, pathPaint, dir, center, size, pathWidth, rng);
    }

    // Draw center chamber (slightly larger, irregular)
    _drawCenterChamber(canvas, pathPaint, center, pathWidth * 0.8, rng);

    // Draw secret if present
    if (tile.secret != null) {
      _drawSecret(canvas, tile.secret!, center, pathWidth);
    }

    // Draw border
    canvas.drawRect(
      Rect.fromLTWH(2, 2, size - 4, size - 4),
      Paint()
        ..color = pathColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Draw corner markers for alignment
    _drawCornerMarkers(canvas, size, pathColor);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Draw a rugged cave-style path from center to edge
  void _drawRuggedPath(
    Canvas canvas,
    Paint paint,
    Direction dir,
    double center,
    double size,
    double pathWidth,
    Random rng,
  ) {
    final path = Path();

    // Define start (center) and end (edge middle) points
    late Offset edgeCenter;
    late Offset perpendicular;

    switch (dir) {
      case Direction.north:
        edgeCenter = Offset(center, 0);
        perpendicular = const Offset(1, 0);
        break;
      case Direction.south:
        edgeCenter = Offset(center, size);
        perpendicular = const Offset(1, 0);
        break;
      case Direction.east:
        edgeCenter = Offset(size, center);
        perpendicular = const Offset(0, 1);
        break;
      case Direction.west:
        edgeCenter = Offset(0, center);
        perpendicular = const Offset(0, 1);
        break;
    }

    // Generate rugged edges
    const segments = 12;
    final halfWidth = pathWidth / 2;
    final ruggedAmount = pathWidth * 0.15; // How much the walls vary

    final leftPoints = <Offset>[];
    final rightPoints = <Offset>[];

    for (int i = 0; i <= segments; i++) {
      final t = i / segments;

      // Interpolate from center to edge
      final basePoint = Offset(
        center + (edgeCenter.dx - center) * t,
        center + (edgeCenter.dy - center) * t,
      );

      // Add ruggedness (less at edges for clean connection)
      final edgeFactor = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
      final leftRug = (rng.nextDouble() - 0.5) * ruggedAmount * 2 * edgeFactor;
      final rightRug = (rng.nextDouble() - 0.5) * ruggedAmount * 2 * edgeFactor;

      // Widen slightly in the middle for natural cave look
      final widthMod = 1.0 + sin(t * pi) * 0.2;

      leftPoints.add(Offset(
        basePoint.dx + perpendicular.dx * (halfWidth * widthMod + leftRug),
        basePoint.dy + perpendicular.dy * (halfWidth * widthMod + leftRug),
      ));

      rightPoints.add(Offset(
        basePoint.dx - perpendicular.dx * (halfWidth * widthMod + rightRug),
        basePoint.dy - perpendicular.dy * (halfWidth * widthMod + rightRug),
      ));
    }

    // Build path
    path.moveTo(leftPoints.first.dx, leftPoints.first.dy);
    for (int i = 1; i < leftPoints.length; i++) {
      path.lineTo(leftPoints[i].dx, leftPoints[i].dy);
    }

    // Connect to right side (reversed)
    for (int i = rightPoints.length - 1; i >= 0; i--) {
      path.lineTo(rightPoints[i].dx, rightPoints[i].dy);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  /// Draw irregular center chamber
  void _drawCenterChamber(
    Canvas canvas,
    Paint paint,
    double center,
    double radius,
    Random rng,
  ) {
    final path = Path();
    const points = 16;

    for (int i = 0; i < points; i++) {
      final angle = (i / points) * 2 * pi;
      final variation = radius * 0.2 * (rng.nextDouble() - 0.5);
      final r = radius + variation;

      final x = center + cos(angle) * r;
      final y = center + sin(angle) * r;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  /// Draw secret icon in center
  void _drawSecret(Canvas canvas, MazeSecret secret, double center, double pathWidth) {
    // Draw a subtle circle behind the emoji
    canvas.drawCircle(
      Offset(center, center),
      pathWidth * 0.35,
      Paint()..color = const Color(0xFF333333),
    );

    // Draw emoji
    final style = ui.TextStyle(
      fontSize: pathWidth * 0.5,
    );

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
      ..pushStyle(style)
      ..addText(secret.emoji);

    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: pathWidth));

    canvas.drawParagraph(
      paragraph,
      Offset(center - pathWidth / 2, center - pathWidth * 0.3),
    );
  }

  /// Draw corner alignment markers
  void _drawCornerMarkers(Canvas canvas, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const markerSize = 8.0;
    const offset = 12.0;

    // Small triangles in corners
    for (final corner in [
      Offset(offset, offset),
      Offset(size - offset, offset),
      Offset(offset, size - offset),
      Offset(size - offset, size - offset),
    ]) {
      final path = Path();
      path.moveTo(corner.dx, corner.dy - markerSize / 2);
      path.lineTo(corner.dx + markerSize / 2, corner.dy + markerSize / 2);
      path.lineTo(corner.dx - markerSize / 2, corner.dy + markerSize / 2);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  /// Draw a 50% dithered background to reduce printer heat
  void _drawDitheredBackground(Canvas canvas, double size) {
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;

    // Checkerboard pattern - 50% coverage, 2x2 pixel blocks for visibility
    const blockSize = 2.0;
    
    for (double y = 0; y < size; y += blockSize * 2) {
      for (double x = 0; x < size; x += blockSize * 2) {
        // Draw two diagonal blocks per 4x4 cell
        canvas.drawRect(
          Rect.fromLTWH(x, y, blockSize, blockSize),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(x + blockSize, y + blockSize, blockSize, blockSize),
          paint,
        );
      }
    }
  }

  void _resetGame() {
    setState(() {
      _tiles = [];
      _currentPrintIndex = 0;
    });
  }
}
