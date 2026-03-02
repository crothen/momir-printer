import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_service.dart';
import '../services/image_processor.dart';
import '../printers/phomemo_protocol.dart';

class Monster {
  final String name;
  final String meta; // "Large aberration, lawful evil"
  final String ac;
  final String hp;
  final String speed;
  final Map<String, String> stats;
  final String? savingThrows;
  final String? skills;
  final String senses;
  final String languages;
  final String challenge;
  final String? traits;
  final String? actions;
  final String? legendaryActions;
  final String? imgUrl;

  Monster({
    required this.name,
    required this.meta,
    required this.ac,
    required this.hp,
    required this.speed,
    required this.stats,
    this.savingThrows,
    this.skills,
    required this.senses,
    required this.languages,
    required this.challenge,
    this.traits,
    this.actions,
    this.legendaryActions,
    this.imgUrl,
  });

  factory Monster.fromJson(Map<String, dynamic> json) {
    return Monster(
      name: json['name'] ?? '',
      meta: json['meta'] ?? '',
      ac: json['Armor Class'] ?? '',
      hp: json['Hit Points'] ?? '',
      speed: json['Speed'] ?? '',
      stats: {
        'STR': '${json['STR'] ?? '10'} ${json['STR_mod'] ?? '(+0)'}',
        'DEX': '${json['DEX'] ?? '10'} ${json['DEX_mod'] ?? '(+0)'}',
        'CON': '${json['CON'] ?? '10'} ${json['CON_mod'] ?? '(+0)'}',
        'INT': '${json['INT'] ?? '10'} ${json['INT_mod'] ?? '(+0)'}',
        'WIS': '${json['WIS'] ?? '10'} ${json['WIS_mod'] ?? '(+0)'}',
        'CHA': '${json['CHA'] ?? '10'} ${json['CHA_mod'] ?? '(+0)'}',
      },
      savingThrows: json['Saving Throws'],
      skills: json['Skills'],
      senses: json['Senses'] ?? '',
      languages: json['Languages'] ?? '',
      challenge: json['Challenge'] ?? '',
      traits: json['Traits'],
      actions: json['Actions'],
      legendaryActions: json['Legendary Actions'],
      imgUrl: json['img_url'],
    );
  }

  String get size => meta.split(' ').first;
  String get type => meta.split(',').first.split(' ').skip(1).join(' ');
  String get alignment => meta.contains(',') ? meta.split(',').last.trim() : '';
  String get cr => challenge.split('(').first.trim();
}

class MonstersScreen extends StatefulWidget {
  const MonstersScreen({super.key});

  @override
  State<MonstersScreen> createState() => _MonstersScreenState();
}

class _MonstersScreenState extends State<MonstersScreen> {
  final _bluetooth = BleManager();
  final _searchController = TextEditingController();
  
  List<Monster> _allMonsters = [];
  List<Monster> _filteredMonsters = [];
  bool _isLoading = true;
  String? _error;
  
