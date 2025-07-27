# Build Instructions for macOS

Since this is a development environment without Swift installed, here are the steps to build and run the app on your macOS machine:

## Prerequisites

You'll need one of the following on your Mac:
- **Xcode** (recommended) - Download from the Mac App Store
- **Xcode Command Line Tools** (minimal) - Run `xcode-select --install`

## Building the App

1. **Copy the project to your Mac**
   - Download or clone this repository to your Mac
   - Or copy the following files to a new folder:
     - `Sources/FileOrganizerApp.swift`
     - `Package.swift`
     - `Info.plist`
     - `build.sh`

2. **Open Terminal on your Mac** and navigate to the project folder:
   ```bash
   cd /path/to/your/FileOrganizerApp/project
   ```

3. **Make the build script executable**:
   ```bash
   chmod +x build.sh
   ```

4. **Run the build script**:
   ```bash
   ./build.sh
   ```

5. **Launch the app**:
   ```bash
   open FileOrganizerApp.app
   ```

## Alternative Build Method (Using Xcode)

If you prefer using Xcode:

1. **Create a new macOS app project** in Xcode
2. **Replace the default ContentView.swift** with the code from `Sources/FileOrganizerApp.swift`
3. **Update Info.plist** with the settings from our `Info.plist` file
4. **Build and run** (⌘R)

## Manual Swift Build (Without Script)

If you prefer to build manually:

```bash
# Build the executable
swift build --configuration release

# Create app bundle
mkdir -p FileOrganizerApp.app/Contents/MacOS
mkdir -p FileOrganizerApp.app/Contents/Resources

# Copy files
cp .build/release/FileOrganizerApp FileOrganizerApp.app/Contents/MacOS/
cp Info.plist FileOrganizerApp.app/Contents/

# Make executable
chmod +x FileOrganizerApp.app/Contents/MacOS/FileOrganizerApp

# Launch
open FileOrganizerApp.app
```

## Troubleshooting

### "swift: command not found"
Install Xcode Command Line Tools:
```bash
xcode-select --install
```

### "App can't be opened" (Security Warning)
1. Right-click the app → "Open"
2. Click "Open" in the security dialog
3. Or temporarily disable Gatekeeper:
   ```bash
   sudo spctl --master-disable
   # Re-enable after testing:
   sudo spctl --master-enable
   ```

### Build Errors
- Ensure you're running on macOS 13.0 or later
- Update Xcode to the latest version
- Try cleaning and rebuilding: `swift package clean` then `swift build`