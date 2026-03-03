# Momir Printer - Build & Deploy Guide

## Overview

Flutter app for thermal mini printers with MTG and D&D game modes. Distributed via Firebase App Distribution.

## Environment

**Build machine:** Chris-Server (WSL2 Ubuntu on Windows)

**Paths:**
- Project: `/home/chris/.openclaw/workspace/momir-printer`
- Flutter SDK: `/home/chris/flutter`
- Android SDK: `/home/chris/android-sdk`

**Firebase:**
- Project: `web-sandbox-crothen`
- Project Number: `558960927637`
- App ID: `1:558960927637:android:f76c73b7ec24f0db2b8c9c`
- Package: `ch.mini_printer.chris`

## Build Commands

### Setup environment
```bash
export ANDROID_HOME=/home/chris/android-sdk
export PATH="$PATH:/home/chris/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"
```

### Build debug APK
```bash
cd /home/chris/.openclaw/workspace/momir-printer
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Deploy to Firebase App Distribution
```bash
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-debug.apk \
  --app 1:558960927637:android:f76c73b7ec24f0db2b8c9c \
  --release-notes "v1.0.X: Description here" \
  --groups "testers"
```

## Version Bumping

Edit `pubspec.yaml`:
```yaml
version: 1.0.X+Y  # X = version, Y = build number
```

## Full Deploy Script

```bash
cd /home/chris/.openclaw/workspace/momir-printer
export ANDROID_HOME=/home/chris/android-sdk
export PATH="$PATH:/home/chris/flutter/bin"

# Build
flutter build apk --debug

# Deploy
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-debug.apk \
  --app 1:558960927637:android:f76c73b7ec24f0db2b8c9c \
  --release-notes "$(git log -1 --pretty=%B)" \
  --groups "testers"
```

## Architecture

```
lib/
├── main.dart
├── models/
│   ├── card.dart              # MTG card model
│   └── werewolf_game.dart     # Werewolf game state
├── printers/
│   ├── printer_protocol.dart  # Abstract interface
│   ├── phomemo_protocol.dart  # ESC/POS protocol (T02, M02, etc.)
│   ├── cat_printer_protocol.dart  # 51 78 protocol (X18, GT01, GB02)
│   └── printer_factory.dart   # Auto-detects protocol from device name
├── services/
│   ├── bluetooth_service.dart # BLE connection management
│   ├── scryfall_service.dart  # Scryfall API client
│   └── image_processor.dart   # Grayscale + Floyd-Steinberg dither
├── screens/
│   ├── home_screen.dart
│   ├── photo_print_screen.dart
│   ├── momir_screen.dart
│   ├── deck_printer_screen.dart
│   ├── dnd_screen.dart
│   ├── werewolf_screen.dart
│   └── printer_test_screen.dart  # Debug/settings for printer protocols
└── widgets/
    └── printer_dialog.dart    # BLE device scanner/connector
```

## Printer Protocols

### Phomemo/ESC-POS (T02, T04, M02, etc.)
- Service UUID: `0xFF00`
- Write characteristic: `0xFF02`
- Commands: Standard ESC/POS (`0x1B` prefix)
- Reference: https://github.com/vivier/phomemo-tools

### Cat Printer (X18, GT01, GB02, MX10, etc.)
- Service UUID: `0xAE30`
- Write characteristic: `0xAE01`
- Commands: `51 78` prefix with CRC
- Reference: https://github.com/rbaron/catprinter

### Protocol Detection
`PrinterFactory.detectType(deviceName)` auto-selects based on Bluetooth device name:
- `x18*`, `gt01*`, `gb0*`, `mx*` → Cat Printer
- `t02*`, `t04*`, `m02*`, `phomemo*` → Phomemo/ESC-POS

### X18 Printer Settings (Seven Star Technology)
Tested and working settings:
- **Protocol:** Cat Printer (51 78 header)
- **CRC:** CRC8 (not simple sum)
- **Bit order:** LSB first
- **New format:** OFF (no 0x12 prefix)
- **Energy:** 80%
- **Row delay:** 0ms
- **Compression:** OFF

## Testers

Firebase App Distribution group: `testers`

Users receive notifications when new builds are deployed. They can also check the Firebase App Tester app manually.

## Troubleshooting

### "Cannot locate Android SDK"
```bash
export ANDROID_HOME=/home/chris/android-sdk
```

### Firebase permission error
Check login status:
```bash
firebase login:list
```

Re-authenticate if needed (requires interactive terminal):
```bash
firebase login --reauth
```

### Flutter not found
```bash
export PATH="$PATH:/home/chris/flutter/bin"
```
