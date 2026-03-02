import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/bluetooth_service.dart';
import '../services/scryfall_service.dart';
import '../services/image_processor.dart';
import '../printers/phomemo_protocol.dart';
import '../models/card.dart';

enum GameMode {
  momir,
  momirStonehewer,
  jhoira,
}

/// Result from a single ability activation
class CardResult {
  final String source;
  final MtgCard card;
  final Uint8List? imageBytes;
  Uint8List? bwPreview;

  CardResult({
    required this.source,
    required this.card,
    this.imageBytes,
    this.bwPreview,
  });
}

class MomirScreen extends StatefulWidget {
  const MomirScreen({super.key});

  @override
  State<MomirScreen> createState() => _MomirScreenState();
}

class _MomirScreenState extends State<MomirScreen> {
  final _bluetooth = BleManager();
  final _scryfall = ScryfallService();
  
  GameMode _mode = GameMode.momir;
  int _selectedMana = 3;
  
  // Results
  List<CardResult> _results = [];
  String? _error;
  
  // Jhoira state
  bool _jhoiraChoosingType = false;
  List<CardResult>? _jhoiraOptions;
  
  bool _isLoading = false;
  bool _isPrinting = false;
  int _printingIndex = -1;
  int _previewBwIndex = -1;

  String get _modeName {
    switch (_mode) {
      case GameMode.momir:
        return 'Momir';
      case GameMode.momirStonehewer:
        return 'MoSto';
      case GameMode.jhoira:
        return 'Jhoira';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_modeName),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfo,
            tooltip: 'How to play',
          ),
        ],
      ),
      body: Column(
        children: [
          // Mode selector
          _buildModeSelector(),
          
          const Divider(),
          
          // Mana selector (not for Jhoira)
          if (_mode != GameMode.jhoira) _buildManaSelector(),
          
          // Jhoira type chooser
          if (_mode == GameMode.jhoira && _jhoiraChoosingType)
            _buildJhoiraTypeChooser(),
          
          if (_mode != GameMode.jhoira || !_jhoiraChoosingType)
            const Divider(),
          
          // Results area
          Expanded(
            child: _buildResults(),
          ),
          
          // Action button (not shown for Jhoira - uses type chooser instead)
          if (_mode != GameMode.jhoira)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 72, // 200% of default ~36px
                child: ElevatedButton.icon(
                  onPressed: _canRoll() ? _startRoll : null,
                  icon: _isLoading 
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.casino, size: 32),
                  label: Text(
                    _isLoading ? 'Rolling...' : 'Roll!',
                    style: const TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getButtonText() {
    if (_mode == GameMode.jhoira) {
      return 'Cast Jhoira';
    }
    return 'Roll!';
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SegmentedButton<GameMode>(
        segments: const [
          ButtonSegment(
            value: GameMode.momir,
            label: Text('Momir'),
            icon: Icon(Icons.pets),
          ),
          ButtonSegment(
            value: GameMode.momirStonehewer,
            label: Text('MoSto'),
            icon: Icon(Icons.shield),
          ),
          ButtonSegment(
            value: GameMode.jhoira,
            label: Text('Jhoira'),
            icon: Icon(Icons.auto_fix_high),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (selection) {
          setState(() {
            _mode = selection.first;
            _results = [];
            _error = null;
            _jhoiraChoosingType = _mode == GameMode.jhoira; // Auto-show type chooser
            _jhoiraOptions = null;
          });
        },
      ),
    );
  }

  Widget _buildManaSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Mana Value',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '{$_selectedMana}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: _selectedMana.toDouble(),
            min: 0,
            max: 16,
            divisions: 16,
            label: _selectedMana.toString(),
            onChanged: (v) => setState(() => _selectedMana = v.round()),
          ),
          if (_mode == GameMode.momirStonehewer)
            Text(
              'Equipment will be MV ≤${_selectedMana - 1 < 0 ? 0 : _selectedMana - 1}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildJhoiraTypeChooser() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'Choose spell type:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 72,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _rollJhoira('instant'),
                    icon: _isLoading 
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                          )
                        : const Icon(Icons.flash_on, size: 32),
                    label: const Text('Instant', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 72,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _rollJhoira('sorcery'),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, size: 32),
                    label: const Text('Sorcery', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      );
    }

    // Jhoira options (pick one of three)
    if (_jhoiraOptions != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Choose a spell to cast:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _jhoiraOptions!.length,
              itemBuilder: (context, index) {
                return _buildJhoiraOptionCard(_jhoiraOptions![index], index);
              },
            ),
          ),
        ],
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _mode == GameMode.jhoira ? Icons.auto_fix_high : Icons.casino,
              size: 80,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              _getEmptyStateText(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildResultCard(_results[index], index),
        );
      },
    );
  }

  String _getEmptyStateText() {
    switch (_mode) {
      case GameMode.momir:
        return 'Pay {$_selectedMana} and discard a card\nto create a random creature!';
      case GameMode.momirStonehewer:
        return 'Pay {$_selectedMana} and discard a card\nto create a creature with equipment!';
      case GameMode.jhoira:
        return 'Discard a card to cast\na random instant or sorcery!';
    }
  }

  Widget _buildJhoiraOptionCard(CardResult result, int index) {
    return Card(
      child: InkWell(
        onTap: () => _selectJhoiraOption(result),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            if (result.card.images.normal != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  result.card.images.normal!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ListTile(
              title: Text(result.card.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(result.card.typeLine ?? ''),
              trailing: const Icon(Icons.touch_app, color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(CardResult result, int index) {
    final showBw = _previewBwIndex == index && result.bwPreview != null;
    
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _toggleBwPreview(result, index),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                children: [
                  if (showBw && result.bwPreview != null)
                    Container(
                      color: Colors.white,
                      width: double.infinity,
                      child: Image.memory(
                        result.bwPreview!,
                        width: double.infinity,
                        fit: BoxFit.fitWidth, // Fill width, height adjusts
                        filterQuality: FilterQuality.none,
                      ),
                    )
                  else if (result.card.images.normal != null)
                    Image.network(
                      result.card.images.normal!,
                      width: double.infinity,
                      fit: BoxFit.fitWidth, // Fill width, height adjusts
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        showBw ? 'B&W • Tap for color' : 'Tap for B&W preview',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getSourceColor(result.source),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        result.source,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: Text(
              result.card.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.card.typeLine != null)
                  Text(result.card.typeLine!, style: const TextStyle(fontSize: 12)),
                if (result.card.ptString != null)
                  Text(result.card.ptString!, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: _bluetooth.currentState == BleConnectionState.connected
                ? IconButton(
                    icon: _printingIndex == index
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print),
                    onPressed: _isPrinting || result.imageBytes == null
                        ? null
                        : () => _printCard(result, index),
                    tooltip: 'Print',
                  )
                : const Tooltip(
                    message: 'Connect printer to print',
                    child: Icon(Icons.print_disabled, color: Colors.grey),
                  ),
          ),
        ],
      ),
    );
  }

  Color _getSourceColor(String source) {
    switch (source) {
      case 'Momir Vig':
        return Colors.green;
      case 'Stonehewer':
        return Colors.orange;
      case 'Jhoira':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  bool _canRoll() {
    return !_isLoading && _jhoiraOptions == null;
  }

  void _startRoll() {
    if (_mode == GameMode.jhoira) {
      setState(() {
        _jhoiraChoosingType = true;
        _results = [];
        _error = null;
      });
    } else {
      _rollMomir();
    }
  }

  Future<void> _rollMomir() async {
    setState(() {
      _isLoading = true;
      _results = [];
      _error = null;
    });

    try {
      final results = <CardResult>[];

      // Get creature
      final creature = await _scryfall.getRandomCreature(_selectedMana);
      final creatureImage = await _fetchImage(creature);
      results.add(CardResult(
        source: 'Momir Vig',
        card: creature,
        imageBytes: creatureImage,
      ));

      // Get equipment if MoSto mode
      if (_mode == GameMode.momirStonehewer) {
        final equipmentMv = _selectedMana - 1;
        if (equipmentMv >= 0) {
          try {
            final equipment = await _scryfall.getRandomEquipment(equipmentMv);
            final equipmentImage = await _fetchImage(equipment);
            results.add(CardResult(
              source: 'Stonehewer',
              card: equipment,
              imageBytes: equipmentImage,
            ));
          } on NoCardFoundException {
            // No equipment at this MV, that's okay
          }
        }
      }

      setState(() {
        _results = results;
        _isLoading = false;
      });
    } on NoCardFoundException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _rollJhoira(String spellType) async {
    setState(() {
      _isLoading = true;
      _jhoiraChoosingType = false;
      _jhoiraOptions = null;
      _error = null;
    });

    try {
      final options = <CardResult>[];

      // Get 3 random spells of the chosen type (any MV)
      for (int i = 0; i < 3; i++) {
        final spell = spellType == 'instant'
            ? await _scryfall.getRandomInstant()
            : await _scryfall.getRandomSorcery();
        final image = await _fetchImage(spell);
        options.add(CardResult(
          source: 'Jhoira',
          card: spell,
          imageBytes: image,
        ));
      }

      setState(() {
        _jhoiraOptions = options;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch spells: $e';
        _isLoading = false;
      });
    }
  }

  void _selectJhoiraOption(CardResult selected) {
    setState(() {
      _results = [selected];
      _jhoiraOptions = null;
    });
  }

  Future<Uint8List?> _fetchImage(MtgCard card) async {
    final imageUrl = card.images.forPrinting;
    if (imageUrl == null) return null;
    
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  void _toggleBwPreview(CardResult result, int index) {
    if (_previewBwIndex == index) {
      setState(() => _previewBwIndex = -1);
    } else {
      if (result.bwPreview == null && result.imageBytes != null) {
        try {
          result.bwPreview = ImageProcessor.createPreview(result.imageBytes!);
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to generate preview: $e')),
          );
          return;
        }
      }
      setState(() => _previewBwIndex = index);
    }
  }

  Future<void> _printCard(CardResult result, int index) async {
    if (result.imageBytes == null) return;
    
    setState(() {
      _isPrinting = true;
      _printingIndex = index;
    });

    try {
      final printData = ImageProcessor.processForPrinting(result.imageBytes!);
      final dims = ImageProcessor.getProcessedDimensions(result.imageBytes!);
      
      final protocol = PhomemoProtocol(_bluetooth);
      final success = await protocol.printFullImage(
        printData,
        ImageProcessor.defaultWidth,
        dims.height,
        density: 0.65,
        feedLines: 50,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Printed ${result.card.name}!' : 'Print failed'),
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
      setState(() {
        _isPrinting = false;
        _printingIndex = -1;
      });
    }
  }

  void _showInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Game Modes'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeInfo(
                'Momir',
                Icons.pets,
                Colors.green,
                '{X}, Discard a card: Create a token copy of a random creature with mana value X.',
              ),
              const SizedBox(height: 16),
              _buildModeInfo(
                'MoSto (Momir + Stonehewer)',
                Icons.shield,
                Colors.orange,
                'Same as Momir, plus: Search for a random Equipment with MV ≤ (X-1) and attach it to the creature.',
              ),
              const SizedBox(height: 16),
              _buildModeInfo(
                'Jhoira',
                Icons.auto_fix_high,
                Colors.deepPurple,
                'Discard a card: Choose instant or sorcery. Reveal 3 random spells of that type. Cast one of them without paying its mana cost.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _buildModeInfo(String name, IconData icon, Color color, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(description, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
