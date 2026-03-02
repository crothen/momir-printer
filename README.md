# Momir Printer

A Flutter app for thermal mini printers with MTG Momir Vig / MoJoSto game modes.

## Features

- **Photo Print**: Select an image, convert to grayscale, dither, and print
- **Momir Vig**: Pay X mana → get a random creature with mana value X (via Scryfall API)
- **MoJoSto**: Full game mode with Momir + Jhoira (instants/sorceries) + Stonecloaker (bounce)

## Supported Printers

| Printer | Protocol | Connection |
|---------|----------|------------|
| Phomemo T02 | vivier/phomemo-tools | BLE |
| Generic "Tiny Print" printers | Dejniel/TiMini-Print | Classic Bluetooth |

## Architecture

```
lib/
├── main.dart
├── models/
│   ├── card.dart              # MTG card model
│   └── printer_config.dart    # Printer settings
├── printers/
│   ├── printer_protocol.dart  # Abstract interface
│   ├── phomemo_protocol.dart  # T02 BLE protocol
│   └── timini_protocol.dart   # Generic Classic BT protocol
├── services/
│   ├── bluetooth_service.dart # BLE + Classic BT handling
│   ├── scryfall_service.dart  # Scryfall API client
│   └── image_processor.dart   # Grayscale + Floyd-Steinberg dither
├── screens/
│   ├── home_screen.dart
│   ├── photo_print_screen.dart
│   └── momir_screen.dart
└── widgets/
    └── ...
```

## Protocol References

- **Phomemo T02**: https://github.com/vivier/phomemo-tools
- **TiMini (Tiny Print)**: https://github.com/Dejniel/TiMini-Print/blob/master/docs/protocol.md

## Scryfall API

- Random creature at CMC X: `GET https://api.scryfall.com/cards/random?q=type:creature+cmc:{X}`
- Random instant/sorcery at CMC X: `GET https://api.scryfall.com/cards/random?q=(type:instant+OR+type:sorcery)+cmc:{X}`
- Rate limit: 50-100ms between requests

## MoJoSto Rules

Players start with an emblem granting three abilities:
- **Momir Vig** ({X}, Discard a card): Create a token copy of a random creature with MV X
- **Jhoira** ({X}, Discard a card): Cast a random instant/sorcery with MV X
- **Stonecloaker** ({3}): Return a creature you control to its owner's hand

## Setup

1. Clone the repo
2. Run `flutter create .` to initialize Flutter scaffolding
3. Add dependencies to `pubspec.yaml`:
   ```yaml
   dependencies:
     flutter_blue_plus: ^1.31.0
     flutter_bluetooth_serial: ^0.4.0
     image: ^4.1.0
     http: ^1.2.0
     permission_handler: ^11.3.0
   ```
4. Run `flutter pub get`
5. Build and run

## License

MIT
