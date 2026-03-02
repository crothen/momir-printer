# Printer Protocol Reference

## Phomemo T02 (BLE)

Based on [vivier/phomemo-tools](https://github.com/vivier/phomemo-tools).

### Connection
- BLE device name starts with: `T02`
- Service UUID: `0000ff00-0000-1000-8000-00805f9b34fb`
- Write characteristic: `0000ff02-0000-1000-8000-00805f9b34fb`

### Commands

| Command | Bytes | Description |
|---------|-------|-------------|
| Init | `1b 40` | Initialize printer |
| Set energy | `1f 11 02 XX` | Set print darkness (0x00-0xFF) |
| Feed paper | `1b 64 XX` | Feed XX lines |
| Print bitmap | `1d 76 30 00 WW 00 HH HH [data]` | Print WW*8 × HH pixels |

### Image Format
- Width: 384 pixels (48 bytes per line)
- 1-bit packed, MSB first
- Black = 1, White = 0

---

## TiMini / Tiny Print (Classic Bluetooth)

Based on [Dejniel/TiMini-Print](https://github.com/Dejniel/TiMini-Print/blob/master/docs/protocol.md).

### Connection
- Classic Bluetooth SPP (Serial Port Profile)
- Device names vary: GT01, GT02, MX05, etc. (see TiMini-Print for full list)
- RFCOMM channel

### Commands (GT01/GT02 family)

| Command | Bytes | Description |
|---------|-------|-------------|
| Init | `51 78 a3 00 01 00 00 00 ff` | Initialize/wake printer |
| Set density | `51 78 a4 00 01 00 XX 00 ff` | Set darkness (0x41-0x6f) |
| Lattice start | `51 78 a6 00 01 00 00 00 ff` | Begin image transfer |
| Lattice end | `51 78 a3 00 01 00 00 00 ff` | End image transfer |
| Paper feed | `51 78 a1 00 02 00 XX 00 ff` | Feed XX lines |
| Print line | `51 78 a2 00 XX 00 [data] ff` | Print one line (XX = data length) |

### Image Format
- Width: 384 pixels (48 bytes per line) for most models
- 1-bit packed
- Some models use different widths (check model config)

### Flow
1. Send init
2. Send lattice start
3. For each line: send print line command
4. Send lattice end
5. Send paper feed

---

## Image Processing Pipeline

```
Original Image
     ↓
Resize to printer width (384px)
     ↓
Convert to grayscale
     ↓
Floyd-Steinberg dithering → 1-bit
     ↓
Pack into bytes (MSB first)
     ↓
Send to printer
```

### Floyd-Steinberg Dithering

```
         X    7/16
  3/16  5/16  1/16
```

For each pixel:
1. Round to 0 or 255
2. Calculate error = old - new
3. Distribute error to neighbors using weights above
