import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/printer_factory.dart';

class DeckCard {
  int quantity;
  final int originalQuantity;
  final String name;
  bool isSideboard;
  String? imageUrl;
  Uint8List? imageBytes;
  bool printed = false;
  String? error;

  DeckCard({
    required int quantity,
    required this.name,
    this.isSideboard = false,
  }) : quantity = quantity, originalQuantity = quantity;
}

class DeckPrinterScreen extends StatefulWidget {
  const DeckPrinterScreen({super.key});

  @override
  State<DeckPrinterScreen> createState() => _DeckPrinterScreenState();
}

class _DeckPrinterScreenState extends State<DeckPrinterScreen> {
  final _bluetooth = BleManager();
  final _urlController = TextEditingController();
  
  List<DeckCard> _mainDeck = [];
  List<DeckCard> _sideboard = [];
  bool _isLoading = false;
  bool _isPrinting = false;
  String? _error;
  String? _deckName;
  
  int _printedCount = 0;
  int _totalCards = 0;
  DeckCard? _currentlyPrinting;

  int get _mainDeckCount => _mainDeck.fold(0, (sum, c) => sum + c.quantity);
  int get _sideboardCount => _sideboard.fold(0, (sum, c) => sum + c.quantity);
  int get _totalCount => _mainDeckCount + _sideboardCount;
  
