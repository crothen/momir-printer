import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/werewolf_game.dart';
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/printer_factory.dart';
import 'dart:ui' as ui;

class WerewolfScreen extends StatefulWidget {
  const WerewolfScreen({super.key});

  @override
  State<WerewolfScreen> createState() => _WerewolfScreenState();
}

enum GamePhase { setup, printing, night, day, gameOver }

class _WerewolfScreenState extends State<WerewolfScreen> {
  final _bluetooth = BleManager();
  
  GamePhase _phase = GamePhase.setup;
  WerewolfGame? _game;
  
  // Setup options
  int _playerCount = 8;
  int _werewolfCount = 2;
  bool _includeSeer = true;
  bool _includeWitch = false;
  bool _includeHunter = false;
  bool _includeBodyguard = false;
  bool _includeCupid = false;
  bool _demoMode = false;
  
  // Night phase
  int _currentNightActionIndex = 0;
  List<WerewolfRole> _nightActions = [];
  int? _selectedTarget;
  
  // Printing
  int _printingPlayerIndex = 0;
  bool _isPrinting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐺 Werewolf'),
        actions: [
          if (_phase != GamePhase.setup)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetGame,
              tooltip: 'New game',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case GamePhase.setup:
        return _buildSetup();
      case GamePhase.printing:
        return _buildPrinting();
      case GamePhase.night:
        return _buildNight();
      case GamePhase.day:
        return _buildDay();
      case GamePhase.gameOver:
        return _buildGameOver();
    }
  }

  // ============ SETUP PHASE ============

  Widget _buildSetup() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Player count
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Players', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _playerCount > 5 ? () => setState(() => _playerCount--) : null,
                    ),
                    Text('$_playerCount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _playerCount < 20 ? () => setState(() => _playerCount++) : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Werewolf count
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🐺 Werewolves', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _werewolfCount > 1 ? () => setState(() => _werewolfCount--) : null,
                    ),
                    Text('$_werewolfCount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _werewolfCount < (_playerCount ~/ 3) 
                          ? () => setState(() => _werewolfCount++) 
                          : null,
                    ),
                  ],
                ),
                Text(
                  'Recommended: ${_recommendedWerewolves()} for $_playerCount players',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Special roles
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Special Roles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildRoleToggle('👁️ Seer', 'See if someone is a wolf', _includeSeer, (v) => setState(() => _includeSeer = v)),
                _buildRoleToggle('🧙 Witch', 'Heal or poison once per game', _includeWitch, (v) => setState(() => _includeWitch = v)),
                _buildRoleToggle('🏹 Hunter', 'Take someone with you when you die', _includeHunter, (v) => setState(() => _includeHunter = v)),
                _buildRoleToggle('🛡️ Bodyguard', 'Protect someone each night', _includeBodyguard, (v) => setState(() => _includeBodyguard = v)),
                _buildRoleToggle('💘 Cupid', 'Link two lovers on night one', _includeCupid, (v) => setState(() => _includeCupid = v)),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Role summary
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Role Summary', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_getRoleSummary()),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Demo mode toggle
        Card(
          child: SwitchListTile(
            title: const Text('🎭 Demo Mode'),
            subtitle: Text(
              _demoMode 
                  ? 'Shows prints on screen (no printer needed)' 
                  : 'Requires connected printer',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
            value: _demoMode,
            onChanged: (v) => setState(() => _demoMode = v),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Start button
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: (_bluetooth.currentState == BleConnectionState.connected || _demoMode)
                ? _startGame 
                : null,
            icon: Icon(_demoMode ? Icons.play_arrow : Icons.print, size: 28),
            label: Text(
              _demoMode
                  ? 'Start Demo'
                  : (_bluetooth.currentState == BleConnectionState.connected
                      ? 'Print Roles & Start'
                      : 'Connect printer first'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleToggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
      value: value,
      onChanged: onChanged,
      dense: true,
    );
  }

  int _recommendedWerewolves() {
    if (_playerCount <= 6) return 1;
    if (_playerCount <= 9) return 2;
    if (_playerCount <= 12) return 3;
    return 4;
  }

  String _getRoleSummary() {
    final parts = <String>[];
    parts.add('🐺 $_werewolfCount Werewolves');
    if (_includeSeer) parts.add('👁️ 1 Seer');
    if (_includeWitch) parts.add('🧙 1 Witch');
    if (_includeHunter) parts.add('🏹 1 Hunter');
    if (_includeBodyguard) parts.add('🛡️ 1 Bodyguard');
    if (_includeCupid) parts.add('💘 1 Cupid');
    
    int specialCount = (_includeSeer ? 1 : 0) + (_includeWitch ? 1 : 0) + 
                       (_includeHunter ? 1 : 0) + (_includeBodyguard ? 1 : 0) + 
                       (_includeCupid ? 1 : 0);
    int villagerCount = _playerCount - _werewolfCount - specialCount;
    if (villagerCount > 0) {
      parts.add('🏠 $villagerCount Villagers');
    }
    parts.add('⛤ 1 Mayor (random villager)');
    
    return parts.join('\n');
  }

  void _startGame() {
    // Build role configs
    final configs = <RoleConfig>[];
    if (_includeSeer) configs.add(RoleConfig(WerewolfRole.seer, 1));
    if (_includeWitch) configs.add(RoleConfig(WerewolfRole.witch, 1));
    if (_includeHunter) configs.add(RoleConfig(WerewolfRole.hunter, 1));
    if (_includeBodyguard) configs.add(RoleConfig(WerewolfRole.bodyguard, 1));
    if (_includeCupid) configs.add(RoleConfig(WerewolfRole.cupid, 1));

    _game = WerewolfGame.create(
      playerCount: _playerCount,
      roleConfigs: configs,
      werewolfCount: _werewolfCount,
    );

    setState(() {
      _phase = GamePhase.printing;
      _printingPlayerIndex = 0;
      _showReadyForNight = false;
    });
  }

  // ============ PRINTING PHASE ============

  Widget _buildPrinting() {
    final player = _game!.players[_printingPlayerIndex];
    final isLastPlayer = _printingPlayerIndex >= _game!.players.length - 1;
    
    return Container(
      color: const Color(0xFF1a1a2e),
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
                    'Printing...',
                    style: const TextStyle(fontSize: 24, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Take your slip and fold it!',
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ] else ...[
                  // Big seat number
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Center(
                      child: Text(
                        '${player.seatPosition}',
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  const Text(
                    'Everyone close your eyes!',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Only SEAT ${player.seatPosition} may look',
                    style: const TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 48),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 72,
                    child: ElevatedButton.icon(
                      onPressed: _printCurrentRole,
                      icon: const Icon(Icons.print, size: 32),
                      label: Text(
                        'Print Seat ${player.seatPosition}',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  Text(
                    '${_printingPlayerIndex + 1} of ${_game!.players.length}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printCurrentRole() async {
    setState(() => _isPrinting = true);
    
    final player = _game!.players[_printingPlayerIndex];
    
    if (_demoMode) {
      // Generate and apply Atkinson dithering for realistic preview
      final imageBytes = await _generateRoleSlipImage(player);
      final ditheredBytes = ImageProcessor.createPreview(imageBytes);
      setState(() => _isPrinting = false);
      
      if (!mounted) return;
      
      // Show preview dialog
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
                    Text('Demo: Seat ${player.seatPosition}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    const Spacer(),
                    const Text('(print preview)', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
              Container(
                color: Colors.white,
                child: Image.memory(ditheredBytes, fit: BoxFit.fitWidth, filterQuality: FilterQuality.none),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Got it, fold & continue'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      await _printRoleSlip(player);
      // Short delay to let them grab the slip
      await Future.delayed(const Duration(seconds: 2));
    }
    
    setState(() {
      _isPrinting = false;
      if (_printingPlayerIndex < _game!.players.length - 1) {
        _printingPlayerIndex++;
      } else {
        // All printed, show "Start Night" screen
        _phase = GamePhase.night;
        _showReadyForNight = true;
      }
    });
  }
  
  bool _showReadyForNight = false;

  Future<void> _printRoleSlip(WerewolfPlayer player) async {
    final printer = UnifiedPrinter(_bluetooth, _bluetooth.connectedDeviceName);
    
    // Generate the role slip image
    final imageBytes = await _generateRoleSlipImage(player);
    
    // Process for thermal printing
    final printData = ImageProcessor.processForPrinting(imageBytes);
    final dims = ImageProcessor.getProcessedDimensions(imageBytes);
    
    await printer.printFullImage(
      printData,
      ImageProcessor.defaultWidth,
      dims.height,
      density: 0.65,
      feedLines: 80,
    );
  }

  Future<Uint8List> _generateRoleSlipImage(WerewolfPlayer player) async {
    // Create image using Canvas
    const width = 384.0;
    const height = 580.0;
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    
    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    
    final blackPaint = Paint()..color = const Color(0xFF000000);
    
    // Draw border
    canvas.drawRect(
      Rect.fromLTWH(4, 4, width - 8, height - 8),
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    
    // Padding from border edge
    const padding = 28.0;
    final textWidth = width - (padding * 2);
    
    // Header section with seat number and name
    final headerStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 36,
      fontWeight: ui.FontWeight.bold,
    );
    
    // Seat number
    final seatPara = _buildParagraph('SEAT ${player.seatPosition}', headerStyle, textWidth);
    canvas.drawParagraph(seatPara, Offset(padding, 20));
    
    // Player name (large)
    final nameStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 40,
      fontWeight: ui.FontWeight.bold,
    );
    final namePara = _buildParagraph(
      player.isMayor ? '${player.name}  ⛤' : player.name, 
      nameStyle, 
      textWidth
    );
    canvas.drawParagraph(namePara, Offset(padding, 70));
    
    // First fold line
    _drawFoldLine(canvas, 140, width);
    
    // Fold instruction
    final foldStyle = ui.TextStyle(
      color: const Color(0xFF666666),
      fontSize: 18,
    );
    final foldPara = _buildParagraph('↓ FOLD HERE ↓', foldStyle, textWidth, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(foldPara, Offset(padding, 145));
    
    // Separator line
    canvas.drawLine(
      Offset(padding, 175),
      Offset(width - padding, 175),
      Paint()..strokeWidth = 1,
    );
    
    // Role section (hidden when folded)
    // Role emoji
    final emojiStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 72,
    );
    final emojiPara = _buildParagraph(player.role.emoji, emojiStyle, textWidth);
    canvas.drawParagraph(emojiPara, Offset((width - 80) / 2, 200));
    
    // Role name
    final roleStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 34,
      fontWeight: ui.FontWeight.bold,
    );
    final rolePara = _buildParagraph(player.role.displayName, roleStyle, textWidth, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(rolePara, Offset(padding, 290));
    
    // Role description
    final descStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 18,
    );
    final descPara = _buildParagraph(player.role.description, descStyle, textWidth, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(descPara, Offset(padding, 345));
    
    // Wake cue info
    if (player.role.wakeCue.isNotEmpty) {
      final cueStyle = ui.TextStyle(
        color: const Color(0xFF000000),
        fontSize: 16,
        fontStyle: ui.FontStyle.italic,
      );
      final cuePara = _buildParagraph('Listen for: ${player.role.wakeCue}', cueStyle, textWidth, textAlign: ui.TextAlign.center);
      canvas.drawParagraph(cuePara, Offset(padding, 455));
    }
    
    // Bottom separator
    canvas.drawLine(
      Offset(padding, 500),
      Offset(width - padding, 500),
      Paint()..strokeWidth = 1,
    );
    
    // Bottom fold line
    _drawFoldLine(canvas, 510, width);
    
    final foldPara2 = _buildParagraph('↑ FOLD HERE ↑', foldStyle, textWidth, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(foldPara2, Offset(padding, 520));
    
    // Convert to image
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }

  ui.Paragraph _buildParagraph(String text, ui.TextStyle style, double width, {ui.TextAlign textAlign = ui.TextAlign.left}) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: textAlign))
      ..pushStyle(style)
      ..addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: width));
    return paragraph;
  }

  void _drawFoldLine(Canvas canvas, double y, double width) {
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
  }

  void _startNightPhase() {
    _game!.startNight();
    _nightActions = _game!.getNightActions();
    _currentNightActionIndex = 0;
    _selectedTarget = null;
    
    setState(() => _phase = GamePhase.night);
  }

  // ============ NIGHT PHASE ============

  Widget _buildNight() {
    // Show "ready for night" screen after all roles are printed
    if (_showReadyForNight) {
      return Container(
        color: const Color(0xFF1a1a2e),
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
                    'All roles printed!',
                    style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Everyone should have their slip.\nRead your role secretly, then fold it.',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showReadyForNight = false;
                        });
                        _startNightPhase();
                      },
                      icon: const Icon(Icons.nightlight_round, size: 28),
                      label: const Text('Start First Night', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    if (_currentNightActionIndex >= _nightActions.length) {
      // Night is over, resolve and go to day
      return _buildNightResolution();
    }
    
    final currentRole = _nightActions[_currentNightActionIndex];
    
    return Container(
      color: const Color(0xFF1a1a2e),
      child: SafeArea(
        child: Column(
          children: [
            // Night header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.nightlight_round, color: Colors.white70, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    'Night ${_game!.dayNumber + 1}',
                    style: const TextStyle(color: Colors.white70, fontSize: 24),
                  ),
                ],
              ),
            ),
            
            const Spacer(),
            
            // Current role action
            Column(
              children: [
                Text(
                  currentRole.emoji,
                  style: const TextStyle(fontSize: 80),
                ),
                const SizedBox(height: 16),
                Text(
                  '${currentRole.displayName}, wake up',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _getNightActionInstruction(currentRole),
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Player selection grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildPlayerGrid(currentRole),
            ),
            
            const Spacer(),
            
            // Confirm button
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _playWakeSound(currentRole),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('🔊 Play Sound'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _selectedTarget != null || !_roleRequiresTarget(currentRole)
                          ? _confirmNightAction
                          : null,
                      child: const Text('Confirm & Close Eyes'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerGrid(WerewolfRole actingRole) {
    final selectablePlayers = _getSelectablePlayers(actingRole);
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: selectablePlayers.map((player) {
        final isSelected = _selectedTarget == player.seatPosition;
        return GestureDetector(
          onTap: () => setState(() => _selectedTarget = player.seatPosition),
          child: Container(
            width: 100,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.red : Colors.white12,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.red : Colors.white24,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${player.seatPosition}',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  player.name.split(' ').last, // Just last name to fit
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<WerewolfPlayer> _getSelectablePlayers(WerewolfRole actingRole) {
    switch (actingRole) {
      case WerewolfRole.werewolf:
        // Can't target other werewolves
        return _game!.alivePlayers.where((p) => p.role != WerewolfRole.werewolf).toList();
      case WerewolfRole.bodyguard:
        // Can protect anyone alive
        return _game!.alivePlayers;
      case WerewolfRole.seer:
        // Can see anyone alive
        return _game!.alivePlayers;
      default:
        return _game!.alivePlayers;
    }
  }

  String _getNightActionInstruction(WerewolfRole role) {
    switch (role) {
      case WerewolfRole.werewolf:
        return 'Choose your victim';
      case WerewolfRole.seer:
        return 'Choose someone to investigate';
      case WerewolfRole.witch:
        return 'Use your potion or skip';
      case WerewolfRole.bodyguard:
        return 'Choose someone to protect';
      case WerewolfRole.cupid:
        return 'Choose two lovers';
      default:
        return '';
    }
  }

  bool _roleRequiresTarget(WerewolfRole role) {
    switch (role) {
      case WerewolfRole.werewolf:
      case WerewolfRole.seer:
      case WerewolfRole.bodyguard:
        return true;
      default:
        return false;
    }
  }

  void _playWakeSound(WerewolfRole role) {
    // Vibrate pattern based on role
    switch (role) {
      case WerewolfRole.werewolf:
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 200), () => HapticFeedback.heavyImpact());
        Future.delayed(const Duration(milliseconds: 400), () => HapticFeedback.heavyImpact());
        break;
      case WerewolfRole.seer:
        HapticFeedback.mediumImpact();
        break;
      case WerewolfRole.witch:
        HapticFeedback.lightImpact();
        Future.delayed(const Duration(milliseconds: 100), () => HapticFeedback.lightImpact());
        break;
      case WerewolfRole.bodyguard:
        HapticFeedback.heavyImpact();
        break;
      default:
        HapticFeedback.mediumImpact();
    }
    
    // TODO: Add actual audio playback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔊 ${role.wakeCue.toUpperCase()}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _confirmNightAction() {
    final currentRole = _nightActions[_currentNightActionIndex];
    
    // Record the action
    switch (currentRole) {
      case WerewolfRole.werewolf:
        _game!.nightKillTarget = _selectedTarget;
        break;
      case WerewolfRole.bodyguard:
        if (_selectedTarget != null) {
          _game!.getPlayerBySeat(_selectedTarget!)?.isProtected = true;
        }
        break;
      case WerewolfRole.seer:
        // Show result to seer
        if (_selectedTarget != null) {
          final target = _game!.getPlayerBySeat(_selectedTarget!);
          if (target != null) {
            final isWolf = target.role == WerewolfRole.werewolf;
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(target.name),
                content: Text(isWolf ? '🐺 IS a Werewolf!' : '✓ Is NOT a Werewolf'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close Eyes'),
                  ),
                ],
              ),
            ).then((_) => _moveToNextNightAction());
            return;
          }
        }
        break;
      default:
        break;
    }
    
    _moveToNextNightAction();
  }

  void _moveToNextNightAction() {
    setState(() {
      _currentNightActionIndex++;
      _selectedTarget = null;
    });
  }

  Widget _buildNightResolution() {
    return Container(
      color: const Color(0xFF1a1a2e),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wb_sunny, color: Colors.orange, size: 80),
            const SizedBox(height: 24),
            const Text(
              'Dawn breaks...',
              style: TextStyle(color: Colors.white, fontSize: 28),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _resolveNightAndPrint,
              icon: const Icon(Icons.print),
              label: const Text('Print Morning News'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveNightAndPrint() async {
    final victimName = _game!.resolveNight();
    _game!.startDay();
    
    // Find the victim player object (if any)
    WerewolfPlayer? victimPlayer;
    if (victimName != null) {
      victimPlayer = _game!.players.where((p) => p.name == victimName && !p.isAlive).firstOrNull;
    }
    
    if (_demoMode) {
      // Show preview instead of printing with Atkinson dithering
      final imageBytes = await _generateMorningNewsImage(victimName);
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
                child: const Row(
                  children: [
                    Icon(Icons.newspaper, size: 20, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Morning News', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    Spacer(),
                    Text('(print preview)', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
              Container(
                color: Colors.white,
                child: Image.memory(ditheredBytes, fit: BoxFit.fitWidth, filterQuality: FilterQuality.none),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Continue to Day'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Print morning news
      await _printMorningNews(victimName);
    }
    
    // Check if victim was a hunter - they get revenge!
    if (victimPlayer != null && victimPlayer.role == WerewolfRole.hunter) {
      _hunterRevenge(victimPlayer);
      return; // Game over check happens after hunter picks
    }
    
    // Check for game over
    if (_game!.isGameOver) {
      setState(() => _phase = GamePhase.gameOver);
    } else {
      setState(() => _phase = GamePhase.day);
    }
  }

  Future<void> _printMorningNews(String? victim) async {
    final printer = UnifiedPrinter(_bluetooth, _bluetooth.connectedDeviceName);
    final imageBytes = await _generateMorningNewsImage(victim);
    
    final printData = ImageProcessor.processForPrinting(imageBytes);
    final dims = ImageProcessor.getProcessedDimensions(imageBytes);
    
    await printer.printFullImage(
      printData,
      ImageProcessor.defaultWidth,
      dims.height,
      density: 0.65,
      feedLines: 80,
    );
  }

  Future<Uint8List> _generateMorningNewsImage(String? victim) async {
    const width = 384.0;
    const height = 350.0;
    const padding = 28.0;
    final textWidth = width - (padding * 2);
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    
    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    
    // Border
    canvas.drawRect(
      Rect.fromLTWH(4, 4, width - 8, height - 8),
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    
    // Header
    final headerStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 28,
      fontWeight: ui.FontWeight.bold,
    );
    final headerPara = _buildParagraph('☀️ DAWN BREAKS ☀️', headerStyle, textWidth, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(headerPara, Offset(padding, 24));
    
    // Day number
    final dayStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 20,
    );
    final dayPara = _buildParagraph('Day ${_game!.dayNumber}', dayStyle, textWidth, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(dayPara, Offset(padding, 62));
    
    // Separator
    canvas.drawLine(
      Offset(padding, 95),
      Offset(width - padding, 95),
      Paint()..strokeWidth = 1,
    );
    
    if (victim != null) {
      // Death announcement
      final deathStyle = ui.TextStyle(
        color: const Color(0xFF000000),
        fontSize: 20,
      );
      final deathPara = _buildParagraph('The village wakes to\ntragic news...', deathStyle, textWidth, textAlign: ui.TextAlign.center);
      canvas.drawParagraph(deathPara, Offset(padding, 110));
      
      // Victim name
      final victimStyle = ui.TextStyle(
        color: const Color(0xFF000000),
        fontSize: 30,
        fontWeight: ui.FontWeight.bold,
      );
      final victimPara = _buildParagraph('💀 $victim', victimStyle, textWidth, textAlign: ui.TextAlign.center);
      canvas.drawParagraph(victimPara, Offset(padding, 170));
      
      final deadStyle = ui.TextStyle(
        color: const Color(0xFF000000),
        fontSize: 24,
      );
      final deadPara = _buildParagraph('IS DEAD', deadStyle, textWidth, textAlign: ui.TextAlign.center);
      canvas.drawParagraph(deadPara, Offset(padding, 215));
    } else {
      // No death
      final safeStyle = ui.TextStyle(
        color: const Color(0xFF000000),
        fontSize: 22,
      );
      final safePara = _buildParagraph('The village sleeps\npeacefully...', safeStyle, textWidth, textAlign: ui.TextAlign.center);
      canvas.drawParagraph(safePara, Offset(padding, 125));
      
      final noDeathStyle = ui.TextStyle(
        color: const Color(0xFF000000),
        fontSize: 28,
        fontWeight: ui.FontWeight.bold,
      );
      final noDeathPara = _buildParagraph('✓ NO DEATHS', noDeathStyle, textWidth, textAlign: ui.TextAlign.center);
      canvas.drawParagraph(noDeathPara, Offset(padding, 190));
    }
    
    // Survivor count
    canvas.drawLine(
      Offset(padding, 265),
      Offset(width - padding, 265),
      Paint()..strokeWidth = 1,
    );
    
    final survivorStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 20,
    );
    final survivorPara = _buildParagraph(
      'Survivors: ${_game!.alivePlayers.length}', 
      survivorStyle, 
      textWidth,
      textAlign: ui.TextAlign.center,
    );
    canvas.drawParagraph(survivorPara, Offset(padding, 280));
    
    final discussStyle = ui.TextStyle(
      color: const Color(0xFF000000),
      fontSize: 18,
      fontStyle: ui.FontStyle.italic,
    );
    final discussPara = _buildParagraph('Discussion begins...', discussStyle, textWidth, textAlign: ui.TextAlign.center);
    canvas.drawParagraph(discussPara, Offset(padding, 312));
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }

  // ============ DAY PHASE ============

  Widget _buildDay() {
    return SafeArea(
      child: Column(
        children: [
          // Day header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.orange[100],
            child: Row(
              children: [
                const Icon(Icons.wb_sunny, color: Colors.orange, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Day ${_game!.dayNumber}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text('${_game!.alivePlayers.length} alive'),
              ],
            ),
          ),
          
          // Player list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _game!.players.length,
              itemBuilder: (ctx, index) {
                final player = _game!.players[index];
                return Card(
                  color: player.isAlive ? null : Colors.grey[300],
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: player.isAlive ? Colors.blue : Colors.grey,
                      child: Text('${player.seatPosition}'),
                    ),
                    title: Text(
                      player.isMayor ? '${player.name} ⛤' : player.name,
                      style: TextStyle(
                        decoration: player.isAlive ? null : TextDecoration.lineThrough,
                        fontWeight: player.isMayor ? FontWeight.bold : null,
                      ),
                    ),
                    subtitle: player.isAlive ? null : Text('${player.role.emoji} ${player.role.displayName}'),
                    trailing: player.isAlive 
                        ? IconButton(
                            icon: const Icon(Icons.how_to_vote),
                            onPressed: () => _executePlayer(player),
                            tooltip: 'Execute',
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _skipExecution,
                    child: const Text('No Execution'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _startNightPhase,
                    icon: const Icon(Icons.nightlight_round),
                    label: const Text('Start Night'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _executePlayer(WerewolfPlayer player) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Execute ${player.name}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _killPlayer(player, wasExecution: true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Execute'),
          ),
        ],
      ),
    );
  }

  void _killPlayer(WerewolfPlayer player, {bool wasExecution = false}) {
    setState(() {
      player.isAlive = false;
    });
    
    // Show role reveal
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${player.name} was ${player.role.emoji} ${player.role.displayName}'),
        duration: const Duration(seconds: 3),
      ),
    );
    
    // Check if hunter - they get revenge
    if (player.role == WerewolfRole.hunter) {
      _hunterRevenge(player);
      return; // Game over check happens after hunter picks
    }
    
    // Check for game over
    if (_game!.isGameOver) {
      setState(() => _phase = GamePhase.gameOver);
    }
  }

  void _hunterRevenge(WerewolfPlayer hunter) {
    final targets = _game!.alivePlayers;
    if (targets.isEmpty) {
      _checkGameOverOrContinueDay();
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🏹 Hunter\'s Revenge!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${hunter.name} was the Hunter!'),
            const SizedBox(height: 8),
            const Text('They may take someone with them.'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: targets.map((target) => ActionChip(
                label: Text('${target.seatPosition}. ${target.name}'),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    target.isAlive = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${hunter.name} took ${target.name} with them! (${target.role.emoji} ${target.role.displayName})'),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                  _checkGameOverOrContinueDay();
                },
              )).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _checkGameOverOrContinueDay();
            },
            child: const Text('Skip (no revenge)'),
          ),
        ],
      ),
    );
  }

  void _checkGameOverOrContinueDay() {
    if (_game!.isGameOver) {
      setState(() => _phase = GamePhase.gameOver);
    } else if (_phase != GamePhase.day) {
      setState(() => _phase = GamePhase.day);
    }
  }

  void _skipExecution() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No one was executed today')),
    );
  }

  // ============ GAME OVER ============

  Widget _buildGameOver() {
    final winner = _game!.winner;
    final isVillageWin = winner == 'VILLAGE';
    
    return Container(
      color: isVillageWin ? const Color(0xFF1B5E20) : const Color(0xFF8B0000),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isVillageWin ? '🏠' : '🐺',
                style: const TextStyle(fontSize: 100),
              ),
              const SizedBox(height: 24),
              Text(
                '$winner WIN!',
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 32),
              
              // Role reveal
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('Role Reveal', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Divider(),
                      ..._game!.players.map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Text('${p.seatPosition}. ${p.name}'),
                            if (p.isMayor) const Text(' ⛤'),
                            const Spacer(),
                            Text('${p.role.emoji} ${p.role.displayName}'),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _resetGame,
                icon: const Icon(Icons.refresh),
                label: const Text('New Game'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetGame() {
    setState(() {
      _phase = GamePhase.setup;
      _game = null;
      _printingPlayerIndex = 0;
      _currentNightActionIndex = 0;
      _selectedTarget = null;
    });
  }
}
