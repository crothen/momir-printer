import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/phomemo_protocol.dart';

class MagicItem {
  final String name;
  final String type;
  final String rarity;
  final bool attunement;
  final String description;

  MagicItem({
    required this.name,
    required this.type,
    required this.rarity,
    required this.attunement,
    required this.description,
  });

  factory MagicItem.fromJson(Map<String, dynamic> json) {
    return MagicItem(
      name: json['name'] ?? '',
      type: json['type'] ?? 'Wondrous item',
      rarity: json['rarity'] ?? 'unknown',
      attunement: json['attunement'] ?? false,
      description: json['description'] ?? '',
    );
  }

  Color get rarityColor {
    switch (rarity.toLowerCase()) {
      case 'common': return Colors.grey;
      case 'uncommon': return Colors.green;
      case 'rare': return Colors.blue;
      case 'very rare': return Colors.purple;
      case 'legendary': return Colors.orange;
      case 'artifact': return Colors.red;
      default: return Colors.grey;
    }
  }
}

class MagicItemsScreen extends StatefulWidget {
  const MagicItemsScreen({super.key});

  @override
  State<MagicItemsScreen> createState() => _MagicItemsScreenState();
}

class _MagicItemsScreenState extends State<MagicItemsScreen> {
  final _bluetooth = BleManager();
  final _searchController = TextEditingController();
  
  List<MagicItem> _allItems = [];
  List<MagicItem> _filteredItems = [];
  bool _isLoading = true;
  String? _error;
  
