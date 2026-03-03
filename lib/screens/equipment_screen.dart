import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/printer_factory.dart';

class Equipment {
  final String name;
  final String category;
  final String cost;
  final String weight;
  final String? damage;
  final String? ac;
  final String? properties;

  Equipment({
    required this.name,
    required this.category,
    required this.cost,
    required this.weight,
    this.damage,
    this.ac,
    this.properties,
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      cost: json['cost'] ?? '',
      weight: json['weight'] ?? '',
      damage: json['damage'],
      ac: json['ac'],
      properties: json['properties'],
    );
  }

  bool get isWeapon => category.toLowerCase().contains('weapon');
  bool get isArmor => category.toLowerCase().contains('armor');
  
  IconData get icon {
    if (isWeapon) return Icons.gavel;
    if (isArmor) return Icons.shield;
    if (category.contains('Tools')) return Icons.build;
    if (category.contains('Mounts')) return Icons.directions_run;
    return Icons.inventory_2;
  }

  Color get color {
    if (isWeapon) return Colors.red;
    if (isArmor) return Colors.blue;
    if (category.contains('Tools')) return Colors.brown;
    if (category.contains('Mounts')) return Colors.green;
    return Colors.grey;
  }
}

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  final _bluetooth = BleManager();
  final _searchController = TextEditingController();
  
  List<Equipment> _allItems = [];
  List<Equipment> _filteredItems = [];
  bool _isLoading = true;
  String? _error;
  
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final jsonString = await rootBundle.loadString('assets/equipment.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        _allItems = jsonList.map((j) => Equipment.fromJson(j)).toList();
        _allItems.sort((a, b) => a.name.compareTo(b.name));
        _filteredItems = _allItems;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load equipment: $e';
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
        if (_categoryFilter != null && !item.category.contains(_categoryFilter!)) return false;
        return true;
      }).toList();
    });
  }

  List<String> get _categoryOptions {
    final cats = <String>{};
    for (var item in _allItems) {
      if (item.category.contains('Armor')) cats.add('Armor');
      else if (item.category.contains('Weapon')) cats.add('Weapons');
      else if (item.category.contains('Tools')) cats.add('Tools');
      else if (item.category.contains('Mounts')) cats.add('Mounts');
      else cats.add('Gear');
    }
    return cats.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment'),
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
                hintText: 'Search equipment...',
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
          if (_categoryFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(_categoryFilter!), onDeleted: () { _categoryFilter = null; _applyFilters(); }),
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
    if (_filteredItems.isEmpty) return const Center(child: Text('No equipment found'));
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) => _buildItemTile(_filteredItems[index]),
    );
  }

  Widget _buildItemTile(Equipment item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(item.icon, color: item.color),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${item.category}\n${item.cost} • ${item.weight}'),
        isThreeLine: true,
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
                  TextButton(onPressed: () { setSheetState(() => _categoryFilter = null); _applyFilters(); }, child: const Text('Clear')),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Category', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _categoryOptions.map((cat) => ChoiceChip(
                  label: Text(cat),
                  selected: _categoryFilter == cat,
                  onSelected: (sel) { setSheetState(() => _categoryFilter = sel ? cat : null); _applyFilters(); },
                )).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showItemDetail(Equipment item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => _EquipmentDetailSheet(
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

class _EquipmentDetailSheet extends StatefulWidget {
  final Equipment item;
  final ScrollController scrollController;
  final BleManager bluetooth;

  const _EquipmentDetailSheet({required this.item, required this.scrollController, required this.bluetooth});

  @override
  State<_EquipmentDetailSheet> createState() => _EquipmentDetailSheetState();
}

class _EquipmentDetailSheetState extends State<_EquipmentDetailSheet> {
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
                Row(
                  children: [
                    Icon(item.icon, size: 32, color: item.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          Text(item.category, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Stats
                _buildStatRow('Cost', item.cost),
                _buildStatRow('Weight', item.weight),
                if (item.damage != null) _buildStatRow('Damage', item.damage!),
                if (item.ac != null) _buildStatRow('AC', item.ac!),
                if (item.properties != null) _buildStatRow('Properties', item.properties!),
                
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

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
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
      final imageBytes = await _generateEquipmentCard(widget.item);
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
      final imageBytes = await _generateEquipmentCard(widget.item);
      final printData = ImageProcessor.processForPrinting(imageBytes);
      final dims = ImageProcessor.getProcessedDimensions(imageBytes);

      final printer = UnifiedPrinter(widget.bluetooth, widget.bluetooth.connectedDeviceName);
      await printer.printFullImage(printData, ImageProcessor.defaultWidth, dims.height, density: 0.65, feedLines: 80);
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Printed ${widget.item.name}!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print error: $e')));
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  Future<Uint8List> _generateEquipmentCard(Equipment item) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    const width = 384.0;
    const padding = 12.0;
    const contentWidth = width - (padding * 2);
    
    final namePainter = TextPainter(
      text: TextSpan(text: item.name.toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black)),  // 200%
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    final catPainter = TextPainter(
      text: TextSpan(text: item.category, style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.black)),  // 200%
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    // Build stats list
    List<List<String>> stats = [
      ['Cost:', item.cost],
      ['Weight:', item.weight],
    ];
    if (item.damage != null) stats.add(['Damage:', item.damage!]);
    if (item.ac != null) stats.add(['AC:', item.ac!]);
    if (item.properties != null) stats.add(['Properties:', item.properties!]);
    
    double height = padding + namePainter.height + 6 + catPainter.height + 14;
    height += stats.length * 28 + 12;  // Larger line height
    height += padding;
    
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(3, 3, width - 6, height - 6), Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
    
    double y = padding;
    
    namePainter.paint(canvas, Offset((width - namePainter.width) / 2, y));
    y += namePainter.height + 6;
    catPainter.paint(canvas, Offset((width - catPainter.width) / 2, y));
    y += catPainter.height + 10;
    
    canvas.drawLine(Offset(padding, y), Offset(width - padding, y), Paint()..color = Colors.black..strokeWidth = 2);
    y += 12;
    
    for (var stat in stats) {
      final label = TextPainter(text: TextSpan(text: stat[0], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)), textDirection: TextDirection.ltr)..layout();  // 200%
      final value = TextPainter(text: TextSpan(text: ' ${stat[1]}', style: const TextStyle(fontSize: 18, color: Colors.black)), textDirection: TextDirection.ltr)..layout(maxWidth: contentWidth - label.width);  // 200%
      label.paint(canvas, Offset(padding, y));
      value.paint(canvas, Offset(padding + label.width, y));
      y += 28;  // Larger line height
    }
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
