import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/phomemo_protocol.dart';

class Spell {
  final String name;
  final int level;
  final String school;
  final String actionType;
  final String range;
  final String duration;
  final List<String> components;
  final String? material;
  final String description;
  final String? cantripUpgrade;
  final bool concentration;
  final bool ritual;
  final List<String> classes;

  Spell({
    required this.name,
    required this.level,
    required this.school,
    required this.actionType,
    required this.range,
    required this.duration,
    required this.components,
    this.material,
    required this.description,
    this.cantripUpgrade,
    required this.concentration,
    required this.ritual,
    required this.classes,
  });

  factory Spell.fromJson(Map<String, dynamic> json) {
    return Spell(
      name: json['name'] ?? '',
      level: json['level'] ?? 0,
      school: json['school'] ?? '',
      actionType: json['actionType'] ?? 'action',
      range: json['range'] ?? '',
      duration: json['duration'] ?? '',
      components: (json['components'] as List?)?.map((e) => e.toString().toUpperCase()).toList() ?? [],
      material: json['material'],
      description: json['description'] ?? '',
      cantripUpgrade: json['cantripUpgrade'],
      concentration: json['concentration'] ?? false,
      ritual: json['ritual'] ?? false,
      classes: (json['classes'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  String get levelText => level == 0 ? 'Cantrip' : '${level}${_ordinal(level)}-level';
  
  String get componentsText => components.join(', ');

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
}

class SpellsScreen extends StatefulWidget {
  const SpellsScreen({super.key});

  @override
  State<SpellsScreen> createState() => _SpellsScreenState();
}

class _SpellsScreenState extends State<SpellsScreen> {
  final _bluetooth = BleManager();
  final _searchController = TextEditingController();
  
  List<Spell> _allSpells = [];
  List<Spell> _filteredSpells = [];
  bool _isLoading = true;
  String? _error;
  
  // Filters
  int? _levelFilter;
  String? _schoolFilter;
  String? _classFilter;

  @override
  void initState() {
    super.initState();
    _loadSpells();
  }

  Future<void> _loadSpells() async {
    try {
      final jsonString = await rootBundle.loadString('assets/spells-2024.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        _allSpells = jsonList.map((j) => Spell.fromJson(j)).toList();
        _allSpells.sort((a, b) => a.name.compareTo(b.name));
        _filteredSpells = _allSpells;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load spells: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredSpells = _allSpells.where((spell) {
        // Search
        if (_searchController.text.isNotEmpty) {
          if (!spell.name.toLowerCase().contains(_searchController.text.toLowerCase())) {
            return false;
          }
        }
        // Level
        if (_levelFilter != null && spell.level != _levelFilter) return false;
        // School
        if (_schoolFilter != null && spell.school.toLowerCase() != _schoolFilter!.toLowerCase()) return false;
        // Class
        if (_classFilter != null && !spell.classes.any((c) => c.toLowerCase() == _classFilter!.toLowerCase())) return false;
        
        return true;
      }).toList();
    });
  }

  List<String> get _schools => _allSpells.map((s) => s.school).toSet().toList()..sort();
  List<String> get _classes {
    final Set<String> classes = {};
    for (var spell in _allSpells) {
      classes.addAll(spell.classes);
    }
    return classes.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('D&D Spells'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
            tooltip: 'Filters',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search spells...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _applyFilters();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: (_) => _applyFilters(),
            ),
          ),
          
          // Active filters chips
          if (_levelFilter != null || _schoolFilter != null || _classFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Wrap(
                spacing: 8,
                children: [
                  if (_levelFilter != null)
                    Chip(
                      label: Text(_levelFilter == 0 ? 'Cantrip' : 'Level $_levelFilter'),
                      onDeleted: () {
                        _levelFilter = null;
                        _applyFilters();
                      },
                    ),
                  if (_schoolFilter != null)
                    Chip(
                      label: Text(_schoolFilter!),
                      onDeleted: () {
                        _schoolFilter = null;
                        _applyFilters();
                      },
                    ),
                  if (_classFilter != null)
                    Chip(
                      label: Text(_classFilter!),
                      onDeleted: () {
                        _classFilter = null;
                        _applyFilters();
                      },
                    ),
                ],
              ),
            ),
          
          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Text(
                  '${_filteredSpells.length} spells',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          // Spell list
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    
    if (_filteredSpells.isEmpty) {
      return const Center(
        child: Text('No spells match your filters'),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filteredSpells.length,
      itemBuilder: (context, index) {
        return _buildSpellTile(_filteredSpells[index]);
      },
    );
  }

  Widget _buildSpellTile(Spell spell) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(spell.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${spell.levelText} ${spell.school}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spell.concentration)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('C', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
              ),
            if (spell.ritual)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('R', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _showSpellDetail(spell),
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
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        _levelFilter = null;
                        _schoolFilter = null;
                        _classFilter = null;
                      });
                      _applyFilters();
                    },
                    child: const Text('Clear All'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Level
              const Text('Level', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (int i = 0; i <= 9; i++)
                    ChoiceChip(
                      label: Text(i == 0 ? 'Cantrip' : '$i'),
                      selected: _levelFilter == i,
                      onSelected: (sel) {
                        setSheetState(() => _levelFilter = sel ? i : null);
                        _applyFilters();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              
              // School
              const Text('School', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (var school in _schools)
                    ChoiceChip(
                      label: Text(school[0].toUpperCase() + school.substring(1)),
                      selected: _schoolFilter?.toLowerCase() == school.toLowerCase(),
                      onSelected: (sel) {
                        setSheetState(() => _schoolFilter = sel ? school : null);
                        _applyFilters();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Class
              const Text('Class', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var cls in _classes)
                    ChoiceChip(
                      label: Text(cls[0].toUpperCase() + cls.substring(1)),
                      selected: _classFilter?.toLowerCase() == cls.toLowerCase(),
                      onSelected: (sel) {
                        setSheetState(() => _classFilter = sel ? cls : null);
                        _applyFilters();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpellDetail(Spell spell) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _SpellDetailSheet(
          spell: spell,
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

class _SpellDetailSheet extends StatefulWidget {
  final Spell spell;
  final ScrollController scrollController;
  final BleManager bluetooth;

  const _SpellDetailSheet({
    required this.spell,
    required this.scrollController,
    required this.bluetooth,
  });

  @override
  State<_SpellDetailSheet> createState() => _SpellDetailSheetState();
}

class _SpellDetailSheetState extends State<_SpellDetailSheet> {
  bool _isPrinting = false;
  bool _isPreviewing = false;
  Uint8List? _previewImage;

  @override
  Widget build(BuildContext context) {
    final spell = widget.spell;
    
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                // Header
                Text(
                  spell.name,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${spell.levelText} ${spell.school}',
                  style: TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Stats grid
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildStatRow('Casting Time', spell.actionType),
                      _buildStatRow('Range', spell.range),
                      _buildStatRow('Duration', spell.duration),
                      _buildStatRow('Components', spell.componentsText + (spell.material != null ? ' (${spell.material})' : '')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Tags
                if (spell.concentration || spell.ritual)
                  Wrap(
                    spacing: 8,
                    children: [
                      if (spell.concentration)
                        Chip(
                          label: const Text('Concentration'),
                          backgroundColor: Colors.orange.withOpacity(0.2),
                          labelStyle: const TextStyle(color: Colors.orange),
                        ),
                      if (spell.ritual)
                        Chip(
                          label: const Text('Ritual'),
                          backgroundColor: Colors.green.withOpacity(0.2),
                          labelStyle: const TextStyle(color: Colors.green),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                
                // Description
                Text(spell.description, style: const TextStyle(fontSize: 15, height: 1.5)),
                
                // At higher levels
                if (spell.cantripUpgrade != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spell.level == 0 ? 'At Higher Character Levels' : 'At Higher Levels',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(spell.cantripUpgrade!),
                      ],
                    ),
                  ),
                ],
                
                // Classes
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: spell.classes.map((c) => Chip(
                    label: Text(c[0].toUpperCase() + c.substring(1)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )).toList(),
                ),
                
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
                
                const SizedBox(height: 80), // Space for button
              ],
            ),
          ),
          
          // Preview and Print buttons
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
                        onPressed: widget.bluetooth.currentState == BleConnectionState.connected && !_isPrinting
                            ? _printSpell
                            : null,
                        icon: _isPrinting
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.print, size: 24),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
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
      final imageBytes = await _generateSpellCard(widget.spell);
      final preview = ImageProcessor.createPreview(imageBytes);
      setState(() => _previewImage = preview);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview error: $e')),
        );
      }
    } finally {
      setState(() => _isPreviewing = false);
    }
  }

  Future<void> _printSpell() async {
    setState(() => _isPrinting = true);

    try {
      final spell = widget.spell;
      final imageBytes = await _generateSpellCard(spell);
      final printData = ImageProcessor.processForPrinting(imageBytes);
      final dims = ImageProcessor.getProcessedDimensions(imageBytes);

      final protocol = PhomemoProtocol(widget.bluetooth);
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
            content: Text(success ? 'Printed ${spell.name}!' : 'Print failed'),
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

  Future<Uint8List> _generateSpellCard(Spell spell) async {
    // Create a picture recorder
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    const width = 384.0;
    const padding = 12.0;
    const contentWidth = width - (padding * 2);
    
    // Calculate height based on content
    final namePainter = TextPainter(
      text: TextSpan(
        text: spell.name.toUpperCase(),
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    final descPainter = TextPainter(
      text: TextSpan(
        text: spell.description,
        style: const TextStyle(fontSize: 11, color: Colors.black, height: 1.3),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    TextPainter? higherPainter;
    if (spell.cantripUpgrade != null) {
      higherPainter = TextPainter(
        text: TextSpan(
          text: '${spell.level == 0 ? "Higher Levels: " : "At Higher Levels: "}${spell.cantripUpgrade}',
          style: const TextStyle(fontSize: 10, color: Colors.black, fontStyle: FontStyle.italic),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contentWidth);
    }
    
    // Calculate total height
    double height = padding; // Top padding
    height += namePainter.height + 4; // Name
    height += 16; // Level/school line
    height += 8; // Divider spacing
    height += 70; // Stats section
    height += 8; // Divider spacing
    height += descPainter.height + 12; // Description
    if (higherPainter != null) {
      height += higherPainter.height + 16;
    }
    height += 24; // Classes
    height += padding; // Bottom padding
    
    // Draw white background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );
    
    // Draw border
    canvas.drawRect(
      Rect.fromLTWH(4, 4, width - 8, height - 8),
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    
    double y = padding + 4;
    
    // Name (centered)
    namePainter.paint(canvas, Offset((width - namePainter.width) / 2, y));
    y += namePainter.height + 2;
    
    // Level/School (centered)
    final typePainter = TextPainter(
      text: TextSpan(
        text: '${spell.levelText} ${spell.school[0].toUpperCase()}${spell.school.substring(1)}',
        style: const TextStyle(fontSize: 12, color: Colors.black, fontStyle: FontStyle.italic),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    typePainter.paint(canvas, Offset((width - typePainter.width) / 2, y));
    y += typePainter.height + 8;
    
    // Divider
    canvas.drawLine(
      Offset(padding, y),
      Offset(width - padding, y),
      Paint()..color = Colors.black..strokeWidth = 2,
    );
    y += 8;
    
    // Stats (2 columns)
    final stats = [
      ['Cast:', spell.actionType],
      ['Range:', spell.range],
      ['Duration:', spell.duration],
      ['Components:', spell.componentsText],
    ];
    
    for (var stat in stats) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: stat[0],
          style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      final valuePainter = TextPainter(
        text: TextSpan(
          text: ' ${stat[1]}',
          style: const TextStyle(fontSize: 10, color: Colors.black),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contentWidth - labelPainter.width);
      
      labelPainter.paint(canvas, Offset(padding, y));
      valuePainter.paint(canvas, Offset(padding + labelPainter.width, y));
      y += 16;
    }
    
    y += 4;
    
    // Divider
    canvas.drawLine(
      Offset(padding, y),
      Offset(width - padding, y),
      Paint()..color = Colors.black..strokeWidth = 1,
    );
    y += 8;
    
    // Description
    descPainter.paint(canvas, Offset(padding, y));
    y += descPainter.height + 8;
    
    // At higher levels
    if (higherPainter != null) {
      // Dotted line
      for (double x = padding; x < width - padding; x += 6) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x + 3, y),
          Paint()..color = Colors.grey..strokeWidth = 1,
        );
      }
      y += 6;
      higherPainter.paint(canvas, Offset(padding, y));
      y += higherPainter.height + 8;
    }
    
    // Divider
    canvas.drawLine(
      Offset(padding, y),
      Offset(width - padding, y),
      Paint()..color = Colors.black..strokeWidth = 1,
    );
    y += 6;
    
    // Classes (centered)
    final classesPainter = TextPainter(
      text: TextSpan(
        text: spell.classes.map((c) => c[0].toUpperCase() + c.substring(1)).join(' • '),
        style: const TextStyle(fontSize: 10, color: Colors.black),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    classesPainter.paint(canvas, Offset((width - classesPainter.width) / 2, y));
    
    // End recording and create image
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }
}
