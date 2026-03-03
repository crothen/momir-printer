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

/// The 5 collectible icons - collect 3 of the same to win!
class MazeIcon {
  final String emoji;
  final String name;

  const MazeIcon(this.emoji, this.name);

  static const diamond = MazeIcon('💎', 'Diamond');
  static const skull = MazeIcon('💀', 'Skull');
  static const rat = MazeIcon('🐀', 'Rat');
  static const coin = MazeIcon('🪙', 'Coin');
  static const eye = MazeIcon('👁️', 'Eye');

  static const List<MazeIcon> all = [diamond, skull, rat, coin, eye];
}

/// A secret combines an icon (for collection) with a random effect
class MazeSecret {
  final MazeIcon icon;
  final String effect;

  const MazeSecret(this.icon, this.effect);

  String get emoji => icon.emoji;
  String get name => icon.name;

  /// All possible effects (randomly assigned to icons)
  static const List<String> allEffects = [
    'The next player can only MOVE (no mapping).',
    'Take an extra action immediately.',
    'Next time you MOVE, you must MAP first.',
    'Choose a player. Their next action must be MAP.',
    'Skip your next action.',
    'Ignore the next ⬆ (North) on a tile you play.',
    'Swap your next MOVE and MAP actions.',
    'Force the previous player to take back their last tile.',
    'Block the next effect that targets you.',
    'Look at the top 3 tiles, put them back in any order.',
    'Draw 2 tiles, keep 1, discard the other.',
    'Your next MAP action lets you place 2 tiles.',
    'Teleport to any tile with a 💀 on it.',
    'Teleport to any tile with a 💎 on it.',
    'Teleport to any tile with a 👁️ on it.',
    'Teleport to any tile with a 🐀 on it.',
    'Teleport to any tile with a 🪙 on it.',
    'Steal a collected icon from another player.',
    'Discard one of your collected icons to take 2 extra actions.',
    'Switch 2 placed tiles. Both must still form at least 1 passage.',
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

  // Game state
  bool _gameStarted = false;
  bool _isPrinting = false;
  bool _printingEffectSheet = false;
  bool _printedRules = false;
  bool _printedStartTile = false;
  MazeTile? _currentTile; // Current tile to print
  int _tilesPrinted = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🗺️ Maze Explorer'),
        actions: [
          if (_gameStarted)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _endGame,
              tooltip: 'End game',
            ),
        ],
      ),
      body: !_gameStarted ? _buildSetup() : _buildPrinting(),
    );
  }

  Widget _buildSetup() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.explore, size: 80, color: Colors.brown),
            const SizedBox(height: 24),
            const Text(
              'Maze Explorer',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Collect 3 matching icons to win!',
              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 8),
            const Text('💎 💀 🐀 🪙 👁️', style: TextStyle(fontSize: 24)),
            
            const SizedBox(height: 48),
            
            // Demo toggle
            Card(
              child: SwitchListTile(
                title: const Text('🎭 Demo Mode'),
                subtitle: Text(
                  _demoMode
                      ? 'Preview on screen (no printer)'
                      : 'Print to connected printer',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
                value: _demoMode,
                onChanged: (v) => setState(() => _demoMode = v),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Start button
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed:
                    (_bluetooth.currentState == BleConnectionState.connected || _demoMode)
                        ? _startGame
                        : null,
                icon: Icon(_demoMode ? Icons.play_arrow : Icons.print, size: 28),
                label: Text(
                  _demoMode
                      ? 'Start Demo'
                      : (_bluetooth.currentState == BleConnectionState.connected
                          ? 'Start Game'
                          : 'Connect printer first'),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
          ],
        ),
      ),
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

  void _startGame() {
    setState(() {
      _gameStarted = true;
      _printedRules = false;
      _printedStartTile = false;
      _tilesPrinted = 0;
      _currentTile = null;
    });
  }

  /// Generate a random tile on demand
  MazeTile _generateNextTile({bool isStartTile = false}) {
    if (isStartTile) {
      return MazeTile(
        shape: TileShape.crossroads,
        rotation: 0,
        hasNorthIndicator: true,
        northRotation: 0, // North is always up on start tile
        isStartTile: true,
      );
    }

    final enabledShapes = _enabledShapes.entries.where((e) => e.value).map((e) => e.key).toList();
    final shape = enabledShapes[_random.nextInt(enabledShapes.length)];
    final rotation = [0, 90, 180, 270][_random.nextInt(4)];

    MazeSecret? secret;
    if (_random.nextDouble() < _secretChance) {
      final icon = MazeIcon.all[_random.nextInt(MazeIcon.all.length)];
      final effect = MazeSecret.allEffects[_random.nextInt(MazeSecret.allEffects.length)];
      secret = MazeSecret(icon, effect);
    }

    final hasNorth = shape != TileShape.deadEnd && _random.nextDouble() < _northChance;
    final northRot = [0, 90, 180, 270][_random.nextInt(4)];

    return MazeTile(
      shape: shape,
      rotation: rotation,
      secret: secret,
      hasNorthIndicator: hasNorth,
      northRotation: northRot,
    );
  }

  Widget _buildPrinting() {
    // First, offer to print rules
    if (!_printedRules) {
      return _buildRulesPrint();
    }
    
    // Then, offer to print start tile
    if (!_printedStartTile) {
      return _buildStartTilePrint();
    }
    
    // Generate next tile if needed
    _currentTile ??= _generateNextTile();
    final tile = _currentTile!;

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
                    _printingEffectSheet ? 'Printing...' : 'Printing tile...',
                    style: const TextStyle(fontSize: 24, color: Colors.white),
                  ),
                ] else ...[
                  // Tile count
                  Text(
                    'Tile #${_tilesPrinted + 1}',
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
                      'Contains: ${tile.secret!.emoji}',
                      style: const TextStyle(fontSize: 18, color: Colors.amber),
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
  
  Widget _buildRulesPrint() {
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
                  const Text('Printing rules...', style: TextStyle(fontSize: 24, color: Colors.white)),
                ] else ...[
                  const Icon(Icons.description, size: 60, color: Colors.white70),
                  const SizedBox(height: 16),
                  const Text('Rules Sheet', style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _printRulesSheet,
                      icon: const Icon(Icons.print, size: 24),
                      label: Text(_demoMode ? 'Preview Rules' : 'Print Rules', style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _printedRules = true),
                    child: const Text('Skip →', style: TextStyle(fontSize: 16, color: Colors.white54)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStartTilePrint() {
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
                  const Text('Printing start tile...', style: TextStyle(fontSize: 24, color: Colors.white)),
                ] else ...[
                  const Icon(Icons.flag, size: 60, color: Colors.white70),
                  const SizedBox(height: 16),
                  const Text('Start Tile', style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Crossroads with North indicator', style: TextStyle(fontSize: 14, color: Colors.white54)),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _printStartTile,
                      icon: const Icon(Icons.print, size: 24),
                      label: Text(_demoMode ? 'Preview Start Tile' : 'Print Start Tile', style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _printedStartTile = true),
                    child: const Text('Skip →', style: TextStyle(fontSize: 16, color: Colors.white54)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printRulesSheet() async {
    setState(() => _isPrinting = true);
    
    final rulesImage = await _generateRulesSheet();
    await _printOrPreview(rulesImage, 'Rules');
    
    setState(() {
      _isPrinting = false;
      _printedRules = true;
    });
  }

  Future<void> _printStartTile() async {
    setState(() => _isPrinting = true);
    
    final startTile = _generateNextTile(isStartTile: true);
    final tileImage = await _generateTileImage(startTile);
    await _printOrPreview(tileImage, 'Start Tile');
    
    setState(() {
      _isPrinting = false;
      _printedStartTile = true;
    });
  }

  Future<void> _printCurrentTile() async {
    setState(() => _isPrinting = true);

    final tile = _currentTile!;
    
    // Print the tile
    final tileImage = await _generateTileImage(tile);
    await _printOrPreview(tileImage, 'Tile #${_tilesPrinted + 1}');

    // If tile has a secret, print the effect sheet too
    if (tile.secret != null) {
      setState(() => _printingEffectSheet = true);
      final effectImage = await _generateEffectSheet(tile.secret!);
      await _printOrPreview(effectImage, 'Effect');
    }

    setState(() {
      _isPrinting = false;
      _printingEffectSheet = false;
      _tilesPrinted++;
      _currentTile = null; // Generate new tile next time
    });
  }

  void _endGame() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Game?'),
        content: Text('You printed $_tilesPrinted tiles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetGame();
            },
            child: const Text('End'),
          ),
        ],
      ),
    );
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

  /// Generate a rules sheet
  Future<Uint8List> _generateRulesSheet() async {
    const width = 384.0;
    const height = 500.0;
    const padding = 24.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // White background
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xFFFFFFFF));

    // Border
    canvas.drawRect(
      Rect.fromLTWH(2, 2, width - 4, height - 4),
      Paint()..color = const Color(0xFF000000)..style = PaintingStyle.stroke..strokeWidth = 3,
    );

    double y = padding;

    // Title
    final titleStyle = ui.TextStyle(color: const Color(0xFF000000), fontSize: 32, fontWeight: ui.FontWeight.bold);
    final titlePara = _buildParagraph('MAZE EXPLORER', titleStyle, width - padding * 2, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(titlePara, Offset(padding, y));
    y += 45;

    // Win condition
    final winStyle = ui.TextStyle(color: const Color(0xFF000000), fontSize: 20, fontWeight: ui.FontWeight.bold);
    final winPara = _buildParagraph('🏆 Collect 3 matching icons!', winStyle, width - padding * 2, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(winPara, Offset(padding, y));
    y += 35;

    // Icons
    final iconsStyle = ui.TextStyle(color: const Color(0xFF000000), fontSize: 28);
    final iconsPara = _buildParagraph('💎  💀  🐀  🪙  👁️', iconsStyle, width - padding * 2, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(iconsPara, Offset(padding, y));
    y += 50;

    // Separator
    canvas.drawLine(Offset(padding, y), Offset(width - padding, y), Paint()..strokeWidth = 2);
    y += 20;

    // Actions
    final headerStyle = ui.TextStyle(color: const Color(0xFF000000), fontSize: 18, fontWeight: ui.FontWeight.bold);
    final bodyStyle = ui.TextStyle(color: const Color(0xFF000000), fontSize: 16);

    final moveHeader = _buildParagraph('MOVE', headerStyle, width - padding * 2);
    canvas.drawParagraph(moveHeader, Offset(padding, y));
    y += 25;
    final moveBody = _buildParagraph('Move 1 tile through the maze.', bodyStyle, width - padding * 2);
    canvas.drawParagraph(moveBody, Offset(padding, y));
    y += 35;

    final mapHeader = _buildParagraph('MAP', headerStyle, width - padding * 2);
    canvas.drawParagraph(mapHeader, Offset(padding, y));
    y += 25;
    final mapBody = _buildParagraph('Place a tile to expand the maze. If you can\'t place it, save for later. At least 1 path must connect.', bodyStyle, width - padding * 2);
    canvas.drawParagraph(mapBody, Offset(padding, y));
    y += 70;

    // North rule
    final northHeader = _buildParagraph('⬆ NORTH', headerStyle, width - padding * 2);
    canvas.drawParagraph(northHeader, Offset(padding, y));
    y += 25;
    final northBody = _buildParagraph('Tiles with ⬆ must be oriented toward North (this tile).', bodyStyle, width - padding * 2);
    canvas.drawParagraph(northBody, Offset(padding, y));
    y += 50;

    // Secrets
    final secretHeader = _buildParagraph('SECRETS', headerStyle, width - padding * 2);
    canvas.drawParagraph(secretHeader, Offset(padding, y));
    y += 25;
    final secretBody = _buildParagraph('When you land on a secret, read the effect aloud and do it. Then add the icon to your collection.', bodyStyle, width - padding * 2);
    canvas.drawParagraph(secretBody, Offset(padding, y));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Generate a foldable effect sheet for a secret
  Future<Uint8List> _generateEffectSheet(MazeSecret secret) async {
    const width = 384.0;
    const totalHeight = 450.0;
    const iconSectionHeight = totalHeight / 4;
    const padding = 24.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, totalHeight));

    // White background
    canvas.drawRect(Rect.fromLTWH(0, 0, width, totalHeight), Paint()..color = const Color(0xFFFFFFFF));

    // Border
    canvas.drawRect(
      Rect.fromLTWH(2, 2, width - 4, totalHeight - 4),
      Paint()..color = const Color(0xFF000000)..style = PaintingStyle.stroke..strokeWidth = 2,
    );

    // === ICON SECTION (top 1/4) ===
    // Big centered icon
    final emojiStyle = ui.TextStyle(color: const Color(0xFF000000), fontSize: 70);
    final emojiPara = _buildParagraph(secret.emoji, emojiStyle, width - padding * 2, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(emojiPara, Offset(padding, iconSectionHeight / 2 - 40));

    // === FOLD LINE ===
    _drawFoldLine(canvas, iconSectionHeight, width, '↓ FOLD ↓');

    // === TEXT SECTION ===
    final textY = iconSectionHeight + 25;

    // Icon + name header (big)
    final nameStyle = ui.TextStyle(color: const Color(0xFF000000), fontSize: 32, fontWeight: ui.FontWeight.bold);
    final namePara = _buildParagraph('${secret.emoji} ${secret.name}', nameStyle, width - padding * 2, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(namePara, Offset(padding, textY));

    // Separator
    canvas.drawLine(Offset(padding, textY + 50), Offset(width - padding, textY + 50), Paint()..strokeWidth = 2);

    // Effect text (bigger)
    final effectStyle = ui.TextStyle(color: const Color(0xFF000000), fontSize: 24);
    final effectPara = _buildParagraph(secret.effect, effectStyle, width - padding * 2, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(effectPara, Offset(padding, textY + 70));

    // Second fold line
    _drawFoldLine(canvas, totalHeight - 60, width, '↑ FOLD ↑');

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

    // If start tile, add START label
    if (tile.isStartTile) {
      _drawStartTileLabel(canvas, size, pathColor);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Draw a North indicator arrow - big and visible
  void _drawNorthIndicator(Canvas canvas, double size, int rotation, Color color) {
    canvas.save();
    canvas.translate(size - 45, 45); // Top-right corner
    canvas.rotate(rotation * pi / 180);

    // Draw background circle for visibility
    final bgColor = _blackBackground ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset.zero, 32, Paint()..color = bgColor);
    canvas.drawCircle(Offset.zero, 32, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);

    // Draw big arrow pointing up
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, -22); // Tip
    path.lineTo(-14, 12); // Bottom left
    path.lineTo(0, 4); // Notch
    path.lineTo(14, 12); // Bottom right
    path.close();

    canvas.drawPath(path, paint);

    canvas.restore();
  }

  /// Draw "START" label on the start tile
  void _drawStartTileLabel(Canvas canvas, double size, Color color) {
    final bgColor = _blackBackground ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    
    // Small label in center
    canvas.drawRect(
      Rect.fromLTWH(size / 2 - 50, size / 2 - 20, 100, 40),
      Paint()..color = bgColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(size / 2 - 50, size / 2 - 20, 100, 40),
      Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2,
    );

    final style = ui.TextStyle(color: color, fontSize: 20, fontWeight: ui.FontWeight.bold);
    final para = _buildParagraph('START', style, 90, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(para, Offset(size / 2 - 45, size / 2 - 12));
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
      _gameStarted = false;
      _isPrinting = false;
      _printingEffectSheet = false;
      _printedRules = false;
      _printedStartTile = false;
      _currentTile = null;
      _tilesPrinted = 0;
    });
  }
}
