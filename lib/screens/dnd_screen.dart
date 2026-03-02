import 'package:flutter/material.dart';
import 'spells_screen.dart';
import 'monsters_screen.dart';
import 'magic_items_screen.dart';
import 'equipment_screen.dart';

class DndScreen extends StatelessWidget {
  const DndScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('D&D Compendium'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose Category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  _CategoryCard(
                    title: 'Spells',
                    subtitle: '339 spells',
                    icon: Icons.auto_stories,
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SpellsScreen()),
                    ),
                  ),
                  _CategoryCard(
                    title: 'Monsters',
                    subtitle: '327 creatures',
                    icon: Icons.pets,
                    color: Colors.red,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MonstersScreen()),
                    ),
                  ),
                  _CategoryCard(
                    title: 'Magic Items',
                    subtitle: '241 items',
                    icon: Icons.diamond,
                    color: Colors.amber,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MagicItemsScreen()),
                    ),
                  ),
                  _CategoryCard(
                    title: 'Equipment',
                    subtitle: '132 items',
                    icon: Icons.shield,
                    color: Colors.teal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EquipmentScreen()),
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
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : Colors.grey;
    
    return Card(
      color: effectiveColor.withOpacity(enabled ? 0.2 : 0.1),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: effectiveColor),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: effectiveColor,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: effectiveColor.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
