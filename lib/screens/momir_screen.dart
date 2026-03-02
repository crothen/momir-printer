import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/bluetooth_service.dart';
import '../services/scryfall_service.dart';
import '../services/image_processor.dart';
import '../printers/phomemo_protocol.dart';
import '../models/card.dart';

class MomirScreen extends StatefulWidget {
  const MomirScreen({super.key});

  @override
  State<MomirScreen> createState() => _MomirScreenState();
}

class _MomirScreenState extends State<MomirScreen> {
  final _bluetooth = BleManager();
  final _scryfall = ScryfallService();
  
  int _selectedMana = 3;
  MtgCard? _currentCard;
  Uint8List? _cardImage;
  
  bool _isLoading = false;
  bool _isPrinting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Momir Vig'),
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
          // Mana selector
          _buildManaSelector(),
          
          const Divider(),
          
          // Card display area
          Expanded(
            child: _buildCardDisplay(),
          ),
          
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || _isPrinting ? null : _rollCreature,
                    icon: _isLoading 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.casino),
                    label: Text(_isLoading ? 'Rolling...' : 'Roll Creature'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                if (_currentCard != null) ...[
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isPrinting || _cardImage == null ? null : _printCard,
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
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManaSelector() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'Select Mana Value',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(17, (index) {
                final isSelected = _selectedMana == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      index.toString(),
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedMana = index),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardDisplay() {
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

    if (_currentCard == null) {
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
              'Pay {$_selectedMana} and discard a card\nto create a random creature!',
              textAlign: TextAlign.center,
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
          // Card image
          if (_cardImage != null)
            Container(
              constraints: const BoxConstraints(maxHeight: 350),
              child: Image.network(
                _currentCard!.images.normal ?? _currentCard!.images.large ?? '',
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 350,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stack) => Container(
                  height: 350,
                  color: Colors.grey[800],
                  child: const Center(child: Icon(Icons.broken_image, size: 64)),
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Card info
          Text(
            _currentCard!.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_currentCard!.typeLine != null)
            Text(
              _currentCard!.typeLine!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          if (_currentCard!.ptString != null)
            Text(
              _currentCard!.ptString!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _rollCreature() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentCard = null;
      _cardImage = null;
    });

    try {
      final card = await _scryfall.getRandomCreature(_selectedMana);
      
      // Fetch card image for printing
      final imageUrl = card.images.forPrinting;
      if (imageUrl != null) {
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          _cardImage = response.bodyBytes;
        }
      }
      
      setState(() {
        _currentCard = card;
        _isLoading = false;
      });
    } on NoCardFoundException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch card: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _printCard() async {
    if (_cardImage == null) return;
    
    setState(() => _isPrinting = true);

    try {
      // Process image for thermal printing
      final printData = ImageProcessor.processForPrinting(_cardImage!);
      final dims = ImageProcessor.getProcessedDimensions(_cardImage!);
      
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
                ? 'Printed ${_currentCard!.name}!' 
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
      setState(() => _isPrinting = false);
    }
  }

  void _showInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Momir Vig'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How to Play',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'You have an emblem with:\n\n'
                '{X}, Discard a card: Create a token that\'s a copy of a '
                'creature card with mana value X chosen at random.\n\n'
                'Activate only as a sorcery.',
              ),
              SizedBox(height: 16),
              Text(
                'Tips',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                '• Start each game with a basic land deck\n'
                '• Popular starting mana values: 3-5\n'
                '• High mana (8+) can get game-ending creatures\n'
                '• Mana value 0 and 1 often whiff',
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
}
