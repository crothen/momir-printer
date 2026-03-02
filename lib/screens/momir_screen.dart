import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/bluetooth_service.dart';
import '../services/scryfall_service.dart';
import '../services/image_processor.dart';
import '../printers/phomemo_protocol.dart';
import '../models/card.dart';

/// Result from a single ability activation
class AbilityResult {
  final String abilityName;
  final MtgCard? card;
  final Uint8List? imageBytes;
  final String? error;

  AbilityResult({
    required this.abilityName,
    this.card,
    this.imageBytes,
    this.error,
  });

  bool get success => card != null;
}

class MomirScreen extends StatefulWidget {
  const MomirScreen({super.key});

  @override
  State<MomirScreen> createState() => _MomirScreenState();
}

class _MomirScreenState extends State<MomirScreen> {
  final _bluetooth = BleManager();
  final _scryfall = ScryfallService();
  
  int _selectedMana = 3;
  
  // Ability toggles
  bool _momirEnabled = true;
  bool _jhoiraEnabled = false;
  bool _stonehewerEnabled = false;
  
  // Results
  List<AbilityResult> _results = [];
  
  bool _isLoading = false;
  bool _isPrinting = false;
  int _printingIndex = -1;

  String get _modeName {
    final parts = <String>[];
    if (_momirEnabled) parts.add('Mo');
    if (_jhoiraEnabled) parts.add('Jo');
    if (_stonehewerEnabled) parts.add('Sto');
    if (parts.isEmpty) return 'Select abilities';
    return parts.join('');
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
          // Ability toggles
          _buildAbilityToggles(),
          
          const Divider(),
          
          // Mana selector
          _buildManaSelector(),
          
          const Divider(),
          
          // Results area
          Expanded(
            child: _buildResults(),
          ),
          
          // Roll button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _canRoll() ? _roll : null,
                icon: _isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.casino),
                label: Text(_isLoading ? 'Rolling...' : 'Roll!'),
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

  Widget _buildAbilityToggles() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _AbilityToggle(
            name: 'Momir',
            icon: Icons.pets,
            color: Colors.green,
            description: 'Random creature',
            enabled: _momirEnabled,
            onToggle: (v) => setState(() => _momirEnabled = v),
          ),
          _AbilityToggle(
            name: 'Jhoira',
            icon: Icons.auto_fix_high,
            color: Colors.blue,
            description: 'Random spell',
            enabled: _jhoiraEnabled,
            onToggle: (v) => setState(() => _jhoiraEnabled = v),
          ),
          _AbilityToggle(
            name: 'Stonehewer',
            icon: Icons.shield,
            color: Colors.orange,
            description: 'Random equipment',
            enabled: _stonehewerEnabled,
            onToggle: (v) => setState(() => _stonehewerEnabled = v),
          ),
        ],
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
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.casino,
              size: 80,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Enable abilities above and roll!',
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
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _buildResultCard(result, index);
      },
    );
  }

  Widget _buildResultCard(AbilityResult result, int index) {
    if (!result.success) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(result.abilityName),
          subtitle: Text(result.error ?? 'Unknown error'),
        ),
      );
    }

    final card = result.card!;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card image
          if (card.images.normal != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                card.images.normal!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stack) => Container(
                  height: 100,
                  color: Colors.grey[800],
                  child: const Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
          
          // Card info + print button
          ListTile(
            title: Text(
              card.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.abilityName),
                if (card.typeLine != null)
                  Text(card.typeLine!, style: const TextStyle(fontSize: 12)),
                if (card.ptString != null)
                  Text(card.ptString!, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: IconButton(
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
            ),
          ),
        ],
      ),
    );
  }

  bool _canRoll() {
    return !_isLoading && (_momirEnabled || _jhoiraEnabled || _stonehewerEnabled);
  }

  Future<void> _roll() async {
    setState(() {
      _isLoading = true;
      _results = [];
    });

    final results = <AbilityResult>[];

    // Momir - Random creature at MV X
    if (_momirEnabled) {
      results.add(await _fetchCard(
        'Momir Vig',
        () => _scryfall.getRandomCreature(_selectedMana),
      ));
    }

    // Jhoira - Random instant/sorcery at MV X
    if (_jhoiraEnabled) {
      results.add(await _fetchCard(
        'Jhoira',
        () => _scryfall.getRandomInstantOrSorcery(_selectedMana),
      ));
    }

    // Stonehewer - Random equipment at MV <= creature's MV
    if (_stonehewerEnabled) {
      // Use the creature's MV if we got one, otherwise use selected mana
      final creatureMv = _momirEnabled && results.first.card != null
          ? results.first.card!.cmc ?? _selectedMana
          : _selectedMana;
      
      results.add(await _fetchCard(
        'Stonehewer Giant',
        () => _scryfall.getRandomEquipment(creatureMv),
      ));
    }

    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  Future<AbilityResult> _fetchCard(
    String abilityName,
    Future<MtgCard> Function() fetcher,
  ) async {
    try {
      final card = await fetcher();
      
      // Fetch card image
      Uint8List? imageBytes;
      final imageUrl = card.images.forPrinting;
      if (imageUrl != null) {
        try {
          final response = await http.get(Uri.parse(imageUrl));
          if (response.statusCode == 200) {
            imageBytes = response.bodyBytes;
          }
        } catch (_) {}
      }
      
      return AbilityResult(
        abilityName: abilityName,
        card: card,
        imageBytes: imageBytes,
      );
    } on NoCardFoundException catch (e) {
      return AbilityResult(
        abilityName: abilityName,
        error: e.message,
      );
    } catch (e) {
      return AbilityResult(
        abilityName: abilityName,
        error: 'Failed to fetch: $e',
      );
    }
  }

  Future<void> _printCard(AbilityResult result, int index) async {
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
            content: Text(success 
                ? 'Printed ${result.card!.name}!' 
                : 'Print failed'),
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
        title: const Text('Momir Abilities'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAbilityInfo(
                'Momir Vig',
                Icons.pets,
                Colors.green,
                '{X}, Discard a card: Create a token copy of a random creature with mana value X.',
              ),
              const SizedBox(height: 16),
              _buildAbilityInfo(
                'Jhoira',
                Icons.auto_fix_high,
                Colors.blue,
                '{X}, Discard a card: Cast a random instant or sorcery with mana value X.',
              ),
              const SizedBox(height: 16),
              _buildAbilityInfo(
                'Stonehewer Giant',
                Icons.shield,
                Colors.orange,
                'When you create a creature token, you may search for a random Equipment with mana value ≤ that creature\'s mana value and attach it.',
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Combinations',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• Mo = Momir only'),
              const Text('• MoJo = Momir + Jhoira'),
              const Text('• MoSto = Momir + Stonehewer'),
              const Text('• MoJoSto = All three!'),
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

  Widget _buildAbilityInfo(String name, IconData icon, Color color, String description) {
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

class _AbilityToggle extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  const _AbilityToggle({
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onToggle(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? color : Theme.of(context).colorScheme.outline,
            width: enabled ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: enabled ? color : Theme.of(context).colorScheme.outline),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontWeight: enabled ? FontWeight.bold : FontWeight.normal,
                color: enabled ? color : Theme.of(context).colorScheme.outline,
              ),
            ),
            Text(
              description,
              style: TextStyle(
                fontSize: 10,
                color: enabled ? color.withValues(alpha: 0.8) : Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