  // Estimate: ~67mm per card, typical roll is 10-15m
  String get _paperEstimate {
    final meters = (_totalCount * 67) / 1000;
    return '~${meters.toStringAsFixed(1)}m of paper (~${(meters / 12 * 100).toStringAsFixed(0)}% of a roll)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deck Printer'),
        actions: [
          if (_mainDeck.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearDeck,
              tooltip: 'Clear deck',
            ),
        ],
      ),
      body: Column(
        children: [
          // URL input
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: 'MTGGoldfish deck URL...',
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: _urlController.text.isNotEmpty ? _loadDeck : null,
                            tooltip: 'Load deck',
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                  ),
                  onSubmitted: (_) => _loadDeck(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Paste a MTGGoldfish deck URL (e.g. mtggoldfish.com/deck/12345)',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
          ),
          
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                    ],
                  ),
                ),
              ),
            ),
          
          // Deck info
          if (_mainDeck.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_deckName != null)
                        Text(_deckName!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildStatChip('Main', _mainDeckCount.toString(), Colors.blue),
                          const SizedBox(width: 8),
                          if (_sideboardCount > 0)
                            _buildStatChip('Side', _sideboardCount.toString(), Colors.orange),
                          const Spacer(),
                          _buildStatChip('Total', _totalCount.toString(), Colors.green),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_paperEstimate, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
              ),
            ),
            
            // Card list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (_mainDeck.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Main Deck', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    ..._mainDeck.map((card) => _buildCardTile(card)),
                  ],
                  if (_sideboard.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Sideboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    ..._sideboard.map((card) => _buildCardTile(card)),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ] else if (!_isLoading) ...[
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.style, size: 80, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Paste a MTGGoldfish URL to load a deck',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ],
          
          // Print progress
          if (_isPrinting)
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Printing ${_currentlyPrinting?.name ?? "..."}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('$_printedCount / $_totalCards'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _totalCards > 0 ? _printedCount / _totalCards : 0),
                ],
              ),
            ),
          
          // Print buttons
          if (_mainDeck.isNotEmpty && !_isPrinting)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Preview button
                    SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _showDeckPreview,
                        icon: const Icon(Icons.preview),
                        label: const Text('Preview'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Print button
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _bluetooth.currentState == BleConnectionState.connected ? _printDeck : null,
                          icon: const Icon(Icons.print, size: 28),
                          label: Text(
                            _bluetooth.currentState == BleConnectionState.connected
                                ? 'Print ($_totalCount)'
                                : 'Connect printer',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildCardTile(DeckCard card) {
    final isDifferent = card.quantity != card.originalQuantity;
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => _showCardPreview(card),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Quantity controls
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.remove),
                      onPressed: card.quantity > 0
                          ? () => setState(() => card.quantity--)
                          : null,
                    ),
                  ),
                  Container(
                    width: 32,
                    alignment: Alignment.center,
                    child: Text(
                      '${card.quantity}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDifferent ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.add),
                      onPressed: () => setState(() => card.quantity++),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Card name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (isDifferent)
                      Text(
                        'was ${card.originalQuantity}',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                      ),
                  ],
                ),
              ),
              // Status indicators
              if (_currentlyPrinting == card)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else if (card.error != null)
                Tooltip(message: card.error!, child: Icon(Icons.error, color: Theme.of(context).colorScheme.error))
              else if (card.printed)
                const Icon(Icons.check_circle, color: Colors.green, size: 20)
              else
                Icon(Icons.visibility, size: 20, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCardPreview(DeckCard card) async {
    // If we don't have the image yet, fetch it
    if (card.imageBytes == null && card.imageUrl == null) {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      
      try {
        final encodedName = Uri.encodeComponent(card.name);
        final scryfallResponse = await http.get(
          Uri.parse('https://api.scryfall.com/cards/named?exact=$encodedName'),
          headers: {'User-Agent': 'MomirPrinter/1.0', 'Accept': 'application/json'},
        );

        if (scryfallResponse.statusCode == 200) {
          final json = scryfallResponse.body;
          final imageMatch = RegExp(r'"normal":\s*"([^"]+)"').firstMatch(json);
          if (imageMatch != null) {
            card.imageUrl = imageMatch.group(1)!.replaceAll(r'\u0026', '&');
            final imageResponse = await http.get(Uri.parse(card.imageUrl!));
            if (imageResponse.statusCode == 200) {
              card.imageBytes = imageResponse.bodyBytes;
            }
          }
        }
      } catch (_) {}
      
      if (mounted) Navigator.of(context).pop(); // Close loading
    }

    if (!mounted) return;

    // Show preview dialog
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (card.imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  card.imageBytes!,
                  fit: BoxFit.contain,
                ),
              )
            else if (card.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  card.imageUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 400,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.image_not_supported, size: 48, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 8),
                    Text('Image not found', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Text(
              card.name,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeckPreview() async {
    final allCards = [..._mainDeck, ..._sideboard].where((c) => c.quantity > 0).toList();
    
    // Show loading while fetching and processing images
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    // Fetch all missing images and create dithered previews
    final processedImages = <Uint8List>[];
    
    for (var card in allCards) {
      // Fetch original if needed
      if (card.imageBytes == null) {
        try {
          final encodedName = Uri.encodeComponent(card.name);
          final scryfallResponse = await http.get(
            Uri.parse('https://api.scryfall.com/cards/named?exact=$encodedName'),
            headers: {'User-Agent': 'MomirPrinter/1.0', 'Accept': 'application/json'},
          );

          if (scryfallResponse.statusCode == 200) {
            final json = scryfallResponse.body;
            final imageMatch = RegExp(r'"normal":\s*"([^"]+)"').firstMatch(json);
            if (imageMatch != null) {
              card.imageUrl = imageMatch.group(1)!.replaceAll(r'\u0026', '&');
              final imageResponse = await http.get(Uri.parse(card.imageUrl!));
              if (imageResponse.statusCode == 200) {
                card.imageBytes = imageResponse.bodyBytes;
              }
            }
          }
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (_) {}
      }
      
      // Create dithered preview for each copy
      if (card.imageBytes != null) {
        try {
          final dithered = ImageProcessor.createPreview(card.imageBytes!);
          for (int i = 0; i < card.quantity; i++) {
            processedImages.add(dithered);
          }
        } catch (_) {
          // Skip cards that fail to process
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading

    // Show full-screen vertical preview (like a receipt tape)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.grey[800],
          appBar: AppBar(
            title: Text('Print Preview (${processedImages.length} cards)'),
            backgroundColor: Colors.grey[900],
          ),
          body: Center(
            child: Container(
              width: 384, // Printer width
              color: Colors.white,
              child: ListView.builder(
                itemCount: processedImages.length,
                itemBuilder: (context, index) {
                  return Image.memory(
                    processedImages[index],
                    fit: BoxFit.fitWidth,
                    filterQuality: FilterQuality.none, // Keep it pixelated
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _clearDeck() {
    setState(() {
      _mainDeck = [];
      _sideboard = [];
      _deckName = null;
      _error = null;
    });
  }

  Future<void> _loadDeck() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Extract deck ID from URL
    final deckIdMatch = RegExp(r'/deck/(\d+)').firstMatch(url);
    if (deckIdMatch == null) {
      setState(() => _error = 'Invalid MTGGoldfish URL. Expected format: mtggoldfish.com/deck/12345');
      return;
    }
    final deckId = deckIdMatch.group(1)!;

    setState(() {
      _isLoading = true;
      _error = null;
      _mainDeck = [];
      _sideboard = [];
    });

    try {
      // Fetch deck list
      final response = await http.get(
        Uri.parse('https://www.mtggoldfish.com/deck/download/$deckId'),
        headers: {'User-Agent': 'MomirPrinter/1.0'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch deck (${response.statusCode})');
      }

      final lines = response.body.split('\n');
      bool inSideboard = false;
      
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) {
          inSideboard = true; // Empty line separates main from sideboard
          continue;
        }

        // Parse "4 Card Name" format
        final match = RegExp(r'^(\d+)\s+(.+)$').firstMatch(line);
        if (match != null) {
          final quantity = int.parse(match.group(1)!);
          final name = match.group(2)!;
          
          final card = DeckCard(quantity: quantity, name: name, isSideboard: inSideboard);
          
          if (inSideboard) {
            _sideboard.add(card);
          } else {
            _mainDeck.add(card);
          }
        }
      }

      // Try to get deck name from the page
      try {
        final pageResponse = await http.get(
          Uri.parse('https://www.mtggoldfish.com/deck/$deckId'),
          headers: {'User-Agent': 'MomirPrinter/1.0'},
        );
        final titleMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(pageResponse.body);
        if (titleMatch != null) {
          _deckName = titleMatch.group(1)!.replaceAll(' - MTGGoldfish', '').trim();
        }
      } catch (_) {}

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load deck: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _printDeck() async {
    setState(() {
      _isPrinting = true;
      _printedCount = 0;
      _totalCards = _totalCount;
      // Reset printed status
      for (var card in [..._mainDeck, ..._sideboard]) {
        card.printed = false;
        card.error = null;
      }
    });

    final printer = UnifiedPrinter(_bluetooth, _bluetooth.connectedDeviceName);
    final allCards = [..._mainDeck, ..._sideboard];

    for (var card in allCards) {
      if (!_isPrinting) break; // Allow cancellation

      setState(() => _currentlyPrinting = card);

      try {
        // Fetch card image from Scryfall
        if (card.imageBytes == null) {
          final encodedName = Uri.encodeComponent(card.name);
          final scryfallResponse = await http.get(
            Uri.parse('https://api.scryfall.com/cards/named?exact=$encodedName'),
            headers: {'User-Agent': 'MomirPrinter/1.0', 'Accept': 'application/json'},
          );

          if (scryfallResponse.statusCode == 200) {
            final json = scryfallResponse.body;
            // Extract image URL (normal size)
            final imageMatch = RegExp(r'"normal":\s*"([^"]+)"').firstMatch(json);
            if (imageMatch != null) {
              card.imageUrl = imageMatch.group(1)!.replaceAll(r'\u0026', '&');
              
              // Download image
              final imageResponse = await http.get(Uri.parse(card.imageUrl!));
              if (imageResponse.statusCode == 200) {
                card.imageBytes = imageResponse.bodyBytes;
              }
            }
          }
        }

        if (card.imageBytes == null) {
          card.error = 'Image not found';
          continue;
        }

        // Print each copy
        for (int i = 0; i < card.quantity; i++) {
          // Small padding between cards in a deck (not the default 1cm)
          final printData = ImageProcessor.processForPrinting(card.imageBytes!, bottomPadding: 20);
          final dims = ImageProcessor.getProcessedDimensions(card.imageBytes!, bottomPadding: 20);

          await printer.printFullImage(
            printData,
            ImageProcessor.defaultWidth,
            dims.height,
            density: 0.65,
            feedLines: 0, // Padding is in the image now
          );

          setState(() => _printedCount++);
          
          // Small delay between prints
          await Future.delayed(const Duration(milliseconds: 500));
        }

        card.printed = true;
      } catch (e) {
        card.error = e.toString();
      }

      setState(() {});
    }

    setState(() {
      _isPrinting = false;
      _currentlyPrinting = null;
    });

    if (mounted) {
      final errors = allCards.where((c) => c.error != null).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors > 0
              ? 'Printed $_printedCount cards ($errors failed)'
              : 'Printed $_printedCount cards!'),
          backgroundColor: errors > 0 ? Colors.orange : Colors.green,
        ),
      );
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}
