#!/bin/bash

echo "🔄 Converting AVIF image to PNG format..."

# Check if we have image conversion tools
if command -v convert >/dev/null 2>&1; then
    echo "✅ Using ImageMagick for conversion..."
    convert assets/images/logo.png assets/images/logo_converted.png
    mv assets/images/logo_converted.png assets/images/logo.png
elif command -v sips >/dev/null 2>&1; then
    echo "✅ Using macOS sips for conversion..."
    # Create a backup
    cp assets/images/logo.png assets/images/logo_backup.avif
    # Convert to PNG
    sips -s format png assets/images/logo.png --out assets/images/logo_converted.png
    mv assets/images/logo_converted.png assets/images/logo.png
else
    echo "❌ No image conversion tools found"
    echo "Please install ImageMagick or use a different method"
    exit 1
fi

echo "✅ Image converted to PNG format"
echo "📁 New logo: assets/images/logo.png" 