  String? _crFilter;
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _loadMonsters();
  }

  Future<void> _loadMonsters() async {
    try {
      final jsonString = await rootBundle.loadString('assets/monsters.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        _allMonsters = jsonList.map((j) => Monster.fromJson(j)).toList();
        _allMonsters.sort((a, b) => a.name.compareTo(b.name));
        _filteredMonsters = _allMonsters;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load monsters: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredMonsters = _allMonsters.where((monster) {
        if (_searchController.text.isNotEmpty) {
          if (!monster.name.toLowerCase().contains(_searchController.text.toLowerCase())) {
            return false;
          }
        }
        if (_crFilter != null && monster.cr != _crFilter) return false;
        if (_typeFilter != null && !monster.type.toLowerCase().contains(_typeFilter!.toLowerCase())) return false;
        return true;
      }).toList();
    });
  }

  List<String> get _crOptions => _allMonsters.map((m) => m.cr).toSet().toList()..sort((a, b) {
    // Sort CRs numerically
    double aVal = a.contains('/') ? 1.0 / double.parse(a.split('/')[1]) : double.tryParse(a) ?? 0;
    double bVal = b.contains('/') ? 1.0 / double.parse(b.split('/')[1]) : double.tryParse(b) ?? 0;
    return aVal.compareTo(bVal);
  });

  List<String> get _typeOptions {
    final types = <String>{};
    for (var m in _allMonsters) {
      final type = m.type.toLowerCase();
      if (type.contains('aberration')) types.add('aberration');
      else if (type.contains('beast')) types.add('beast');
      else if (type.contains('celestial')) types.add('celestial');
      else if (type.contains('construct')) types.add('construct');
      else if (type.contains('dragon')) types.add('dragon');
      else if (type.contains('elemental')) types.add('elemental');
      else if (type.contains('fey')) types.add('fey');
      else if (type.contains('fiend')) types.add('fiend');
      else if (type.contains('giant')) types.add('giant');
      else if (type.contains('humanoid')) types.add('humanoid');
      else if (type.contains('monstrosity')) types.add('monstrosity');
      else if (type.contains('ooze')) types.add('ooze');
      else if (type.contains('plant')) types.add('plant');
      else if (type.contains('undead')) types.add('undead');
    }
    return types.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('D&D Monsters'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search monsters...',
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
          if (_crFilter != null || _typeFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Wrap(
                spacing: 8,
                children: [
                  if (_crFilter != null)
                    Chip(label: Text('CR $_crFilter'), onDeleted: () { _crFilter = null; _applyFilters(); }),
                  if (_typeFilter != null)
                    Chip(label: Text(_typeFilter!), onDeleted: () { _typeFilter = null; _applyFilters(); }),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(children: [
              Text('${_filteredMonsters.length} monsters', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontWeight: FontWeight.w500)),
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
    if (_filteredMonsters.isEmpty) return const Center(child: Text('No monsters found'));
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filteredMonsters.length,
      itemBuilder: (context, index) => _buildMonsterTile(_filteredMonsters[index]),
    );
  }

  Widget _buildMonsterTile(Monster monster) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(monster.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${monster.meta}\nCR ${monster.cr}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showMonsterDetail(monster),
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
                  TextButton(onPressed: () { setSheetState(() { _crFilter = null; _typeFilter = null; }); _applyFilters(); }, child: const Text('Clear All')),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Challenge Rating', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _crOptions.map((cr) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cr),
                      selected: _crFilter == cr,
                      onSelected: (sel) { setSheetState(() => _crFilter = sel ? cr : null); _applyFilters(); },
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Type', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _typeOptions.map((type) => ChoiceChip(
                  label: Text(type[0].toUpperCase() + type.substring(1)),
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

  void _showMonsterDetail(Monster monster) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _MonsterDetailSheet(
          monster: monster,
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

class _MonsterDetailSheet extends StatefulWidget {
  final Monster monster;
  final ScrollController scrollController;
  final BleManager bluetooth;

  const _MonsterDetailSheet({required this.monster, required this.scrollController, required this.bluetooth});

  @override
  State<_MonsterDetailSheet> createState() => _MonsterDetailSheetState();
}

class _MonsterDetailSheetState extends State<_MonsterDetailSheet> {
  bool _isPrinting = false;

  String _stripHtml(String? html) {
    if (html == null) return '';
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final monster = widget.monster;
    
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
                Text(monster.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text(monster.meta, style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 16),
                
                // AC, HP, Speed
                _buildStatLine('Armor Class', monster.ac),
                _buildStatLine('Hit Points', monster.hp),
                _buildStatLine('Speed', monster.speed),
                const Divider(),
                
                // Ability scores
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: monster.stats.entries.map((e) => Column(
                    children: [
                      Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(e.value.split(' ').first, style: const TextStyle(fontSize: 14)),
                      Text(e.value.split(' ').last, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                    ],
                  )).toList(),
                ),
                const Divider(),
                
                if (monster.savingThrows != null) _buildStatLine('Saving Throws', monster.savingThrows!),
                if (monster.skills != null) _buildStatLine('Skills', monster.skills!),
                _buildStatLine('Senses', monster.senses),
                _buildStatLine('Languages', monster.languages),
                _buildStatLine('Challenge', monster.challenge),
                const Divider(),
                
                if (monster.traits != null) ...[
                  const Text('Traits', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_stripHtml(monster.traits)),
                  const SizedBox(height: 16),
                ],
                
                if (monster.actions != null) ...[
                  const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_stripHtml(monster.actions)),
                  const SizedBox(height: 16),
                ],
                
                if (monster.legendaryActions != null) ...[
                  const Text('Legendary Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_stripHtml(monster.legendaryActions)),
                ],
                
                const SizedBox(height: 80),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: widget.bluetooth.currentState == BleConnectionState.connected && !_isPrinting ? _printMonster : null,
                  icon: _isPrinting ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print, size: 28),
                  label: Text(_isPrinting ? 'Printing...' : 'Print Stat Block', style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
          children: [
            TextSpan(text: '$label ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Future<void> _printMonster() async {
    setState(() => _isPrinting = true);
    try {
      final imageBytes = await _generateMonsterCard(widget.monster);
      final printData = ImageProcessor.processForPrinting(imageBytes);
      final dims = ImageProcessor.getProcessedDimensions(imageBytes);

      final protocol = PhomemoProtocol(widget.bluetooth);
      await protocol.printFullImage(printData, ImageProcessor.defaultWidth, dims.height, density: 0.65, feedLines: 50);
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Printed ${widget.monster.name}!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print error: $e')));
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  Future<Uint8List> _generateMonsterCard(Monster monster) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    const width = 384.0;
    const padding = 10.0;
    const contentWidth = width - (padding * 2);
    
    // Measure text heights
    final namePainter = TextPainter(
      text: TextSpan(text: monster.name.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    final metaPainter = TextPainter(
      text: TextSpan(text: monster.meta, style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.black)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    
    // Calculate height
    double height = padding + namePainter.height + 2 + metaPainter.height + 8;
    height += 60; // AC, HP, Speed
    height += 50; // Stats row
    height += 80; // Senses, Languages, CR
    height += padding;
    
    // Draw
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(3, 3, width - 6, height - 6), Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
    
    double y = padding;
    
    namePainter.paint(canvas, Offset((width - namePainter.width) / 2, y));
    y += namePainter.height + 2;
    metaPainter.paint(canvas, Offset((width - metaPainter.width) / 2, y));
    y += metaPainter.height + 6;
    
    canvas.drawLine(Offset(padding, y), Offset(width - padding, y), Paint()..color = Colors.black..strokeWidth = 1);
    y += 6;
    
    // AC, HP, Speed
    for (var stat in [['AC', monster.ac], ['HP', monster.hp], ['Speed', monster.speed]]) {
      final label = TextPainter(text: TextSpan(text: '${stat[0]}: ', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)), textDirection: TextDirection.ltr)..layout();
      final value = TextPainter(text: TextSpan(text: stat[1], style: const TextStyle(fontSize: 10, color: Colors.black)), textDirection: TextDirection.ltr)..layout(maxWidth: contentWidth - label.width);
      label.paint(canvas, Offset(padding, y));
      value.paint(canvas, Offset(padding + label.width, y));
      y += 16;
    }
    
    y += 4;
    canvas.drawLine(Offset(padding, y), Offset(width - padding, y), Paint()..color = Colors.black..strokeWidth = 1);
    y += 6;
    
    // Stats
    final statKeys = ['STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA'];
    final cellWidth = contentWidth / 6;
    for (int i = 0; i < 6; i++) {
      final x = padding + (i * cellWidth) + (cellWidth / 2);
      final keyPainter = TextPainter(text: TextSpan(text: statKeys[i], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)), textDirection: TextDirection.ltr)..layout();
      final valStr = monster.stats[statKeys[i]]!;
      final valPainter = TextPainter(text: TextSpan(text: valStr.split(' ').first, style: const TextStyle(fontSize: 10, color: Colors.black)), textDirection: TextDirection.ltr)..layout();
      keyPainter.paint(canvas, Offset(x - keyPainter.width / 2, y));
      valPainter.paint(canvas, Offset(x - valPainter.width / 2, y + 12));
    }
    y += 36;
    
    canvas.drawLine(Offset(padding, y), Offset(width - padding, y), Paint()..color = Colors.black..strokeWidth = 1);
    y += 6;
    
    // Senses, Languages, CR
    for (var stat in [['Senses', monster.senses], ['Languages', monster.languages], ['Challenge', monster.challenge]]) {
      final label = TextPainter(text: TextSpan(text: '${stat[0]}: ', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)), textDirection: TextDirection.ltr)..layout();
      final value = TextPainter(text: TextSpan(text: stat[1], style: const TextStyle(fontSize: 9, color: Colors.black)), textDirection: TextDirection.ltr)..layout(maxWidth: contentWidth - label.width);
      label.paint(canvas, Offset(padding, y));
      value.paint(canvas, Offset(padding + label.width, y));
      y += 14;
    }
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
