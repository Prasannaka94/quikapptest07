#!/bin/bash

echo "🚀 Installing and configuring flutter_launcher_icons..."

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter first."
    exit 1
fi

echo "📦 Running flutter pub get..."
flutter pub get

echo "🎨 Running flutter_launcher_icons..."
flutter pub run flutter_launcher_icons:main

echo "✅ flutter_launcher_icons installation completed!"
echo "📱 Icons generated for both Android and iOS"
echo "📁 Check ios/Runner/Assets.xcassets/AppIcon.appiconset/ for iOS icons"
echo "📁 Check android/app/src/main/res/ for Android icons" 