  String? _rarityFilter;
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final jsonString = await rootBundle.loadString('assets/magic-items.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        _allItems = jsonList.map((j) => MagicItem.fromJson(j)).toList();
        _allItems.sort((a, b) => a.name.compareTo(b.name));
        _filteredItems = _allItems;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load items: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredItems = _allItems.where((item) {
        if (_searchController.text.isNotEmpty) {
          if (!item.name.toLowerCase().contains(_searchController.text.toLowerCase())) {
            return false;
          }
        }
        if (_rarityFilter != null && item.rarity != _rarityFilter) return false;
        if (_typeFilter != null && item.type != _typeFilter) return false;
        return true;
      }).toList();
    });
  }

  List<String> get _rarityOptions => ['common', 'uncommon', 'rare', 'very rare', 'legendary', 'artifact'];
  List<String> get _typeOptions => _allItems.map((i) => i.type).toSet().toList()..sort();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Magic Items'),
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterSheet),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search items...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _applyFilters(); })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: (_) => _applyFilters(),
            ),
          ),
          if (_rarityFilter != null || _typeFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Wrap(
                spacing: 8,
                children: [
                  if (_rarityFilter != null)
                    Chip(label: Text(_rarityFilter!), onDeleted: () { _rarityFilter = null; _applyFilters(); }),
                  if (_typeFilter != null)
                    Chip(label: Text(_typeFilter!), onDeleted: () { _typeFilter = null; _applyFilters(); }),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(children: [
              Text('${_filteredItems.length} items', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontWeight: FontWeight.w500)),
            ]),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_filteredItems.isEmpty) return const Center(child: Text('No items found'));
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) => _buildItemTile(_filteredItems[index]),
    );
  }

  Widget _buildItemTile(MagicItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 8,
          height: 40,
          decoration: BoxDecoration(
            color: item.rarityColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${item.type} • ${item.rarity}${item.attunement ? ' (attunement)' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showItemDetail(item),
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  TextButton(onPressed: () { setSheetState(() { _rarityFilter = null; _typeFilter = null; }); _applyFilters(); }, child: const Text('Clear All')),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Rarity', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _rarityOptions.map((rarity) => ChoiceChip(
                  label: Text(rarity[0].toUpperCase() + rarity.substring(1)),
                  selected: _rarityFilter == rarity,
                  onSelected: (sel) { setSheetState(() => _rarityFilter = sel ? rarity : null); _applyFilters(); },
                )).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Type', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _typeOptions.map((type) => ChoiceChip(
                  label: Text(type),
                  selected: _typeFilter == type,
                  onSelected: (sel) { setSheetState(() => _typeFilter = sel ? type : null); _applyFilters(); },
                )).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showItemDetail(MagicItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _ItemDetailSheet(
          item: item,
          scrollController: scrollController,
          bluetooth: _bluetooth,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _ItemDetailSheet extends StatefulWidget {
  final MagicItem item;
  final ScrollController scrollController;
  final BleManager bluetooth;

  const _ItemDetailSheet({required this.item, required this.scrollController, required this.bluetooth});

  @override
  State<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<_ItemDetailSheet> {
  bool _isPrinting = false;
  bool _isPreviewing = false;
  Uint8List? _previewImage;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Text(item.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.rarityColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.rarity[0].toUpperCase() + item.rarity.substring(1),
                        style: TextStyle(color: item.rarityColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(item.type, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
                if (item.attunement) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 4),
                      Text('Requires Attunement', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(item.description, style: const TextStyle(fontSize: 15, height: 1.5)),
                
                // B&W Preview
                if (_previewImage != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Print Preview (B&W)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      color: Colors.white,
                    ),
                    child: Image.memory(_previewImage!, filterQuality: FilterQuality.none),
                  ),
                ],
                
                const SizedBox(height: 80),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _isPreviewing ? null : _togglePreview,
                        icon: _isPreviewing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(_previewImage != null ? Icons.close : Icons.visibility),
                        label: Text(_previewImage != null ? 'Hide' : 'Preview'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: widget.bluetooth.currentState == BleConnectionState.connected && !_isPrinting ? _printItem : null,
                        icon: _isPrinting ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print, size: 24),
                        label: Text(_isPrinting ? 'Printing...' : 'Print', style: const TextStyle(fontSize: 16)),
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

  Future<void> _togglePreview() async {
    if (_previewImage != null) {
      setState(() => _previewImage = null);
      return;
    }
    
    setState(() => _isPreviewing = true);
    try {
      final imageBytes = await _generateItemCard(widget.item);
      final preview = ImageProcessor.createPreview(imageBytes);
      setState(() => _previewImage = preview);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preview error: $e')));
    } finally {
      setState(() => _isPreviewing = false);
    }
  }

  Future<void> _printItem() async {
    setState(() => _isPrinting = true);
    try {
      final imageBytes = await _generateItemCard(widget.item);
      final printData = ImageProcessor.processForPrinting(imageBytes);
      final dims = ImageProcessor.getProcessedDimensions(imageBytes);

      final protocol = PhomemoProtocol(widget.bluetooth);
      await protocol.printFullImage(printData, ImageProcessor.defaultWidth, dims.height, density: 0.65, feedLines: 50);
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Printed ${widget.item.name}!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print error: $e')));
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  Future<Uint8List> _generateItemCard(MagicItem item) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    const width = 384.0;
    const padding = 12.0;
    const contentWidth = width - (padding * 2);
    
    final namePainter = TextPainter(
      text: TextSpan(text: item.name.toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black)),  // 200%
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    final typePainter = TextPainter(
      text: TextSpan(
        text: '${item.type}, ${item.rarity}${item.attunement ? ' (requires attunement)' : ''}',
        style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.black),  // 200%
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    final descPainter = TextPainter(
      text: TextSpan(text: item.description, style: const TextStyle(fontSize: 18, color: Colors.black, height: 1.3)),  // 200%
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    double height = padding + namePainter.height + 8 + typePainter.height + 16 + descPainter.height + padding;
    
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(3, 3, width - 6, height - 6), Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
    
    double y = padding;
    
    namePainter.paint(canvas, Offset((width - namePainter.width) / 2, y));
    y += namePainter.height + 6;
    typePainter.paint(canvas, Offset((width - typePainter.width) / 2, y));
    y += typePainter.height + 10;
    
    canvas.drawLine(Offset(padding, y), Offset(width - padding, y), Paint()..color = Colors.black..strokeWidth = 2);
    y += 12;
    
    descPainter.paint(canvas, Offset(padding, y));
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
