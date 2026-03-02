import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MomirPrinterApp());
}

class MomirPrinterApp extends StatelessWidget {
  const MomirPrinterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Momir Printer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Izzet colors: blue-red
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
