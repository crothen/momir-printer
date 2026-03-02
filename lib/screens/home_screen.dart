import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../widgets/printer_dialog.dart';
import 'photo_print_screen.dart';
import 'momir_screen.dart';
import 'dnd_screen.dart';
import 'deck_printer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _bluetooth = BleManager();
  StreamSubscription<BleConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _connectionSubscription = _bluetooth.connectionState.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  String? get _connectedPrinter => _bluetooth.connectedDeviceName;
  bool get _isConnected => _bluetooth.currentState == BleConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Momir Printer'),
        actions: [
          // Printer connection status
          IconButton(
            icon: Icon(
              _isConnected ? Icons.print : Icons.print_disabled,
              color: _isConnected ? Colors.green : null,
            ),
            onPressed: _showPrinterDialog,
            tooltip: _connectedPrinter ?? 'No printer connected',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Printer status card
            Card(
              child: ListTile(
                leading: Icon(
                  _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _isConnected ? Colors.blue : Colors.grey,
                ),
                title: Text(_connectedPrinter ?? 'No printer connected'),
                subtitle: _isConnected 
                    ? const Text('Ready to print')
                    : const Text('Tap to connect'),
                trailing: _isConnected
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          await _bluetooth.disconnect();
                          setState(() {});
                        },
                        tooltip: 'Disconnect',
                      )
                    : null,
                onTap: _showPrinterDialog,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Mode selection
            const Text(
              'Select Mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  _ModeCard(
                    title: 'Photo Print',
                    icon: Icons.photo,
                    color: Colors.teal,
                    onTap: () => _navigateToMode('photo'),
                  ),
                  _ModeCard(
                    title: 'Momir',
                    subtitle: 'Mo / MoSto / Jhoira',
                    icon: Icons.casino,
                    color: Colors.purple,
                    onTap: () => _navigateToMode('momir'),
                  ),
                  _ModeCard(
                    title: 'Deck Printer',
                    subtitle: 'MTGGoldfish proxies',
                    icon: Icons.style,
                    color: Colors.indigo,
                    onTap: () => _navigateToMode('deck'),
                  ),
                  _ModeCard(
                    title: 'D&D',
                    subtitle: 'Spells • Monsters • Items',
                    icon: Icons.menu_book,
                    color: Colors.deepOrange,
                    onTap: () => _navigateToMode('dnd'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrinterDialog() {
    PrinterDialog.show(context).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _navigateToMode(String mode) {
    switch (mode) {
      case 'photo':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PhotoPrintScreen()),
        );
        break;
      case 'momir':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MomirScreen()),
        );
        break;
      case 'deck':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DeckPrinterScreen()),
        );
        break;
      case 'dnd':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DndScreen()),
        );
        break;
      case 'settings':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings coming soon!')),
        );
        break;
    }
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  const _ModeCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : Colors.grey;
    
    return Card(
      color: effectiveColor.withValues(alpha: enabled ? 0.2 : 0.1),
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
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 11,
                  color: effectiveColor.withValues(alpha: 0.8),
                ),
              ),
            if (!enabled)
              Text(
                'Connect printer first',
                style: TextStyle(
                  fontSize: 10,
                  color: effectiveColor.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
