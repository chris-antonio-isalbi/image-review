# Image Review File Organizer

A native macOS application that automatically organizes your image files based on approval status from your web-based image review system.

## Overview

This app works in conjunction with your existing image review web application. After reviewing images and marking them as "Approved" or "Not Approved" in your web app, you can export the review data as JSON and use this macOS app to automatically organize the physical image files on your computer.

## Features

- 🏷️ **Automatic File Organization**: Sorts images into "Approved" and "Not Approved" folders
- 📁 **Smart File Detection**: Handles various image formats (JPG, PNG, HEIC, TIFF, etc.)
- 🔍 **Flexible Matching**: Matches files even with different extensions
- 🛡️ **Safe Operations**: Creates unique filenames to avoid overwrites
- 📊 **Progress Tracking**: Real-time status updates during organization
- 🎯 **Native macOS**: Fast, native user interface built with Swift

## Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools or Xcode (for building)
- Swift 5.9 or later

## Building the App

1. **Clone or download this repository**
2. **Open Terminal and navigate to the project directory**
3. **Run the build script**:
   ```bash
   ./build.sh
   ```

This will create `FileOrganizerApp.app` in the project directory.

## Installing Xcode Command Line Tools

If you don't have Xcode installed, you can install just the command line tools:

```bash
xcode-select --install
```

## Usage

### Step 1: Add Export Functionality to Your Web App

Add the code from `export-functionality.js` to your existing `Image Review.html` file. Insert it just before the closing `</script>` tag.

This will add an "Export as JSON" button to your web app's sidebar.

### Step 2: Export Review Data

1. Open your image review web application
2. Review and approve/reject images as usual
3. Click the "Export as JSON" button in the sidebar
4. Save the downloaded JSON file to your computer

### Step 3: Organize Files with the macOS App

1. **Launch the app**: Double-click `FileOrganizerApp.app` or run `open FileOrganizerApp.app` in Terminal
2. **Select JSON file**: Click "Browse" next to "JSON File" and select your exported JSON file
3. **Select image folder**: Click "Browse" next to "Image Folder" and choose the folder containing your images
4. **Organize**: Click "Organize Files" to start the process

The app will:
- Create "Approved" and "Not Approved" subfolders in your image directory
- Move files to appropriate folders based on their review status
- Show progress and results in the status area

## JSON Format

The app expects JSON data in this format:

```json
[
  {
    "Image Name": "IMG_001.jpg",
    "Approved": "Yes",
    "Reviewer": "John Doe",
    "Comments": "Approved on 2:30 PM - 15 DEC",
    "Timestamp": "2024-12-15T14:30:00.000Z",
    "Folder": "Product Photos"
  }
]
```

**Required fields:**
- `Image Name`: The filename of the image
- `Approved`: "Yes", "No", "Approved", "Not Approved", etc.

**Optional fields:**
- `Reviewer`: Name of the person who reviewed
- `Comments`: Review comments
- `Timestamp`: When the review was completed
- `Folder`: Source folder name

## File Organization Logic

- **Approved images** (`Approved: "Yes"`) → `Approved/` folder
- **Rejected images** (`Approved: "No"`) → `Not Approved/` folder
- **Pending/Unknown status** → Files remain in original location

## Supported Image Formats

- JPEG (`.jpg`, `.jpeg`)
- PNG (`.png`)
- HEIC (`.heic`)
- TIFF (`.tiff`, `.tif`)
- GIF (`.gif`)
- BMP (`.bmp`)

## Safety Features

- **No file deletion**: Files are only moved, never deleted
- **Duplicate handling**: If a file already exists in the destination, a unique name is created (e.g., `image_1.jpg`)
- **Error handling**: Detailed error reporting for any issues
- **Backup recommendation**: Always backup your files before bulk operations

## Troubleshooting

### Build Issues

**Error: "Cannot find Swift compiler"**
```bash
# Install Xcode command line tools
xcode-select --install
```

**Error: "Permission denied"**
```bash
# Make build script executable
chmod +x build.sh
```

### Runtime Issues

**"App can't be opened because it's from an unidentified developer"**
1. Right-click the app and select "Open"
2. Click "Open" in the security dialog
3. Or disable Gatekeeper temporarily: `sudo spctl --master-disable`

**Files not found**
- Ensure the JSON file contains exact filenames
- Check that image files are in the selected folder
- Verify file extensions match

**Permission denied errors**
- The app may need permission to access certain folders
- Grant Full Disk Access in System Preferences > Privacy & Security

## Development

### Project Structure

```
FileOrganizerApp/
├── Sources/
│   └── FileOrganizerApp.swift    # Main application code
├── Package.swift                  # Swift package definition
├── Info.plist                    # App metadata
├── build.sh                      # Build script
├── export-functionality.js       # Web app export code
├── sample-export.json            # Example JSON format
└── README.md                     # This file
```

### Key Components

- **FileOrganizationService**: Handles file operations and JSON parsing
- **FileOrganizerApp**: Main application class with UI
- **ImageFeedback**: Data model for review information

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is provided as-is for your use. Modify and distribute as needed.

## Support

For issues with the macOS app, check the troubleshooting section above. For issues with your web application integration, ensure the JSON export format matches the expected structure.