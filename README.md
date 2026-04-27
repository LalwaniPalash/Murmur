# Murmur

A lightweight, privacy-first dictation tool for macOS that converts speech to text locally on your device. Murmur integrates seamlessly with your Mac to enable voice input across any application without sending audio to cloud services.

## Features

- **Local Processing**: All audio processing and transcription happens on your Mac—no cloud uploads or internet required
- **Accessibility First**: Designed for accessibility, enabling dictation for all users regardless of typing ability
- **Universal Input**: Insert transcribed text directly into any application (email, documents, messaging, etc.)
- **Intelligent Text Formatting**: Uses llama.cpp to automatically add punctuation, fix capitalization, and improve text quality
- **Multiple Shortcuts**: Trigger dictation via keyboard shortcuts and menu bar access
- **Audio Feedback**: Real-time audio level indicators during recording
- **Settings & Customization**: Configure language, keyboard shortcuts, and behavior preferences
- **Menu Bar Integration**: Convenient menu bar icon for quick access

## Requirements

- **macOS 15 or later** (Sequoia)
- **Microphone**: Built-in or external microphone
- **Whisper CLI**: For speech-to-text transcription (see Installation)
- **Llama CLI** (optional): For intelligent text formatting and punctuation (improves transcription quality)

### Supported Architecture

Murmur runs on both Apple Silicon and Intel Macs:

- **Apple Silicon** (ARM64 / M1, M2, M3, M4 and newer): **Recommended** — uses Metal GPU acceleration for best performance
- **Intel** (x86_64): Fully supported — uses CPU inference (slower, but fully functional)

## Installation

### Quick Start (Recommended)

Murmur can **automatically install** both whisper-cpp and llama.cpp for you if they're not already available on your system. On first launch, you can use the in-app installer:

1. Launch Murmur
2. Go to **Models > Runtime Installers**
3. Click **Install** for each runtime you need
4. The app will clone, build, and configure them automatically

**Note:** This requires CMake (`brew install cmake`), which the app will guide you to install if missing.

### Manual Installation (Alternative)

If you prefer to install via Homebrew instead:

```bash
# Required for transcription
brew install whisper-cpp

# Optional for text formatting (improves quality)
brew install llama-cpp
```

Without llama-cpp, the app works but text formatting features are disabled. For best experience, install both via either method above.

### Building Murmur from Source

1. Open the repository:
   ```bash
   cd Murmur
   ```

2. Build using Swift Package Manager:
   ```bash
   swift build -c release
   ```

3. The compiled binary will be available at `.build/release/Murmur`

4. Move to your Applications folder:
   ```bash
   cp .build/release/Murmur /Applications/Murmur.app
   ```

**Note:** Building Murmur itself doesn't require CMake. The app will automatically build whisper-cpp and llama.cpp runtimes on first use via the in-app installer (see Quick Start above).

### First Launch

On first launch, Murmur will:
1. Request microphone permission (required for audio capture)
2. Verify Whisper CLI installation
3. Show the main hub window and menu bar icon

Grant microphone access when prompted to enable dictation functionality.

## Usage

### Starting Dictation

1. **Via Keyboard Shortcut**: Configure your preferred shortcut in Settings (default: Cmd+Shift+Space)
2. **Via Menu Bar**: Click the waveform icon in your menu bar and select "Start Recording"
3. **Via Scratchpad**: Use the dedicated scratchpad window for testing

### Recording

- Speak clearly and at a normal pace
- Audio level indicator shows input volume
- Press the same shortcut or click Stop to end recording
- The app automatically processes and displays the transcript

### Inserting Text

- After transcription completes, click "Insert" to paste the text into your active application
- Or copy the text from the hub window to use elsewhere

### Keyboard Shortcuts

Configure in **Preferences > Keyboard Shortcuts**:

- **Start/Stop Recording**: Cmd+Shift+Space (customizable)
- **Insert Last Transcript**: Cmd+Shift+Return (customizable)
- **Open Hub**: Cmd+Shift+H (customizable)
- **Open Settings**: Cmd+, (standard macOS)

## Configuration

### Language Support

Select your language and regional variant in **Preferences > Language**. Whisper supports 99+ languages. Your selection affects transcription accuracy and formatting.

### Microphone Selection

Choose from available input devices in **Preferences > Audio > Input Device**. Useful for headsets, USB microphones, or external audio interfaces.

### Text Formatting

Enable or disable automatic formatting options:
- Capitalize sentences
- Add punctuation
- Insert spaces after punctuation

## Troubleshooting

### "Whisper CLI not found" or Transcription Fails

Ensure `whisper-cpp` is installed:
```bash
brew install whisper-cpp
which whisper-cli
```

### Text Formatting Not Working (Llama)

The app works without llama-cli but formatting features are disabled. To enable:
```bash
brew install llama-cpp
which llama-cli
```

If installed but not detected, verify installation:
```bash
/opt/homebrew/bin/llama-cli --version  # Apple Silicon
/usr/local/bin/llama-cli --version     # Intel
```

### No Microphone Input

1. Check **System Settings > Privacy & Security > Microphone** and allow Murmur
2. Test the microphone in **Preferences > Audio**
3. Verify the correct input device is selected

### Poor Transcription Quality

- Reduce background noise
- Speak more clearly and at a normal pace
- Select the correct language in Preferences
- Use a higher-quality microphone

### App Not Responding

Restart the app and check Console.app for error messages:
```bash
log show --predicate 'processImagePath contains "Murmur"' --level debug
```

## Architecture

Murmur follows a modular architecture:

- **App Layer** (`App/`): SwiftUI-based UI coordination and window management
- **Services Layer** (`Services/`): Core business logic including audio capture, transcription, and text insertion
- **Models Layer** (`Models/`): Data models and types
- **Views Layer** (`Views/`): SwiftUI view components

Key services:
- `AudioTranscription`: Manages audio capture and transcription pipeline
- `CLIProcessRunner`: Handles Whisper CLI invocation and communication
- `Insertion`: Handles text insertion into active applications
- `ShortcutMonitor`: Monitors system-wide keyboard shortcuts

## Contributing

Contributions are welcome! To contribute:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes following Swift coding guidelines
4. Write tests for new functionality
5. Commit with clear messages: `git commit -m "feat: describe your change"`
6. Push and open a pull request

### Code Style

- Follow [Apple Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use `swift build` to verify compilation
- Maintain 80%+ test coverage
- Format with SwiftFormat before committing

### Testing

Run tests with:
```bash
swift test
```

## License

MIT License - see LICENSE file for details

## Support

For issues, feature requests, or questions:
- Open an issue on GitHub
- Check existing issues before reporting duplicates
- Provide your macOS version and hardware architecture when reporting bugs

## Acknowledgments

Murmur integrates:
- [Whisper](https://github.com/openai/whisper) via [whisper.cpp](https://github.com/ggml-org/whisper.cpp) for local speech-to-text processing
- [llama.cpp](https://github.com/ggml-org/llama.cpp) for intelligent text formatting and enhancement

Both projects are powered by [GGML](https://github.com/ggml-org/ggml), an efficient tensor library supporting CPU and GPU acceleration.
