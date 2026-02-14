# Noa-Flutter: AI Agent Development Guide

> **Purpose**: This document is a comprehensive reference for AI agents contributing to the noa-flutter project. It covers hardware capabilities, SDK APIs, architecture patterns, communication protocols, and practical guidelines for adding features.
>
> **Owner**: Patrick MacDowell (owns Frame hardware for testing)
>
> **Important**: This file is LOCAL ONLY. Do not push to the remote repository.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Hardware Reference: Frame AR Glasses](#2-hardware-reference-frame-ar-glasses)
3. [Architecture Overview](#3-architecture-overview)
4. [Communication Stack](#4-communication-stack)
5. [Flutter SDK Packages](#5-flutter-sdk-packages)
6. [Lua API Reference (Frame-Side)](#6-lua-api-reference-frame-side)
7. [Bluetooth LE Protocol](#7-bluetooth-le-protocol)
8. [State Machine & App Logic](#8-state-machine--app-logic)
9. [Message Protocol & Flags](#9-message-protocol--flags)
10. [Current Feature Inventory](#10-current-feature-inventory)
11. [Project Structure](#11-project-structure)
12. [Key Patterns & Conventions](#12-key-patterns--conventions)
13. [How to Add a New Feature](#13-how-to-add-a-new-feature)
14. [Display Programming Guide](#14-display-programming-guide)
15. [Camera Programming Guide](#15-camera-programming-guide)
16. [Audio Programming Guide](#16-audio-programming-guide)
17. [IMU & Gesture Programming Guide](#17-imu--gesture-programming-guide)
18. [Testing & Debugging](#18-testing--debugging)
19. [Constraints & Gotchas](#19-constraints--gotchas)
20. [Feature Ideas & Extension Points](#20-feature-ideas--extension-points)
21. [Quick Reference Card](#21-quick-reference-card)

---

## 1. Project Overview

**Noa** is a Flutter-based multimodal AI assistant app for **Brilliant Labs Frame** AR glasses. Users interact with Frame by tapping the side of the glasses, which triggers audio recording + photo capture. This data is sent to the Noa backend API (or a custom LLM endpoint), and the AI response is displayed on Frame's micro OLED display and optionally spoken aloud via TTS.

### Key Design Principle

Frame is a **peripheral device**, not a standalone computer. All heavy computation happens on the phone (Flutter app) or in the cloud (Noa API). Frame runs a lightweight Lua event loop that handles:
- Display rendering
- Audio capture & streaming
- Photo capture & transmission
- IMU tap detection
- Bluetooth communication with the host app

### Tech Stack
| Layer | Technology |
|-------|-----------|
| Mobile App | Flutter (Dart) |
| State Management | Riverpod (ChangeNotifierProvider) |
| BLE Communication | frame_ble (wraps flutter_blue_plus) |
| Message Encoding | frame_msg (TxRichText, RxPhoto, etc.) |
| Frame-Side Logic | Lua scripts uploaded at connection |
| Backend | Noa API at `https://api.brilliant.xyz/noa` |
| Auth | Google OAuth, Apple Sign-In, Email WebView |

---

## 2. Hardware Reference: Frame AR Glasses

### Processor & Memory
| Spec | Value |
|------|-------|
| SoC | nRF52840 (Nordic Semiconductor) |
| CPU | 32-bit ARM Cortex-M4F @ 64 MHz |
| Flash | 1 MB |
| RAM | 256 KB |
| FPGA | Crosslink-NX LIFCL-17 (17k logic cells) |

**Critical constraint**: 256 KB RAM is very limited. Lua scripts must be memory-efficient. Always call `collectgarbage("collect")` in loops.

### Display
| Spec | Value |
|------|-------|
| Type | Micro OLED |
| Size | 0.23 inches |
| Resolution | 640 x 400 pixels (RGB) |
| Field of View | 20 degrees |
| Color Palette | Up to 255 colors, optimized for 16 per frame |
| Named Colors | VOID, WHITE, GREY, RED, PINK, DARKBROWN, BROWN, ORANGE, YELLOW, DARKGREEN, GREEN, LIGHTGREEN, NIGHTBLUE, SEABLUE, SKYBLUE, CLOUDBLUE |
| Brightness Levels | -2 to +2 (5 steps) |

**Display coordinate system**: Origin (0,0) is top-left. X: 0-639, Y: 0-399. Text rendering uses Lua `frame.display.text()` with 1-based coordinates.

### Camera
| Spec | Value |
|------|-------|
| Sensor | OV09734 |
| Native Resolution | 1280 x 720 |
| Output | Cropped to 720x720, YCbCr conversion |
| Capture Resolution | 100-720 (even numbers only) |
| Quality Levels | VERY_LOW, LOW, MEDIUM, HIGH, VERY_HIGH |
| Pan Range | -140 to +140 |
| Metering Modes | SPOT, CENTER_WEIGHTED, AVERAGE |

### Microphone
| Spec | Value |
|------|-------|
| Type | ICS-41351 MEMS |
| Sample Rates | 8000 Hz or 16000 Hz |
| Bit Depths | 8-bit or 16-bit (signed integers) |
| Range | 4 kHz to 20 kHz capture |

### IMU (Motion Sensor)
| Spec | Value |
|------|-------|
| Chip | MC6470 |
| Axes | 6-axis (accelerometer + compass) |
| Data | Roll, pitch, heading angles |
| Features | Tap detection callback |
| Raw Data | Accelerometer (x,y,z) + compass (x,y,z) |

### Connectivity & Power
| Spec | Value |
|------|-------|
| Bluetooth | 5.3, sensitivity -95 dBm |
| Battery | 2x 105 mAh Li-ion (210 mAh total) |
| Charging Cradle | Additional 140 mAh |
| Operating Current | 45-100 mA |
| Sleep Current | ~580 uA |
| Operating Temp | 0-45 C |

---

## 3. Architecture Overview

```
+------------------+       BLE        +------------------+
|   Flutter App    | <===============> |   Frame Glasses  |
|   (Host Device)  |                  |   (Peripheral)   |
+------------------+                  +------------------+
|                  |                  |                  |
| - UI (Pages)     |   frame_ble     | - Lua VM         |
| - State Machine  | <-- packets --> | - main.lua       |
| - Riverpod State |   frame_msg     | - app.lua        |
| - Noa API Client |                  | - graphics.lua   |
| - Auth/Location  |                  | - rich_text.lua  |
|                  |                  | - data.min.lua   |
+--------+---------+                  | - camera.min.lua |
         |                            | - code.min.lua   |
         | HTTP/REST                  +------------------+
         v
+------------------+
|   Noa Backend    |
| api.brilliant.xyz|
+------------------+
| - Speech-to-text |
| - Vision AI      |
| - LLM response   |
| - TTS audio      |
+------------------+
```

### Data Flow for a Query

1. User taps Frame side -> IMU tap callback fires
2. Frame sends tap flag (0x10) to Flutter app via BLE
3. Flutter app processes tap count (1=proceed, 2=cancel)
4. On second tap: Flutter sends `startListeningFlag` (0x11) + capture settings
5. Frame starts microphone recording + prepares camera
6. Frame streams audio data (0x05 non-final, 0x06 final) to Flutter
7. Frame captures photo and streams JPEG data to Flutter
8. On third tap: Flutter sends `stopListeningFlag` (0x12)
9. Flutter bundles audio (WAV) + image (JPEG) into multipart POST to Noa API
10. API returns: user_prompt (transcription), message (AI response), audio (TTS), image (optional)
11. Flutter sends response text to Frame via `messageResponseFlag` (0x20) as TxRichText
12. Frame's graphics.lua renders text with scrolling animation on OLED display

---

## 4. Communication Stack

### Layer Model

```
+------------------------------------------+
| Application Layer (Flutter Dart code)     |
| - AppLogicModel state machine             |
| - NoaApi HTTP client                      |
+------------------------------------------+
| Message Layer (frame_msg package)         |
| - TxRichText, TxCode, TxCaptureSettings  |
| - RxPhoto, RxAudio, RxTap                |
+------------------------------------------+
| Transport Layer (frame_ble package)       |
| - BrilliantBluetooth scan/connect         |
| - BrilliantDevice sendMessage/sendString  |
| - Stream<Uint8List> dataResponse          |
+------------------------------------------+
| BLE Layer (flutter_blue_plus)             |
| - TX Characteristic: write to Frame       |
| - RX Characteristic: notify from Frame    |
+------------------------------------------+
```

### Two Communication Modes

**1. Lua REPL Mode (frame_ble only)**
- Send Lua string via `sendString()` -> evaluated on Frame
- Response via `print()` statements on Frame
- Blocking: waits for response
- Used during: firmware check, setup, diagnostics

**2. Message Loop Mode (frame_msg)**
- Frame runs event loop (app.lua) continuously
- Asynchronous bidirectional messaging via `sendMessage(flag, data)`
- Flag byte identifies message type
- Supports fragmentation of large payloads
- Used during: normal operation (tap, listen, display)

---

## 5. Flutter SDK Packages

### frame_ble v3.0.0 - Low-Level BLE

**Import**: `package:frame_ble/brilliant_bluetooth.dart` (and related files)

#### BrilliantBluetooth (Static Methods)
| Method | Returns | Description |
|--------|---------|-------------|
| `requestPermission()` | void | Request BLE permissions from OS |
| `scan()` | `Stream<BrilliantScannedDevice>` | Discover nearby Frame devices |
| `stopScan()` | `Future<void>` | Stop BLE scanning |
| `connect(device)` | `Future<BrilliantDevice>` | Connect to a scanned device |
| `reconnect(address)` | `Future<BrilliantDevice>` | Reconnect to a known device by MAC |

#### BrilliantDevice (Instance)
| Property/Method | Returns | Description |
|----------------|---------|-------------|
| `.device` | `BluetoothDevice` | Underlying flutter_blue_plus device |
| `.state` | `BrilliantConnectionState` | Current connection state enum |
| `.connectionState` | `Stream<BrilliantDevice>` | Stream of connection state changes |
| `.stringResponse` | `Stream<String>` | Lua print() output stream |
| `.dataResponse` | `Stream<Uint8List>` | Binary data stream from Frame |
| `sendString(lua)` | `Future<String>` | Execute Lua code, await response |
| `sendMessage(flag, data)` | `Future<void>` | Send flagged binary message |
| `sendBreakSignal()` | `Future<void>` | Send 0x03 - stop running Lua |
| `sendResetSignal()` | `Future<void>` | Send 0x04 - reset & run main.lua |
| `uploadScript(name, content)` | `Future<void>` | Write Lua file to Frame filesystem |
| `disconnect()` | `Future<void>` | Disconnect BLE |

#### BrilliantConnectionState (Enum)
- `connected` - Normal BLE connection
- `dfuConnected` - Device in firmware update mode
- `disconnected` - Not connected

#### BrilliantScannedDevice
- `.device` - Underlying BluetoothDevice
- `.device.advName` - Advertised device name

#### BrilliantDfuDevice
| Method | Returns | Description |
|--------|---------|-------------|
| `connect()` | `Future<void>` | Connect in DFU mode |
| `updateFirmware(zipPath)` | `Stream<double>` | Flash firmware, stream progress 0.0-1.0 |

### frame_msg v2.0.0 - Application Messaging

**Import**: `package:frame_msg/frame_msg.dart`

#### Transmit Classes (Flutter -> Frame)

**TxRichText** - Text + emoji display message
```dart
TxRichText(
  text: "hello world",   // String to display
  emoji: "\u{F0000}",    // Private-use Unicode emoji
  x: 1,                  // X position (1-640)
  y: 1,                  // Y position (1-400)
  paletteOffset: 1,      // Color index 1-15 (0=VOID invalid)
  spacing: 4,            // Character spacing
).pack()                 // Returns Uint8List
```

**TxCode** - Single-byte control code
```dart
TxCode(value: 0x10).pack()  // Returns Uint8List with the code byte
```

**TxCaptureSettings** - Camera capture configuration
```dart
TxCaptureSettings(
  resolution: 720,       // 100-720 (even numbers)
  qualityIndex: 4,       // 0=VERY_LOW, 1=LOW, 2=MEDIUM, 3=HIGH, 4=VERY_HIGH
).pack()
```

**TxSprite** - Bitmap/image data (available but not currently used in noa)
```dart
TxSprite.fromPngBytes(pngData)  // Convert PNG to Frame sprite format
TxSprite.pack()                  // Serialize for transmission
```

#### Receive Classes (Frame -> Flutter)

**RxPhoto** - Assemble streamed photo data
```dart
RxPhoto(quality: 'HIGH', resolution: 720)
  .attach(device.dataResponse)  // Returns Stream<Uint8List>
  .first                        // Await complete JPEG image
```

**RxAudio** - Assemble streamed audio data
```dart
RxAudio(streaming: false)
  .attach(device.dataResponse)  // Returns Stream<Uint8List>
  .first                        // Await complete audio buffer
```

**RxTap** - Detect tap gestures with debouncing
```dart
RxTap(tapFlag: 0x10, threshold: Duration(milliseconds: 200))
  .attach(device.dataResponse)  // Returns Stream<int>
  .listen((tapCount) {
    // tapCount == 1: single tap
    // tapCount == 2: double tap
  })
```

---

## 6. Lua API Reference (Frame-Side)

These are the Lua functions available on the Frame device. They execute on the nRF52840 SoC.

### Display Module

```lua
-- Text rendering
frame.display.text(string, x, y, {color='WHITE', spacing=4})

-- Bitmap/sprite rendering
-- color_format: 2, 4, or 16 colors
frame.display.bitmap(x, y, width, color_format, palette_offset, data)

-- Flush buffer to screen (MUST call after text/bitmap)
frame.display.show()

-- Color management
frame.display.assign_color(color_index, r, g, b)           -- RGB 0-255
frame.display.assign_color_ycbcr(color_index, y, cb, cr)   -- YCbCr 10-bit

-- Display settings
frame.display.set_brightness(level)    -- -2, -1, 0, 1, or 2
frame.display.power_save(enable)       -- true/false
frame.display.write_register(reg, val) -- Low-level 8-bit register access
```

### Camera Module

```lua
-- Capture a photo
frame.camera.capture{resolution=512, quality='VERY_HIGH', pan=0}
-- resolution: 100-720 (even), quality: VERY_LOW/LOW/MEDIUM/HIGH/VERY_HIGH
-- pan: -140 to 140

-- Check capture status
frame.camera.image_ready()  -- returns boolean

-- Read captured image
frame.camera.read(num_bytes)      -- returns byte string, nil when done
frame.camera.read_raw(num_bytes)  -- skip JPEG header, raw data only

-- Auto exposure control
frame.camera.auto{
  metering='CENTER_WEIGHTED',  -- SPOT, CENTER_WEIGHTED, AVERAGE
  exposure=0.1,
  exposure_speed=0.45,
  shutter_limit=16383,
  analog_gain_limit=16,
  white_balance_speed=0.5,
  rgb_gain_limit=287
}

-- Manual exposure
frame.camera.set_exposure(shutter)       -- 4-16383
frame.camera.set_gain(gain)              -- 1-248
frame.camera.set_white_balance(r, g, b)  -- 0-1023 each

-- Low-level
frame.camera.write_register(addr16, val8)
frame.camera.read_register(addr16)  -- returns 8-bit value
frame.camera.power_save(enable)
```

### Microphone Module

```lua
frame.microphone.start{sample_rate=8000, bit_depth=8}
-- sample_rate: 8000 or 16000
-- bit_depth: 8 or 16

frame.microphone.stop()

frame.microphone.read(num_bytes)
-- returns: byte string (data available)
-- returns: "" (buffer empty but still recording)
-- returns: nil (stopped and buffer exhausted)
```

### IMU Module

```lua
frame.imu.direction()
-- returns: {roll=float, pitch=float, heading=float}

frame.imu.tap_callback(handler_function)
-- handler_function: called on tap event
-- pass nil to deactivate

frame.imu.raw()
-- returns: {accelerometer={x,y,z}, compass={x,y,z}}
```

### Bluetooth Module

```lua
frame.bluetooth.address()        -- returns MAC string "4E:87:B5:0C:64:0F"
frame.bluetooth.max_length()     -- returns max packet size
frame.bluetooth.send(data)       -- send byte string (must not exceed max_length)
frame.bluetooth.receive_callback(handler)  -- handler receives raw byte data
frame.bluetooth.is_connected()   -- returns boolean
```

### File System Module

```lua
frame.file.open(filename, mode)  -- mode: 'read', 'write', 'append'
frame.file.remove(name)
frame.file.rename(name, new_name)
frame.file.listdir(directory)    -- returns: [{name, size, type}, ...]
frame.file.mkdir(pathname)

-- File object methods:
f:read()           -- read line (no args) or f:read(num_bytes)
f:write(data)      -- write byte string
f:close()          -- MUST close after writing to prevent corruption
```

### System Module

```lua
frame.HARDWARE_VERSION      -- string, e.g. 'Frame'
frame.FIRMWARE_VERSION      -- 12-char string, e.g. 'v25.080.0838'
frame.GIT_TAG               -- 7-char git commit hash
frame.battery_level()       -- returns 1-100

frame.sleep(seconds)        -- decimal values OK; no arg = sleep until tap
frame.stay_awake(enable)    -- prevent sleep while docked
frame.update()              -- reboot into DFU bootloader
frame.time.utc(timestamp?)  -- get/set UTC time
frame.time.zone(offset?)    -- get/set timezone '-7:00'
frame.time.date(timestamp?) -- returns {second, minute, hour, day, month, year, weekday, ...}

frame.fpga_read(address, num_bytes)
frame.fpga_write(address, data)
```

### Compression Module

```lua
frame.compression.decompress(data, block_size)
frame.compression.process_function(callback)  -- receives chunks of block_size
```

---

## 7. Bluetooth LE Protocol

### Service & Characteristics

| Item | UUID |
|------|------|
| Service | `7A230001-5475-A6A4-654C-8431F6AD49C4` |
| TX (Host -> Frame) | `7A230002-5475-A6A4-654C-8431F6AD49C4` |
| RX (Frame -> Host) | `7A230003-5475-A6A4-654C-8431F6AD49C4` |

### MTU

- Typical range: 27-251 bytes depending on OS/device
- Raw data overhead: 4 bytes (available = MTU - 4)
- Query on Frame: `frame.bluetooth.max_length()`
- Large payloads are automatically fragmented by frame_msg

### Control Characters (sent raw on TX)

| Byte | Purpose |
|------|---------|
| 0x01 | Prefix for raw byte data (triggers receive_callback) |
| 0x03 | Break signal - terminate running Lua scripts |
| 0x04 | Reset signal - clear variables, run main.lua |

### Pairing

- BLE bonding is required before communication
- Physical pinhole button on Frame un-pairs from previous host
- First connection triggers bonding dialog on phone

---

## 8. State Machine & App Logic

### StateMachine Implementation (`lib/util/state_machine.dart`)

The app uses a custom finite state machine (not a third-party package). Key behavior:

```dart
StateMachine state = StateMachine(State.getUserSettings);

// In triggerEvent():
state.event(someEvent);              // Queue an event
state.onEntry(() async { ... });     // Runs once on state entry
state.changeOn(Event.done, State.nextState);  // Define transition
state.changePending();               // Check if state changed (loop continues)
```

The `triggerEvent()` method loops with `do { ... } while (state.changePending())` allowing cascading state transitions in a single call.

### State Diagram (Simplified)

```
getUserSettings
  |-- done --> disconnected (logged in + paired)
  |-- error --> waitForLogin

waitForLogin
  |-- loggedIn --> scanning

scanning
  |-- deviceFound --> found
  |-- cancelPressed --> disconnected

found
  |-- buttonPressed --> connect
  |-- deviceLost --> scanning

connect
  |-- deviceConnected --> stopLuaApp
  |-- updatableDeviceConnected --> updateFirmware
  |-- deviceInvalid --> requiresRepair

stopLuaApp --> checkFirmwareVersion
  |-- deviceUpToDate --> uploadMainLua
  |-- deviceNeedsUpdate --> triggerUpdate

uploadMainLua
  |-- (scripts uploaded) --> connected (via setPairedDevice -> loggedIn event chain)

disconnected (auto-reconnect loop)
  |-- deviceConnected --> recheckFirmwareVersion

recheckFirmwareVersion
  |-- deviceUpToDate --> checkScriptVersion
  |-- deviceNeedsUpdate --> stopLuaApp

checkScriptVersion
  |-- deviceUpToDate --> connected
  |-- deviceNeedsUpdate --> stopLuaApp

connected (main interaction state)
  |-- noaResponse --> sendResponseToDevice
  |-- deviceDisconnected --> disconnected

sendResponseToDevice --> connected
```

### FrameState (Frame UI State)

```
disconnected --> tapMeIn --> listening --> onit --> printReply --> tapMeIn
                                |                                   ^
                                +-- (double tap: cancel) --> tapMeIn-+
```

### Adding New States

To add a new state to the machine:

1. Add to `State` enum in `app_logic_model.dart`
2. Add case in `triggerEvent()` switch block
3. Define `onEntry()` for initialization logic
4. Define `changeOn()` for outgoing transitions
5. Wire incoming transitions from other states

---

## 9. Message Protocol & Flags

### Phone -> Frame Flags (sent as first byte with `sendMessage`)

| Flag | Hex | Constant | Purpose |
|------|-----|----------|---------|
| TAP_SUBS | 0x10 | `tapFLag` | Subscribe to tap events |
| START_LISTENING | 0x11 | `startListeningFlag` | Begin audio + camera capture |
| STOP_LISTENING | 0x12 | `stopListeningFlag` | Stop recording |
| STOP_TAP | 0x13 | `stopTapFlag` | Unsubscribe from tap events |
| LOOK_AHEAD | 0x14 | `loopAheadFlag` | Check IMU orientation |
| CHECK_FW_VERSION | 0x16 | `checkFwVersionFlag` | Request firmware version |
| CHECK_SCRIPT_VERSION | 0x17 | `checkScriptVersionFlag` | Request script version |
| MESSAGE_RESPONSE | 0x20 | `messageResponseFlag` | Display text on Frame |
| IMAGE_RESPONSE | 0x21 | `imageResponseFlag` | Display image on Frame |
| SINGLE_DATA | 0x22 | `singleDataFlag` | Single-byte control code |
| HOLD_RESPONSE | 0x23 | `holdResponseFlag` | Keep Frame awake |

### Frame -> Phone Flags (received in `dataResponse` stream)

| Flag | Hex | Purpose |
|------|-----|---------|
| AUDIO_NON_FINAL | 0x05 | Audio chunk (more coming) |
| AUDIO_FINAL | 0x06 | Last audio chunk |
| TAP | 0x10 | Tap event occurred |
| CHECK_FW_VERSION | 0x16 | Firmware version response |
| CHECK_SCRIPT_VERSION | 0x17 | Script version response |

### Adding New Flags

To create a new message type:

1. Choose an unused flag byte (check both Dart constants and Lua flags)
2. Add Dart constant in `app_logic_model.dart`
3. Add Lua constant in `app.lua`
4. If sending data: create a TxMsg subclass (see `tx_rich_text.dart` for pattern)
5. If receiving data: add parser in `data.parsers[FLAG]` in Lua, add handler in `handle_messages()` in Lua
6. Add Flutter-side handling in the appropriate state's `onEntry` or stream listener

---

## 10. Current Feature Inventory

| Feature | Status | Files |
|---------|--------|-------|
| Google OAuth login | Complete | `lib/util/sign_in.dart`, `lib/pages/login.dart` |
| Apple Sign-In | Complete | `lib/util/sign_in.dart`, `lib/pages/login.dart` |
| Email sign-in (WebView) | Complete | `lib/pages/login.dart` |
| BLE scanning & pairing | Complete | `lib/models/app_logic_model.dart` |
| Firmware version check | Complete | `app_logic_model.dart`, `app.lua` |
| Firmware update (DFU) | Complete | `app_logic_model.dart` |
| Lua script upload | Complete | `app_logic_model.dart` |
| Tap-to-interact (3-tap flow) | Complete | `app_logic_model.dart`, `app.lua` |
| Double-tap cancel | Complete | `app_logic_model.dart` |
| Audio recording | Complete | `app_logic_model.dart`, `app.lua` |
| Photo capture | Complete | `app_logic_model.dart`, `app.lua` |
| Noa API query (multimodal) | Complete | `lib/noa_api.dart` |
| Custom LLM endpoint | Complete | `lib/pages/tune.dart`, `noa_api.dart` |
| Response display on Frame | Complete | `app_logic_model.dart`, `graphics.lua` |
| TTS audio playback | Complete | `noa_api.dart` |
| Geolocation context | Complete | `lib/util/location.dart` |
| Chat history UI | Complete | `lib/pages/noa.dart` |
| AI tuning (prompt, temp, length) | Complete | `lib/pages/tune.dart` |
| Debug log viewer | Complete | `lib/pages/hack.dart` |
| Foreground service (Android) | Complete | `lib/util/foreground_service.dart` |
| "Look ahead" IMU check | Complete | `app.lua` |
| Auto-sleep timer | Complete | `app.lua` |
| Auto-exposure | Complete | `app.lua` |

---

## 11. Project Structure

```
noa-flutter/
├── .env.template                    # Google OAuth client IDs
├── pubspec.yaml                     # Dart dependencies (v1.6.3)
├── analysis_options.yaml
├── README.md                        # Setup instructions
├── TESTING.md                       # Manual test checklist (50+ cases)
├── docs/
│   └── AGENT_DEVELOPMENT_GUIDE.md   # THIS FILE
│
├── assets/
│   ├── app_icon.png
│   ├── frame-firmware-v25.080.0838.zip
│   ├── images/                      # UI assets + tutorial images
│   └── lua_scripts/                 # Lua code uploaded to Frame
│       ├── main.lua                 # Entry point: require("app")
│       ├── app.lua                  # Main event loop (THE core Frame logic)
│       ├── app.min.lua              # Minified version
│       ├── graphics.lua             # Text rendering + scrolling
│       ├── graphics.min.lua
│       ├── rich_text.lua            # TxRichText parser
│       └── rich_text.min.lua
│
├── lib/
│   ├── main.dart                    # App entry point, init sequence
│   ├── noa_api.dart                 # Backend API client (NoaApi, NoaUser, NoaMessage)
│   ├── bluetooth.dart               # Deprecated (commented out)
│   ├── style.dart                   # Colors & TextStyles (SF Pro Display)
│   │
│   ├── models/
│   │   └── app_logic_model.dart     # STATE MACHINE - core business logic (893 lines)
│   │
│   ├── pages/
│   │   ├── splash.dart              # Loading screen
│   │   ├── login.dart               # Auth page (Google, Apple, Email)
│   │   ├── pairing.dart             # Device pairing UI with progress
│   │   ├── noa.dart                 # Main chat screen
│   │   ├── account.dart             # User settings
│   │   ├── tune.dart                # AI model tuning
│   │   ├── hack.dart                # Debug log viewer
│   │   └── regulatory.dart          # FCC/EU compliance info
│   │
│   ├── widgets/
│   │   ├── bottom_nav_bar.dart      # 3-tab nav: Chat / Hack / Log
│   │   └── top_title_bar.dart       # Header bar
│   │
│   └── util/
│       ├── app_log.dart             # Riverpod logging provider
│       ├── foreground_service.dart   # Android background service
│       ├── location.dart            # GPS + reverse geocoding
│       ├── sign_in.dart             # OAuth handlers
│       ├── state_machine.dart       # Custom FSM implementation
│       ├── tx_rich_text.dart        # TxRichText message class
│       ├── bytes_to_wav.dart        # Audio conversion utility
│       ├── alert_dialog.dart
│       ├── show_toast.dart
│       └── switch_page.dart
│
├── ios/                             # iOS native project
├── android/                         # Android native project
└── packages/frame_msg/lua/          # Lua scripts from frame_msg package
    ├── code.min.lua
    ├── data.min.lua
    └── camera.min.lua
```

---

## 12. Key Patterns & Conventions

### State Management

- **Single ChangeNotifierProvider** (`model`) holds all app state
- Pages read state via `ref.watch(model)` and trigger via `ref.read(model).triggerEvent()`
- All user preferences persist to `SharedPreferences`
- State transitions are logged via `Logger("State machine")`

### Frame Communication Pattern

Always follow this sequence when sending to Frame:

```dart
// 1. For control codes (single byte commands):
_connectedDevice!.sendMessage(singleDataFlag, TxCode(value: someFlag).pack());

// 2. For rich text display:
_connectedDevice!.sendMessage(
  messageResponseFlag,
  TxRichText(text: "message", emoji: "\u{F0000}").pack()
);

// 3. For camera settings:
_connectedDevice!.sendMessage(
  startListeningFlag,
  TxCaptureSettings(resolution: 720, qualityIndex: 4).pack()
);
```

### Receiving Data Pattern

```dart
// Use Rx* classes to decode streamed data:
final image = await RxPhoto(quality: 'HIGH', resolution: 720)
    .attach(_connectedDevice!.dataResponse)
    .first;

final audio = await RxAudio(streaming: false)
    .attach(_connectedDevice!.dataResponse)
    .first;

// For simple flags:
RxTap(tapFlag: 0x10, threshold: Duration(milliseconds: 200))
    .attach(_connectedDevice!.dataResponse)
    .listen((tapCount) { ... });
```

### Lua Script Conventions

- `main.lua` is the entry point (just `require("app")`)
- `app.lua` contains the main event loop
- Helper modules use `require()` and return tables
- Minified versions (.min.lua) are the ones actually uploaded (see pubspec.yaml assets)
- Always call `collectgarbage("collect")` in the main loop
- Use `pcall()` for error-safe BLE sends
- Frame auto-sleeps after ~18 seconds of inactivity

### Error Handling

- BLE operations wrapped in try/catch with state machine error transitions
- Lua BLE sends wrapped in `pcall(frame.bluetooth.send, data)`
- API calls wrapped with timeout handling
- Device disconnection handled via connection state stream

### Styling

- Font: SF Pro Display
- Colors: colorWhite (#FFF), colorLight (#B6BEC9), colorPink (#F288BF), colorRed (#DC0000), colorDark (#292929)
- Dark background theme
- All styles defined in `lib/style.dart`

---

## 13. How to Add a New Feature

### Checklist for Any New Feature

1. **Determine scope**: Does this need Frame-side changes, Flutter-side only, or both?
2. **Read existing code**: Understand the state machine and message protocol first
3. **Choose communication approach**: New flag? Existing flag? Lua REPL?
4. **Implement Frame-side (if needed)**: Modify `app.lua` and/or create new Lua module
5. **Implement Flutter-side**: Add state(s), UI, message handling
6. **Test with hardware**: The owner has Frame glasses for testing
7. **Update minified Lua**: If you changed .lua files, update .min.lua versions

### Example: Adding a New Display Feature

**Scenario**: Show battery level on Frame display when requested.

**Step 1 - Define the protocol**:
```
New flag: 0x24 = BATTERY_REQUEST_FLAG
Response: Frame sends back 0x24 + battery_level_byte
```

**Step 2 - Lua side** (in `app.lua`):
```lua
BATTERY_REQUEST_FLAG = 0x24

-- In handle_messages():
if code_byte == BATTERY_REQUEST_FLAG then
    local level = frame.battery_level()
    send_data(string.char(BATTERY_REQUEST_FLAG) .. string.char(level))
end
```

**Step 3 - Dart side** (in `app_logic_model.dart`):
```dart
const batteryRequestFlag = 0x24;

// Send request:
_connectedDevice!.sendMessage(singleDataFlag, TxCode(value: batteryRequestFlag).pack());

// Listen for response in dataResponse stream:
// flag == batteryRequestFlag -> event[1] is battery level 1-100
```

**Step 4 - UI**: Add display element in the relevant page.

### Example: Adding a New Page

1. Create `lib/pages/my_page.dart`
2. Follow existing page pattern (ConsumerStatefulWidget with Riverpod)
3. Add navigation from `bottom_nav_bar.dart` or `account.dart`
4. Access state via `ref.watch(model)` and `ref.read(model)`

---

## 14. Display Programming Guide

### Display Constraints
- Resolution: 640 x 400 pixels
- 16 colors per frame (from palette of 255)
- Text font is built into firmware (not customizable)
- Character width ~28px at default spacing=4
- Line height ~58px (based on graphics.lua LINE_SPACING)
- Approximately 22 characters per line (based on graphics.lua wrapping logic)
- 3 lines visible simultaneously (based on graphics.lua layout)

### Current Text Rendering (graphics.lua)

The app uses a progressive text reveal animation:
- Text is shown character-by-character at ~70ms intervals
- Three lines visible: last_last_line, last_line, this_line (scrolling upward)
- Word-wrapping at ~22 characters
- Emoji displayed in YELLOW at top-right corner (640 - 91px)
- Top margin: 118px from top

### Displaying Content

From Flutter:
```dart
// Display text with emoji
await _connectedDevice!.sendMessage(
  messageResponseFlag,
  TxRichText(
    text: "Your text here",
    emoji: "\u{F0000}",  // Custom Frame emoji code
  ).pack()
);
```

From Lua:
```lua
-- Direct text (no animation)
frame.display.text("Hello", 1, 1, {color='WHITE'})
frame.display.show()

-- Bitmap
frame.display.bitmap(x, y, width, 2, 0, data)
frame.display.show()
```

### Known Emoji Codes (Private Use Area)

These are custom emoji codes used in the codebase:
| Code | Usage | Context |
|------|-------|---------|
| `\u{F0000}` | "tap me in" state | Default idle emoji |
| `\u{F0003}` | AI response | Shown during reply display |
| `\u{F0008}` | Sleep pending | Before auto-sleep |
| `\u{F000D}` | Boot/startup | Shown on initial load |
| `\u{F0010}` | Listening | During audio recording |

---

## 15. Camera Programming Guide

### Capture Flow

**From Flutter (via frame_msg)**:
```dart
// 1. Set up receiver
_image = RxPhoto(quality: 'HIGH', resolution: 720)
    .attach(_connectedDevice!.dataResponse)
    .first;

// 2. Trigger capture (sends settings to Frame)
await _connectedDevice!.sendMessage(
  startListeningFlag,
  TxCaptureSettings(resolution: 720, qualityIndex: 4).pack()
);

// 3. Await result
Uint8List jpegData = await _image;
```

**From Lua (direct)**:
```lua
frame.camera.capture{resolution=720, quality='HIGH'}
while not frame.camera.image_ready() do
    frame.sleep(0.01)
end
local data = frame.camera.read(512)  -- read in chunks
```

### Auto-Exposure

The app runs auto-exposure every 100ms in the main loop:
```lua
function run_auto_exp(prev, interval)
    local t = frame.time.utc()
    if ((prev == 0) or ((t - prev) > interval)) then
        camera.run_auto_exposure()
        return t
    end
    return prev
end
```

### Image Pipeline

1. Frame captures 720x720 JPEG
2. Streamed over BLE in chunks (0x05 non-final, 0x06 final flags from audio; photo uses different mechanism via frame_msg)
3. RxPhoto reassembles on Flutter side
4. Image processed with `image` package: `encodeJpg(copyRotate(decodeJpg(image)!, angle: 0))`
5. Sent to Noa API as multipart file attachment

---

## 16. Audio Programming Guide

### Audio Capture Flow

```dart
// Flutter side
_audio = RxAudio(streaming: false)
    .attach(_connectedDevice!.dataResponse)
    .first;

// Frame Lua side starts recording when startListeningFlag received:
frame.microphone.start{sample_rate=8000, bit_depth=8}

// Frame streams audio in the main loop:
function transfer_audio_data()
    local mtu = frame.bluetooth.max_length()
    local audio_data_size = math.floor((mtu - 1) / 2) * 2
    for i=1,20 do
        audio_data = frame.microphone.read(audio_data_size)
        if audio_data == nil then
            send_data(string.char(AUDIO_DATA_FINAL_MSG))
            break
        elseif audio_data ~= '' then
            send_data(string.char(AUDIO_DATA_NON_FINAL_MSG) .. audio_data)
        else
            break
        end
    end
end
```

### Audio Processing

- Raw PCM from Frame: 8-bit, 8000 Hz mono
- Converted to WAV on Flutter side via `bytesToWav(audio, 8, 8000)`
- Sent to Noa API which handles speech-to-text
- TTS response comes back as MP3, played via `just_audio` package

---

## 17. IMU & Gesture Programming Guide

### Tap Detection

**Lua side** (registers callback):
```lua
frame.imu.tap_callback(handle_tap)  -- enable
frame.imu.tap_callback(nil)          -- disable
```

**Flutter side** (via RxTap):
```dart
RxTap(tapFlag: tapFLag, threshold: Duration(milliseconds: 200))
    .attach(_connectedDevice!.dataResponse)
    .listen((taps) {
  if (taps == 1) { /* single tap */ }
  if (taps == 2) { /* double tap - cancel */ }
});
```

### Head Orientation ("Look Ahead")

The app checks if the user is looking forward before processing:
```lua
local pos = frame.imu.direction()
-- Roll: -20 to 20, Pitch: -60 to 40 = "looking ahead"
if not (pos['roll'] > -20 and pos['roll'] < 20
    and pos['pitch'] > -60 and pos['pitch'] < 40) then
    -- Not looking ahead, show warning
else
    -- OK to proceed
end
```

### Raw IMU Data

```lua
local raw = frame.imu.raw()
-- raw.accelerometer.x, .y, .z
-- raw.compass.x, .y, .z
```

Useful for: head tracking, gesture recognition, activity detection, compass heading.

---

## 18. Testing & Debugging

### Running the App

```bash
# Get dependencies
flutter pub get

# Run in debug mode (allows hot reload)
flutter run

# Run in release mode (required for real BLE testing)
flutter run --release

# iOS specific
cd ios && pod install && cd ..
flutter run --release -d <ios-device-id>
```

### Debug Logging

The app uses structured logging via the `logging` package:

```dart
final _log = Logger("MyComponent");
_log.info("Something happened");
_log.warning("Something went wrong");
_log.fine("Detailed debug info");
```

Logs are visible in:
- Flutter debug console
- The "LOG" tab in the app (HackPage) via `appLog` Riverpod provider

### BLE Debugging Tips

- Check `_connectedDevice?.state` before sending messages
- Watch `connectionState` stream for unexpected disconnections
- Frame auto-sleeps after ~18 seconds of no BLE messages
- Send `holdResponseFlag` to keep Frame awake during long operations
- If Frame becomes unresponsive, use pinhole button to reset pairing

### Common Test Scenarios (from TESTING.md)

- Permission handling (BLE, Location)
- Login/logout flows
- Device pairing (first time, reconnection)
- Tap interaction (1-tap, 2-tap, 3-tap, double-tap cancel)
- Audio + photo capture quality
- API response display on Frame
- Background operation
- Firmware update flow

---

## 19. Constraints & Gotchas

### Hardware Constraints

1. **256 KB RAM**: Lua scripts must be memory-efficient. Call `collectgarbage("collect")` regularly.
2. **MTU limits**: BLE packets are limited (27-251 bytes). Large data must be fragmented. frame_msg handles this.
3. **16 colors per frame**: Display palette is limited. Plan visual designs accordingly.
4. **~22 chars per line**: Text wraps at about 22 characters on the 640px display.
5. **3 lines max visible**: The graphics system shows 3 lines of text maximum.
6. **Battery: 210 mAh**: Active use (camera + mic + display + BLE) drains quickly at 45-100 mA.
7. **Camera is 720x720 max**: Resolution cannot exceed 720, must be even numbers.
8. **Mic is 8 or 16 kHz only**: Limited sample rates.
9. **No persistent storage for app data**: Frame's filesystem is mainly for Lua scripts. User data should be stored on the phone (SharedPreferences).

### Software Constraints

1. **frame_msg v2.0.0 is current**: Don't downgrade to deprecated `frame_sdk` package.
2. **Minified Lua required**: pubspec.yaml references `.min.lua` files. If you edit `.lua` files, the minified versions must also be updated.
3. **Firmware version must match**: `_firmwareVersion` constant in `app_logic_model.dart` must match the firmware ZIP in assets.
4. **Script version tracking**: `_scriptVersion` in Dart must match `SCRIPT_VERSION` in `app.lua`.
5. **iOS requires bluetooth-central background mode**: Already configured but don't remove.
6. **Android foreground service**: Required for BLE in background on Android.
7. **State machine is NOT async-safe**: `triggerEvent()` can cause reentrant issues if called from multiple async contexts simultaneously. Events from streams should be serialized.
8. **Lua `print()` vs `frame.bluetooth.send()`**: `print()` goes to stringResponse stream. `frame.bluetooth.send()` goes to dataResponse stream. Don't mix them up.
9. **Auto-sleep timer**: Frame sleeps after 18 seconds of no BLE messages. Use `holdResponseFlag` to prevent this during long operations.

### Common Mistakes

- Forgetting `frame.display.show()` after drawing on Frame display
- Not calling `collectgarbage("collect")` in Lua loops (memory leak -> crash)
- Sending data larger than `frame.bluetooth.max_length()` (BLE error)
- Not handling `_cancelled` flag checks between async operations
- Forgetting to close Lua files after writing (`f:close()`)
- Using wrong stream (stringResponse vs dataResponse) for the data type

---

## 20. Feature Ideas & Extension Points

These are areas where new functionality could be added:

### Display Enhancements
- **Rich formatted text**: Multiple colors, sizes (via bitmap rendering)
- **Image display**: Use TxSprite to show images/icons on the OLED
- **Animations**: Frame-side animation loops
- **Status bar**: Battery, time, connection indicator
- **Multiple display modes**: Clock, compass, notifications, etc.

### Camera / Vision
- **Continuous capture mode**: Periodic photo capture for scene awareness
- **QR/barcode scanning**: Capture + decode on Flutter side
- **Object detection overlay**: Process image -> show labels on display
- **Photo gallery**: Save captured images with metadata
- **Video-like streaming**: Rapid capture for near-real-time vision

### Audio / Voice
- **Voice commands**: Local speech-to-text for quick actions
- **Audio notifications**: Alert sounds played through phone speaker
- **Continuous listening mode**: Always-on voice assistant
- **Voice memos**: Record and save audio clips

### IMU / Gesture
- **Custom gestures**: Head nod (yes), head shake (no)
- **Activity tracking**: Step counting via accelerometer
- **Compass heading display**: Show direction on Frame
- **Gaze-based scrolling**: Tilt head to scroll text

### AI / LLM
- **Multiple AI providers**: OpenAI, Anthropic, local models
- **Conversation branching**: Multiple chat threads
- **Context persistence**: Save/load conversation context
- **Image generation**: Display AI-generated images on Frame
- **Real-time translation**: Hear speech, show translation

### System
- **Notification forwarding**: Show phone notifications on Frame
- **Calendar integration**: Upcoming event display
- **Weather widget**: Show current conditions
- **Navigation**: Turn-by-turn directions on display
- **Smart home control**: Voice commands -> IoT actions

---

## 21. Quick Reference Card

### Key Files to Edit for Most Features

| What | File |
|------|------|
| State machine / core logic | `lib/models/app_logic_model.dart` |
| Backend API calls | `lib/noa_api.dart` |
| Frame-side event loop | `assets/lua_scripts/app.lua` |
| Frame display rendering | `assets/lua_scripts/graphics.lua` |
| Frame message parsing | `assets/lua_scripts/rich_text.lua` |
| Custom TX message types | `lib/util/tx_rich_text.dart` |
| UI pages | `lib/pages/*.dart` |
| App styling | `lib/style.dart` |
| Dependencies | `pubspec.yaml` |

### Key Constants

```dart
// Firmware & scripts
const _firmwareVersion = "v25.080.0838";
const _scriptVersion = "v1.0.8";

// Photo settings
const resolution = 720;
const qualityLevel = 'HIGH';

// API endpoint
const endpoint = 'https://api.brilliant.xyz/noa';
```

### Frame Display Layout Constants (from graphics.lua)

```lua
TOP_MARGIN = 118        -- Y offset from top
LINE_SPACING = 58       -- Vertical spacing between lines
EMOJI_MAX_WIDTH = 91    -- Space reserved for emoji (right side)
MAX_CHARS_PER_LINE = 22 -- Approximate characters per line
MAX_VISIBLE_LINES = 3   -- Lines shown simultaneously
```

### BLE Message Quick Reference

```dart
// Send text to Frame display
sendMessage(messageResponseFlag, TxRichText(text: "hi", emoji: "\u{F0000}").pack())

// Send control code
sendMessage(singleDataFlag, TxCode(value: someFlag).pack())

// Start audio+camera recording
sendMessage(startListeningFlag, TxCaptureSettings(resolution: 720, qualityIndex: 4).pack())

// Stop recording
sendMessage(singleDataFlag, TxCode(value: stopListeningFlag).pack())

// Keep Frame awake
sendMessage(singleDataFlag, TxCode(value: holdResponseFlag).pack())

// Subscribe to taps
sendMessage(singleDataFlag, TxCode(value: tapFLag).pack())

// Check firmware version
sendMessage(singleDataFlag, TxCode(value: checkFwVersionFlag).pack())
```

### Riverpod Access Pattern

```dart
// In a ConsumerStatefulWidget:
final appModel = ref.watch(model);           // Reactive rebuild on change
final appModel = ref.read(model);            // One-time read
ref.read(model).triggerEvent(Event.done);    // Trigger state change
```

---

## Appendix A: Noa API Reference

### POST `https://api.brilliant.xyz/noa`

**Headers**: `Authorization: <user_auth_token>`

**Multipart Fields**:
| Field | Type | Description |
|-------|------|-------------|
| audio | File (WAV) | 8-bit 8kHz mono audio |
| image | File (JPEG) | 720x720 JPEG from Frame camera |
| messages | JSON string | Chat history array [{role, content}] |
| noa_system_prompt | String | System prompt + length constraint |
| temperature | String | "0.0" to "2.0" |
| tts | String | "1" or "0" |
| promptless | String | "1" or "0" |
| location | String | Reverse-geocoded address |
| time | String | Current timestamp |

**Response** (JSON):
```json
{
  "user_prompt": "transcribed speech",
  "message": "AI response text",
  "audio": "base64_mp3_tts",
  "image": "base64_generated_image_or_null",
  "debug": {
    "topic_changed": false
  }
}
```

### GET `https://api.brilliant.xyz/noa/user`
**Headers**: `Authorization: <token>`
**Response**: `{ "user": { "email", "plan", "credit_used", "credit_total" } }`

### POST `https://api.brilliant.xyz/noa/user/signin`
**Body**: `{ "id_token", "provider" }` (google/apple/discord)
**Response**: `{ "token": "auth_token" }`

### POST `https://api.brilliant.xyz/noa/user/signout`
**Headers**: `Authorization: <token>`

### POST `https://api.brilliant.xyz/noa/user/delete`
**Headers**: `Authorization: <token>`

### POST `https://api.brilliant.xyz/noa/wildcard`
**Headers**: `Authorization: <token>`
**Fields**: noa_system_prompt, location, time, temperature, tts

---

## Appendix B: Development Environment Setup

```bash
# Prerequisites
- Flutter SDK >=3.3.1
- Xcode (for iOS)
- Android Studio (for Android)
- Physical device (BLE doesn't work in simulators)

# Setup
git clone https://github.com/brilliantlabsAR/noa-flutter.git
cd noa-flutter
cp .env.template .env
# Edit .env with Google OAuth client IDs (optional)
flutter pub get

# iOS
cd ios && pod install && cd ..

# Run on device
flutter run --release
```

### Version Sync Checklist

When updating firmware or scripts:
1. Update `_firmwareVersion` in `lib/models/app_logic_model.dart`
2. Place new firmware ZIP in `assets/` with matching name
3. Update `SCRIPT_VERSION` in `assets/lua_scripts/app.lua`
4. Update `_scriptVersion` in `lib/models/app_logic_model.dart`
5. Regenerate `.min.lua` files for any changed Lua scripts
6. Update `pubspec.yaml` assets if filenames changed
