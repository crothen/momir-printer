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
  deadEnd('⊥', 'Dead End', [Direction.north]),
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

/// A secret that can appear on a tile with a game effect
class MazeSecret {
  final String emoji;
  final String name;
  final String effect;

  const MazeSecret(this.emoji, this.name, this.effect);

  static const List<MazeSecret> allSecrets = [
    MazeSecret('💎', 'Gem', 'The next player can only MOVE (no mapping).'),
    MazeSecret('🗝️', 'Key', 'Take another turn immediately.'),
    MazeSecret('📜', 'Scroll', 'Next time you MOVE, you must MAP first.'),
    MazeSecret('🏺', 'Artifact', 'Choose a player. Their next action must be MAP.'),
    MazeSecret('💀', 'Skull', 'Skip your next turn.'),
    MazeSecret('🕯️', 'Candle', 'Ignore the next ⬆ (North) on a tile you play.'),
    MazeSecret('⚗️', 'Potion', 'Swap your next MOVE and MAP actions.'),
    MazeSecret('🗡️', 'Sword', 'Force the previous player to take back their last tile.'),
    MazeSecret('🛡️', 'Shield', 'Block the next effect that targets you.'),
    MazeSecret('🔮', 'Crystal', 'Look at the top 3 tiles, put them back in any order.'),
    MazeSecret('🪙', 'Coin', 'Draw 2 tiles, keep 1, discard the other.'),
    MazeSecret('🧪', 'Vial', 'Your next MAP action lets you place 2 tiles.'),
  ];
}

/// A generated maze tile ready to print
class MazeTile {
  final TileShape shape;
  final int rotation; // 0, 90, 180, 270 degrees
  final MazeSecret? secret;
  final int seed; // For reproducible random cave walls
  final bool hasNorthIndicator; // Must be oriented towards "North"
  final int northRotation; // Which way the North arrow points (0, 90, 180, 270)
  final bool isStartTile; // The first tile with rules

