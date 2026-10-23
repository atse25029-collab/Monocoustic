# Monocoustic 🎵

A desktop music player for Windows with synchronized `.lrc` and `.smi` lyrics support, accompanied by an Android APK companion client to control playback from your bed or couch.

---

## ✨ Features

### 💻 Laptop / Desktop Player (Windows)
- **Audio Engine**: Plays local audio formats including `.mp3`, `.flac`, `.wav`, `.aac`, `.ogg`, and `.m4a`.
- **Synchronized Lyrics Engine**:
  - **LRC Support (`.lrc`)**: Standard and multi-timestamp synchronized lyrics (`[mm:ss.xx]`).
  - **SAMI Support (`.smi` / `.sami`)**: Synchronized Accessible Media Interchange subtitle/lyric parsing with HTML tag removal, entity decoding, and multi-language translation support.
  - **Auto-Discovery**: Automatically links companion `.lrc` or `.smi` files residing in the same folder with the same name as the audio file.
  - **Click-to-Seek**: Tap any lyric line on desktop or mobile to jump playback straight to that timestamp.
- **Modern Acrylic UI**: Dark theme, track list with lyric badges, playback controls, and volume control.
- **Embedded Local Control Server**: Runs an in-memory WebSocket and HTTP server on your local Wi-Fi network.
- **One-Tap QR Code Pairing**: Displays an instant pairing QR code and local IP address for the Android app.

### 📱 Android Remote Controller (APK)
- **Couch & Bed Remote Control**:
  - Connects instantly over local Wi-Fi by entering the IP or scanning the QR code on your laptop.
  - Real-time mirrored view of Now Playing track, artist, duration, and progress slider.
- **Synchronized Live Lyrics on Mobile**:
  - Auto-scrolling lyrics stay in sync with laptop playback with active line spotlight.
  - Tap any lyric line on your phone to seek the laptop's music.
- **Desktop Queue Management**:
  - Browse upcoming tracks and switch songs on your laptop from bed.
- **Bedtime Sleep Timer**:
  - Choose 15, 30, 45, or 60 minutes. The player smoothly pauses playback when the timer finishes.

---

## 🚀 Getting Started

### 1. Run the Desktop Player on your Laptop

To run Monocoustic on Windows in development mode:
```powershell
flutter run -d windows
```

To build a standalone Windows release executable:
```powershell
flutter build windows
```
The executable and assets will be output to:
`build\windows\x64\runner\Release\`

---

### 2. Build the Android Remote APK

To build the release APK for your Android phone:
```powershell
flutter build apk --release
```
The installable APK will be output to:
`build\app\outputs\flutter-apk\app-release.apk`

Transfer this `.apk` to your phone and install it (enable "Install unknown apps" if prompted).

---

### 3. Pairing Laptop & Android Phone

1. Make sure your laptop and Android phone are connected to the **same Wi-Fi network**.
2. Open **Monocoustic** on your laptop. In the left sidebar, click **Remote Pairing**.
3. You will see your local LAN IP (e.g., `192.168.1.15:8080`) and a QR code.
4. Open **Monocoustic** on your Android phone, enter the IP, and tap **Connect to Laptop**.
5. You can now lie down on your bed or couch and enjoy full control of your music and live lyrics!

---

## 🧪 Running Tests

To run the unit, protocol, and UI tests:
```powershell
flutter test
```
All lyric parser edge cases (`.lrc` multi-timestamp tags, offsets, `.smi` HTML classes and translations, binary search sync) and WebSocket remote communication protocols are fully covered.
