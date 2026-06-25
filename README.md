# SpinTouch

A native **SwiftUI + CoreBluetooth** iOS app that connects directly to a
**LaMotte WaterLink SpinTouch** photometer over Bluetooth LE, reads the latest
water-chemistry test, and presents it with in-range status, LSI water balance,
offline recommendations, history/trends, and optional AI explanations.

No proxy, no MCU, no Home Assistant required — just your iPhone and the device.

> **Disclaimer:** This is an independent, unofficial project. It is **not
> affiliated with, endorsed by, or sponsored by LaMotte Company.** LaMotte®,
> WaterLink®, SpinTouch®, and SpinDisk® are trademarks of LaMotte Company, used
> here only to describe interoperability. Water-chemistry guidance (including AI
> output) is informational only — always follow product label instructions and
> consult a professional for serious imbalances.

## Features

- **Direct BLE connection** to the SpinTouch (scan → connect → read → ACK), with
  a polite auto-disconnect so the official LaMotte app can reconnect.
- **Parsed results** with per-parameter ideal-range status (OK / LOW / HIGH).
- **LSI water balance** (Langelier Saturation Index) gauge.
- **Offline recommendations** — deterministic, on-device chemistry guidance.
- **History & trends** — browse past readings and per-metric charts; export
  CSV/JSON.
- **AI read (optional)** — sends the reading and your pool settings to
  Anthropic's Claude using **your own API key** (stored in the Keychain) for a
  plain-English assessment with dosing suggestions. Results are cached locally.

## Requirements

- Xcode 16+ (built/tested against Xcode 26)
- A physical iPhone (BLE does not work in the Simulator)
- A LaMotte SpinTouch with a SpinDisk cartridge
- (Optional, for AI) an Anthropic API key

## Build & run

1. Open `ios/SpinTouch.xcodeproj` in Xcode.
2. Set your own Team under **Signing & Capabilities** (bundle id defaults to
   `com.shreeve.SpinTouch`).
3. Select your iPhone and build & run (⌘R).

See [`ios/README.md`](ios/README.md) for the protocol details and BLE flow.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ios/SpinTouch.xcodeproj -scheme SpinTouch \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Unit tests cover the BLE payload parser, LSI, the recommendation rules, and the
HTML sanitizer.

## Credits & attribution

The BLE protocol (GATT UUIDs, the 91-byte payload format, and the
parameter/disk/sanitizer lookup tables) was adapted under the MIT License from
**[joyfulhouse/lamotte-spintouch](https://github.com/joyfulhouse/lamotte-spintouch)**
(© 2024–2026 JoyfulHouse Real Estate LLC). See [`NOTICE`](NOTICE) for the full
attribution.

## License

[MIT](LICENSE) © 2026 Steve Shreeve. Includes MIT-licensed portions from
lamotte-spintouch (see [`NOTICE`](NOTICE)).