  MazeTile({
    required this.shape,
    required this.rotation,
    this.secret,
    int? seed,
    this.hasNorthIndicator = false,
    this.northRotation = 0,
    this.isStartTile = false,
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
  double _northChance = 0.5;
  bool _demoMode = false;
  bool _blackBackground = true;

  // Shape distribution (how many of each)
  Map<TileShape, bool> _enabledShapes = {
    TileShape.deadEnd: true,
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
  bool _printingEffectSheet = false; // True when printing the effect sheet after a tile

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
                Text(
                  '+ 1 starting tile (crossroads with rules)',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
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

        // Secrets & North indicators
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Secrets',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${(_secretChance * 100).round()}% chance per tile'),
                Slider(
                  value: _secretChance,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  label: '${(_secretChance * 100).round()}%',
                  onChanged: (v) => setState(() => _secretChance = v),
                ),
                const SizedBox(height: 16),
                const Text('⬆ North Indicators',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${(_northChance * 100).round()}% of tiles (dead ends excluded)'),
                Slider(
                  value: _northChance,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  label: '${(_northChance * 100).round()}%',
                  onChanged: (v) => setState(() => _northChance = v),
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
                      ? 'Paths carved into darkness (50% dither)'
                      : 'White background with dark paths',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
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
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
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
      case TileShape.deadEnd:
        return 'One exit only';
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

    // First tile is always a crossroads with North indicator (start tile)
    final startTile = MazeTile(
      shape: TileShape.crossroads,
      rotation: 0,
      hasNorthIndicator: true,
      northRotation: [0, 90, 180, 270][_random.nextInt(4)],
      isStartTile: true,
    );

    // Generate remaining tiles
    final regularTiles = List.generate(_tileCount, (i) {
      final shape = enabledShapes[_random.nextInt(enabledShapes.length)];
      final rotation = [0, 90, 180, 270][_random.nextInt(4)];

      MazeSecret? secret;
      if (_random.nextDouble() < _secretChance && secretIndex < shuffledSecrets.length) {
        secret = shuffledSecrets[secretIndex++];
      }

      // North indicator: 50% chance, but dead ends never have it
      final hasNorth = shape != TileShape.deadEnd && _random.nextDouble() < _northChance;
      final northRot = [0, 90, 180, 270][_random.nextInt(4)];

      return MazeTile(
        shape: shape,
        rotation: rotation,
        secret: secret,
        hasNorthIndicator: hasNorth,
        northRotation: northRot,
      );
    });

    _tiles = [startTile, ...regularTiles];

    setState(() {
      _isGenerating = false;
      _currentPrintIndex = 0;
      _printingEffectSheet = false;
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
                  Text(
                    _printingEffectSheet ? 'Printing effect sheet...' : 'Printing tile...',
                    style: const TextStyle(fontSize: 24, color: Colors.white),
                  ),
                ] else ...[
                  // Tile info
                  Text(
                    tile.isStartTile 
                        ? 'Starting Tile (Rules)'
                        : 'Tile ${_currentPrintIndex} of ${_tiles.length - 1}',
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
                    '${tile.shape.name}${tile.hasNorthIndicator ? ' ⬆' : ''}',
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  if (tile.secret != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Secret: ${tile.secret!.emoji} ${tile.secret!.name}',
                      style: const TextStyle(fontSize: 14, color: Colors.amber),
                    ),
                    Text(
                      '(will print effect sheet after tile)',
                      style: TextStyle(fontSize: 12, color: Colors.amber.withValues(alpha: 0.7)),
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
                        _demoMode ? 'Preview' : 'Print',
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
    final northCount = _tiles.where((t) => t.hasNorthIndicator).length;

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
                  '${_tiles.length} tiles printed\n$secretCount secrets hidden\n$northCount with ⬆ orientation',
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
    
    // Print the tile
    final tileImage = await _generateTileImage(tile);
    await _printOrPreview(tileImage, 'Tile ${_currentPrintIndex + 1}');

    // If tile has a secret, print the effect sheet too
    if (tile.secret != null) {
      setState(() => _printingEffectSheet = true);
      final effectImage = await _generateEffectSheet(tile.secret!);
      await _printOrPreview(effectImage, 'Effect: ${tile.secret!.name}');
    }

    setState(() {
      _isPrinting = false;
      _printingEffectSheet = false;
      _currentPrintIndex++;
    });
  }

  Future<void> _printOrPreview(Uint8List imageBytes, String title) async {
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
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const Text('(preview)',
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
  }

  /// Generate a foldable effect sheet for a secret
  /// Layout: Icon section (1/4 height) | --- fold line --- | Text section (3/4 height)
  /// Icon section is split: left half = icon, right half = empty
  Future<Uint8List> _generateEffectSheet(MazeSecret secret) async {
    const width = 384.0;
    const totalHeight = 480.0; // Tall enough to fold 3 times
    const iconSectionHeight = totalHeight / 4;
    const textSectionHeight = totalHeight * 3 / 4;
    const padding = 20.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, totalHeight));

    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, totalHeight),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // Border
    canvas.drawRect(
      Rect.fromLTWH(2, 2, width - 4, totalHeight - 4),
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // === ICON SECTION (top 1/4) ===
    // Left half: icon
    final emojiStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 60,
    );
    final emojiPara = _buildParagraph(secret.emoji, emojiStyle, width / 2 - padding);
    canvas.drawParagraph(emojiPara, Offset(padding, iconSectionHeight / 2 - 35));

    // Vertical divider in icon section
    canvas.drawLine(
      Offset(width / 2, padding),
      Offset(width / 2, iconSectionHeight - padding),
      Paint()
        ..color = const Color(0xFFCCCCCC)
        ..strokeWidth = 1,
    );

    // === FOLD LINE ===
    _drawFoldLine(canvas, iconSectionHeight, width, '↓ FOLD HERE ↓');

    // === TEXT SECTION (bottom 3/4) ===
    final textY = iconSectionHeight + 30;

    // Secret name
    final nameStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 28,
      fontWeight: ui.FontWeight.bold,
    );
    final namePara = _buildParagraph(secret.name, nameStyle, width - padding * 2, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(namePara, Offset(padding, textY));

    // Separator
    canvas.drawLine(
      Offset(padding, textY + 45),
      Offset(width - padding, textY + 45),
      Paint()..strokeWidth = 1,
    );

    // Effect text
    final effectStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 22,
    );
    final effectPara = _buildParagraph(secret.effect, effectStyle, width - padding * 2, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(effectPara, Offset(padding, textY + 60));

    // Second fold line (for triple fold)
    _drawFoldLine(canvas, iconSectionHeight + textSectionHeight / 2, width, '↑ FOLD ↑');

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), totalHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  void _drawFoldLine(Canvas canvas, double y, double width, String label) {
    final paint = Paint()
      ..color = const Color(0xFFAAAAAA)
      ..strokeWidth = 1;

    const dashWidth = 8.0;
    const dashSpace = 4.0;
    double x = 10;

    while (x < width - 10) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + dashSpace;
    }

    // Label
    final labelStyle = ui.TextStyle(
      color: const Color(0xFF999999),
      fontSize: 12,
    );
    final labelPara = _buildParagraph(label, labelStyle, width - 40, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(labelPara, Offset(20, y + 2));
  }

  /// Generate a cave-style maze tile image
  Future<Uint8List> _generateTileImage(MazeTile tile) async {
    const size = 384.0;
    const center = size / 2;
    const pathWidth = 60.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    final pathColor = _blackBackground ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

    // Fill background
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

    // Draw center chamber
    _drawCenterChamber(canvas, pathPaint, center, pathWidth * 0.8, rng);

    // Draw secret if present
    if (tile.secret != null) {
      _drawSecret(canvas, tile.secret!, center, pathWidth);
    }

    // Draw North indicator if present
    if (tile.hasNorthIndicator) {
      _drawNorthIndicator(canvas, size, tile.northRotation, pathColor);
    }

    // Draw border
    canvas.drawRect(
      Rect.fromLTWH(2, 2, size - 4, size - 4),
      Paint()
        ..color = pathColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Draw corner markers
    _drawCornerMarkers(canvas, size, pathColor);

    // If start tile, add rules text
    if (tile.isStartTile) {
      _drawStartTileRules(canvas, size, pathColor);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Draw a North indicator arrow
  void _drawNorthIndicator(Canvas canvas, double size, int rotation, Color color) {
    canvas.save();
    canvas.translate(size - 35, 35); // Top-right corner
    canvas.rotate(rotation * pi / 180);

    // Draw arrow pointing up
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, -15); // Tip
    path.lineTo(-10, 10); // Bottom left
    path.lineTo(0, 5); // Notch
    path.lineTo(10, 10); // Bottom right
    path.close();

    canvas.drawPath(path, paint);

    // Draw "N" below arrow
    final textStyle = ui.TextStyle(
      color: color,
      fontSize: 14,
      fontWeight: ui.FontWeight.bold,
    );
    final para = _buildParagraph('⬆', textStyle, 30, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(para, const Offset(-15, -8));

    canvas.restore();
  }

  /// Draw rules on the start tile
  void _drawStartTileRules(Canvas canvas, double size, Color color) {
    // Draw a small rules box in the center
    final bgColor = _blackBackground ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    
    canvas.drawRect(
      Rect.fromLTWH(size / 2 - 80, size / 2 - 50, 160, 100),
      Paint()..color = bgColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(size / 2 - 80, size / 2 - 50, 160, 100),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final titleStyle = ui.TextStyle(
      color: color,
      fontSize: 16,
      fontWeight: ui.FontWeight.bold,
    );
    final titlePara = _buildParagraph('MAZE EXPLORER', titleStyle, 150, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(titlePara, Offset(size / 2 - 75, size / 2 - 45));

    final rulesStyle = ui.TextStyle(
      color: color,
      fontSize: 11,
    );
    final rulesPara = _buildParagraph('Actions:\n• MOVE - travel\n• MAP - place tile\n⬆ = orient North', rulesStyle, 150, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(rulesPara, Offset(size / 2 - 75, size / 2 - 25));
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

    const segments = 12;
    final halfWidth = pathWidth / 2;
    final ruggedAmount = pathWidth * 0.15;

    final leftPoints = <Offset>[];
    final rightPoints = <Offset>[];

    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final basePoint = Offset(
        center + (edgeCenter.dx - center) * t,
        center + (edgeCenter.dy - center) * t,
      );

      final edgeFactor = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
      final leftRug = (rng.nextDouble() - 0.5) * ruggedAmount * 2 * edgeFactor;
      final rightRug = (rng.nextDouble() - 0.5) * ruggedAmount * 2 * edgeFactor;
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

    path.moveTo(leftPoints.first.dx, leftPoints.first.dy);
    for (int i = 1; i < leftPoints.length; i++) {
      path.lineTo(leftPoints[i].dx, leftPoints[i].dy);
    }
    for (int i = rightPoints.length - 1; i >= 0; i--) {
      path.lineTo(rightPoints[i].dx, rightPoints[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawCenterChamber(Canvas canvas, Paint paint, double center, double radius, Random rng) {
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

  void _drawSecret(Canvas canvas, MazeSecret secret, double center, double pathWidth) {
    canvas.drawCircle(
      Offset(center, center),
      pathWidth * 0.35,
      Paint()..color = const Color(0xFF333333),
    );

    final style = ui.TextStyle(fontSize: pathWidth * 0.5);
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
      ..pushStyle(style)
      ..addText(secret.emoji);

    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: pathWidth));
    canvas.drawParagraph(paragraph, Offset(center - pathWidth / 2, center - pathWidth * 0.3));
  }

  void _drawCornerMarkers(Canvas canvas, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const markerSize = 8.0;
    const offset = 12.0;

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

  void _drawDitheredBackground(Canvas canvas, double size) {
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;

    const blockSize = 2.0;

    for (double y = 0; y < size; y += blockSize * 2) {
      for (double x = 0; x < size; x += blockSize * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, blockSize, blockSize), paint);
        canvas.drawRect(Rect.fromLTWH(x + blockSize, y + blockSize, blockSize, blockSize), paint);
      }
    }
  }

  ui.Paragraph _buildParagraph(String text, ui.TextStyle style, double width, {ui.TextAlign textAlign = ui.TextAlign.left}) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: textAlign))
      ..pushStyle(style)
      ..addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: width));
    return paragraph;
  }

  void _resetGame() {
    setState(() {
      _tiles = [];
      _currentPrintIndex = 0;
      _printingEffectSheet = false;
    });
  }
}
