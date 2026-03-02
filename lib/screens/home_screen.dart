import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _connectedPrinter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Momir Printer'),
        actions: [
          // Printer connection status
          IconButton(
            icon: Icon(
              _connectedPrinter != null ? Icons.print : Icons.print_disabled,
              color: _connectedPrinter != null ? Colors.green : null,
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
                  _connectedPrinter != null ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _connectedPrinter != null ? Colors.blue : Colors.grey,
                ),
                title: Text(_connectedPrinter ?? 'No printer connected'),
                subtitle: _connectedPrinter != null 
                    ? const Text('Ready to print')
                    : const Text('Tap to connect'),
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
                    title: 'Momir Vig',
                    icon: Icons.casino,
                    color: Colors.purple,
                    onTap: () => _navigateToMode('momir'),
                  ),
                  _ModeCard(
                    title: 'MoJoSto',
                    icon: Icons.auto_awesome,
                    color: Colors.orange,
                    onTap: () => _navigateToMode('mojosto'),
                  ),
                  _ModeCard(
                    title: 'Settings',
                    icon: Icons.settings,
                    color: Colors.grey,
                    onTap: () => _navigateToMode('settings'),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect Printer'),
        content: const Text('Bluetooth scanning not yet implemented.\n\nThis will show available printers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _navigateToMode(String mode) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$mode mode not yet implemented')),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
