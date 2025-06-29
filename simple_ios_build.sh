#!/bin/bash

# Simple iOS Build Script - Workaround for codemagic.yaml syntax issues
# This script performs the essential iOS build steps

set -euo pipefail

echo "🚀 Starting Simple iOS Build Process..."

# Set default PROJECT_ROOT if not set
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
echo "📁 Project root: $PROJECT_ROOT"

# Make scripts executable
echo "🔧 Making scripts executable..."
chmod +x lib/scripts/ios/*.sh 2>/dev/null || true
chmod +x lib/scripts/utils/*.sh 2>/dev/null || true

# Apply Firebase Forward Declaration Fix
echo "🔧 Applying Firebase Forward Declaration Fix..."
if [ -f "lib/scripts/ios/fix_firebase_forward_declaration.sh" ]; then
    chmod +x lib/scripts/ios/fix_firebase_forward_declaration.sh
    if ./lib/scripts/ios/fix_firebase_forward_declaration.sh; then
        echo "✅ Firebase Forward Declaration Fix applied successfully"
    else
        echo "⚠️ Firebase fix failed, continuing anyway..."
    fi
else
    echo "⚠️ Firebase fix script not found, continuing..."
fi

# Apply Bundle Identifier Collision Fix
echo "🔧 Applying Bundle Identifier Collision Fix..."
if [ -f "lib/scripts/ios/fix_bundle_identifier_collision_v2.sh" ]; then
    chmod +x lib/scripts/ios/fix_bundle_identifier_collision_v2.sh
    if ./lib/scripts/ios/fix_bundle_identifier_collision_v2.sh; then
        echo "✅ Bundle Identifier Collision Fix applied successfully"
    else
        echo "⚠️ Bundle ID fix failed, continuing anyway..."
    fi
else
    echo "⚠️ Bundle ID fix script not found, continuing..."
fi

# Run main iOS build
echo "🚀 Running main iOS build script..."
if [ -f "lib/scripts/ios/main.sh" ]; then
    chmod +x lib/scripts/ios/main.sh
    ./lib/scripts/ios/main.sh
else
    echo "❌ Main iOS build script not found!"
    exit 1
fi

echo "✅ iOS build process completed!"

# Validate results
echo "🔍 Validating build results..."
if [ -f "output/ios/Runner.ipa" ]; then
    IPA_SIZE=$(du -h output/ios/Runner.ipa | cut -f1)
    echo "✅ IPA found: output/ios/Runner.ipa ($IPA_SIZE)"
elif [ -d "output/ios/Runner.xcarchive" ]; then
    ARCHIVE_SIZE=$(du -h output/ios/Runner.xcarchive | cut -f1)
    echo "⚠️ Archive found: output/ios/Runner.xcarchive ($ARCHIVE_SIZE)"
    echo "📋 IPA can be exported manually from the archive"
else
    echo "❌ No build artifacts found"
    exit 1
fi

echo "🎉 Simple iOS build completed successfully!" 