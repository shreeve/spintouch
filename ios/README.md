# SpinTouch iOS

A native SwiftUI + CoreBluetooth app that connects directly to a LaMotte
WaterLink **SpinTouch** over Bluetooth LE, reads the latest water-chemistry
test, and displays the parsed values. No MCU, no Home Assistant, no proxy —
just your iPhone and the device.

AI interpretation ("Get AI Read") is stubbed for a later step; this version
gets the values flowing.

## Why a native app?

iOS does **not** expose raw BLE/GATT to Shortcuts or Safari (no Web Bluetooth),
so reading a custom GATT device like the SpinTouch requires CoreBluetooth in a
real app. The protocol is fully known, so the app is small.

## Requirements

- Xcode 16+ (built/tested against Xcode 26)
- A physical iPhone (BLE does not work in the Simulator)
- A LaMotte SpinTouch with a SpinDisk cartridge

## Build & run

1. Open `SpinTouch.xcodeproj` in Xcode.
2. Select your iPhone as the run destination.
3. Set your own Team under **Signing & Capabilities** (bundle id defaults to
   `com.shreeve.SpinTouch` — change if needed).
4. Build & run (⌘R) and trust the developer profile on the phone if prompted.

The Bluetooth usage string is set via the `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`
build setting, so there is no separate `Info.plist` to manage.

## How to use

1. Power on the SpinTouch, run a test, and **leave it on the results screen**
   (it only advertises over BLE while showing results).
2. Open the app and tap **Scan**.
3. The app connects, subscribes to the status characteristic, reads the
   91-byte result, parses it, and sends the ACK.
4. Values appear as cards with an in-range / high / low chip, plus disk series,
   sanitizer, and report time. Tap the toolbar magnifier for a live BLE log and
   the raw hex payload.

> Only one BLE central can be connected at a time. While this app is connected,
> the official LaMotte phone app cannot connect, and vice-versa.

## How it works

| File | Responsibility |
|---|---|
| `SpinTouchProtocol.swift` | BLE UUIDs, parameter catalog, and the 91-byte payload parser |
| `Models.swift` | `ParameterValue` / `SpinTouchReading` + range-status logic |
| `BLEManager.swift` | CoreBluetooth flow: scan → connect → discover → notify → read → ACK |
| `ContentView.swift` | SwiftUI UI |
| `SpinTouchApp.swift` | App entry point |

### BLE flow

```
scan(service 00000000-0000-1000-8000-BBBD00000000)
  → connect
  → discover service + characteristics
  → setNotifyValue(true, status 0x..11)
  → read(data 0x..10)            // 91 bytes
  → parse + display
  → write(0x01, ack 0x..13)
```

### Payload format (91 bytes)

```
[0-3]   start signature 01 02 03 05
[4-75]  up to 12 entries × 6 bytes: [TestType][Decimals][float32 little-endian]
[76-83] timestamp: YY MM DD HH MM SS AMPM Military
[84]    number of valid results
[85]    disk type index
[86]    sanitizer type index
[87-90] end signature 07 0B 0D 11
```

Parsing scans entries by `TestType` (param id) rather than fixed offsets, since
different SpinDisk series report different parameters. The parser, parameter
map, and ranges mirror the reverse-engineered protocol in
`../misc/lamotte-spintouch/RESEARCH.md` and the proven Home Assistant
integration. It was validated against the real captured payloads in that doc.

## Roadmap

- [ ] Wire up "Get AI Read": POST values + ideal ranges to an LLM and show a
      plain-English assessment with dosing suggestions.
- [ ] Remember the last device and auto-reconnect.
- [ ] History / charts of past readings.
- [ ] Polite auto-disconnect window so the official app can still connect.
