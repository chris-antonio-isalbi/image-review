#!/bin/bash

# Build script for File Organizer macOS App
# This script builds the Swift package and creates a proper macOS app bundle

set -e

echo "🏗️  Building File Organizer App..."

# Clean any previous builds
rm -rf .build
rm -rf FileOrganizerApp.app

# Build the Swift package
echo "📦 Building Swift package..."
swift build --configuration release

# Create the app bundle structure
echo "📱 Creating app bundle..."
mkdir -p FileOrganizerApp.app/Contents/MacOS
mkdir -p FileOrganizerApp.app/Contents/Resources

# Copy the executable
cp .build/release/FileOrganizerApp FileOrganizerApp.app/Contents/MacOS/

# Copy the Info.plist
cp Info.plist FileOrganizerApp.app/Contents/

# Make the executable... executable
chmod +x FileOrganizerApp.app/Contents/MacOS/FileOrganizerApp

echo "✅ Build complete! FileOrganizerApp.app is ready to use."
echo ""
echo "To run the app:"
echo "  open FileOrganizerApp.app"
echo ""
echo "Or double-click FileOrganizerApp.app in Finder"