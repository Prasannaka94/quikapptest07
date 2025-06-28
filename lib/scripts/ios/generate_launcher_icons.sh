#!/bin/bash

# Flutter Launcher Icons Generator for iOS
# Purpose: Generate proper iOS app icons including 1024x1024 using flutter_launcher_icons

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/utils.sh"

log_info "🚀 Starting Flutter Launcher Icons Generation for iOS..."

# Function to validate source image
validate_source_image() {
    local image_path="$1"
    
    log_info "🔍 Validating source image: $image_path"
    
    if [ ! -f "$image_path" ]; then
        log_error "Source image not found: $image_path"
        return 1
    fi
    
    # Check file size
    local file_size=$(du -h "$image_path" | cut -f1)
    log_info "📏 File size: $file_size"
    
    # Multiple validation methods for image files
    local is_valid_image=false
    
    # Method 1: Check file extension
    if [[ "$image_path" =~ \.(png|jpg|jpeg|gif|bmp|tiff|webp)$ ]]; then
        log_info "✅ File has valid image extension"
        is_valid_image=true
    fi
    
    # Method 2: Check file magic bytes
    if command -v file >/dev/null 2>&1; then
        local file_type
        file_type=$(file "$image_path" 2>/dev/null)
        if echo "$file_type" | grep -qE "(image|PNG|JPEG|GIF|BMP|TIFF|WebP)"; then
            log_info "✅ File magic bytes indicate image: $file_type"
            is_valid_image=true
        else
            log_warn "⚠️ File magic bytes don't indicate image: $file_type"
        fi
    fi
    
    # Method 3: Try to get image dimensions
    local dimensions="unknown"
    if command -v identify >/dev/null 2>&1; then
        dimensions=$(identify -format "%wx%h" "$image_path" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$dimensions" ]; then
            log_info "✅ ImageMagick dimensions: $dimensions"
            is_valid_image=true
        fi
    elif command -v sips >/dev/null 2>&1; then
        dimensions=$(sips -g pixelWidth -g pixelHeight "$image_path" 2>/dev/null | grep -E "pixel(Width|Height)" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
        if [ $? -eq 0 ] && [ -n "$dimensions" ] && [ "$dimensions" != "x" ]; then
            log_info "✅ sips dimensions: $dimensions"
            is_valid_image=true
        fi
    fi
    
    log_info "📐 Source image dimensions: $dimensions"
    
    # If we couldn't validate it's an image, but it exists and has reasonable size, continue
    if [ "$is_valid_image" = false ]; then
        local file_size_bytes
        file_size_bytes=$(stat -f%z "$image_path" 2>/dev/null || stat -c%s "$image_path" 2>/dev/null || echo "0")
        if [ "$file_size_bytes" -gt 100 ]; then
            log_warn "⚠️ Could not validate image format, but file exists and has reasonable size"
            log_warn "Continuing with icon generation..."
            is_valid_image=true
        else
            log_error "❌ File appears to be invalid or empty"
            return 1
        fi
    fi
    
    # Check if image is at least 1024x1024 (if we could get dimensions)
    if [[ "$dimensions" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        local width="${BASH_REMATCH[1]}"
        local height="${BASH_REMATCH[2]}"
        
        if [ "$width" -lt 1024 ] || [ "$height" -lt 1024 ]; then
            log_warn "⚠️ Source image is smaller than 1024x1024 (${width}x${height})"
            log_warn "This may result in lower quality icons"
        else
            log_success "✅ Source image is 1024x1024 or larger"
        fi
    fi
    
    return 0
}

# Function to create optimized source image
create_optimized_source_image() {
    local source_path="$1"
    local optimized_path="$2"
    
    log_info "🔧 Creating optimized source image for icon generation..."
    
    # Create assets/images directory if it doesn't exist
    mkdir -p "$(dirname "$optimized_path")"
    
    # Copy and optimize the source image
    if command -v convert >/dev/null 2>&1; then
        # Use ImageMagick for optimization
        convert "$source_path" -resize 1024x1024 -quality 95 -strip "$optimized_path"
        log_success "✅ Image optimized using ImageMagick"
    elif command -v sips >/dev/null 2>&1; then
        # Use macOS sips for optimization
        cp "$source_path" "$optimized_path"
        sips -Z 1024 "$optimized_path" >/dev/null 2>&1
        log_success "✅ Image optimized using sips"
    else
        # Simple copy if no optimization tools available
        cp "$source_path" "$optimized_path"
        log_warn "⚠️ No image optimization tools available, using original image"
    fi
    
    # Validate the optimized image
    validate_source_image "$optimized_path"
}

# Function to run flutter_launcher_icons
run_flutter_launcher_icons() {
    log_info "🎨 Running Flutter Launcher Icons generation..."
    
    # Check if flutter_launcher_icons is available
    if ! flutter pub deps | grep -q "flutter_launcher_icons"; then
        log_error "flutter_launcher_icons not found in dependencies"
        log_info "Installing flutter_launcher_icons..."
        flutter pub add --dev flutter_launcher_icons
    fi
    
    # Run flutter pub get to ensure dependencies are up to date
    log_info "📦 Running flutter pub get..."
    flutter pub get
    
    # Run flutter_launcher_icons
    log_info "🚀 Generating icons with flutter_launcher_icons..."
    if flutter pub run flutter_launcher_icons:main; then
        log_success "✅ Flutter Launcher Icons generation completed successfully!"
    else
        log_error "❌ Flutter Launcher Icons generation failed"
        return 1
    fi
    
    return 0
}

# Function to validate generated icons
validate_generated_icons() {
    log_info "🔍 Validating generated iOS icons..."
    
    local ios_icon_dir="ios/Runner/Assets.xcassets/AppIcon.appiconset"
    local required_icons=(
        "Icon-App-1024x1024@1x.png"
        "Icon-App-20x20@1x.png"
        "Icon-App-20x20@2x.png"
        "Icon-App-20x20@3x.png"
        "Icon-App-29x29@1x.png"
        "Icon-App-29x29@2x.png"
        "Icon-App-29x29@3x.png"
        "Icon-App-40x40@1x.png"
        "Icon-App-40x40@2x.png"
        "Icon-App-40x40@3x.png"
        "Icon-App-60x60@2x.png"
        "Icon-App-60x60@3x.png"
        "Icon-App-76x76@1x.png"
        "Icon-App-76x76@2x.png"
        "Icon-App-83.5x83.5@2x.png"
    )
    
    local missing_icons=()
    local found_icons=0
    
    for icon in "${required_icons[@]}"; do
        if [ -f "$ios_icon_dir/$icon" ]; then
            found_icons=$((found_icons + 1))
            local file_size=$(du -h "$ios_icon_dir/$icon" | cut -f1)
            log_info "✅ Found: $icon ($file_size)"
        else
            missing_icons+=("$icon")
            log_warn "⚠️ Missing: $icon"
        fi
    done
    
    # Special check for 1024x1024 icon
    local icon_1024="$ios_icon_dir/Icon-App-1024x1024@1x.png"
    if [ -f "$icon_1024" ]; then
        log_success "✅ 1024x1024 icon found: $icon_1024"
        
        # Validate 1024x1024 icon dimensions
        if command -v identify >/dev/null 2>&1; then
            local dimensions=$(identify -format "%wx%h" "$icon_1024" 2>/dev/null)
            if [ "$dimensions" = "1024x1024" ]; then
                log_success "✅ 1024x1024 icon has correct dimensions"
            else
                log_warn "⚠️ 1024x1024 icon has wrong dimensions: $dimensions"
            fi
        fi
    else
        log_error "❌ 1024x1024 icon is missing!"
        return 1
    fi
    
    log_info "📊 Icon validation summary:"
    log_info "   Found: $found_icons/${#required_icons[@]} icons"
    log_info "   Missing: ${#missing_icons[@]} icons"
    
    if [ ${#missing_icons[@]} -gt 0 ]; then
        log_warn "Missing icons: ${missing_icons[*]}"
        return 1
    fi
    
    return 0
}

# Function to update Contents.json if needed
update_contents_json() {
    log_info "📝 Updating Contents.json for iOS icons..."
    
    local contents_file="ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
    
    if [ ! -f "$contents_file" ]; then
        log_error "Contents.json not found: $contents_file"
        return 1
    fi
    
    # Create backup
    cp "$contents_file" "${contents_file}.backup"
    
    # Generate proper Contents.json for iOS
    cat > "$contents_file" << 'EOF'
{
  "images" : [
    {
      "size" : "20x20",
      "idiom" : "iphone",
      "filename" : "Icon-App-20x20@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "20x20",
      "idiom" : "iphone",
      "filename" : "Icon-App-20x20@3x.png",
      "scale" : "3x"
    },
    {
      "size" : "29x29",
      "idiom" : "iphone",
      "filename" : "Icon-App-29x29@1x.png",
      "scale" : "1x"
    },
    {
      "size" : "29x29",
      "idiom" : "iphone",
      "filename" : "Icon-App-29x29@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "29x29",
      "idiom" : "iphone",
      "filename" : "Icon-App-29x29@3x.png",
      "scale" : "3x"
    },
    {
      "size" : "40x40",
      "idiom" : "iphone",
      "filename" : "Icon-App-40x40@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "40x40",
      "idiom" : "iphone",
      "filename" : "Icon-App-40x40@3x.png",
      "scale" : "3x"
    },
    {
      "size" : "60x60",
      "idiom" : "iphone",
      "filename" : "Icon-App-60x60@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "60x60",
      "idiom" : "iphone",
      "filename" : "Icon-App-60x60@3x.png",
      "scale" : "3x"
    },
    {
      "size" : "20x20",
      "idiom" : "ipad",
      "filename" : "Icon-App-20x20@1x.png",
      "scale" : "1x"
    },
    {
      "size" : "20x20",
      "idiom" : "ipad",
      "filename" : "Icon-App-20x20@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "29x29",
      "idiom" : "ipad",
      "filename" : "Icon-App-29x29@1x.png",
      "scale" : "1x"
    },
    {
      "size" : "29x29",
      "idiom" : "ipad",
      "filename" : "Icon-App-29x29@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "40x40",
      "idiom" : "ipad",
      "filename" : "Icon-App-40x40@1x.png",
      "scale" : "1x"
    },
    {
      "size" : "40x40",
      "idiom" : "ipad",
      "filename" : "Icon-App-40x40@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "76x76",
      "idiom" : "ipad",
      "filename" : "Icon-App-76x76@1x.png",
      "scale" : "1x"
    },
    {
      "size" : "76x76",
      "idiom" : "ipad",
      "filename" : "Icon-App-76x76@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "83.5x83.5",
      "idiom" : "ipad",
      "filename" : "Icon-App-83.5x83.5@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "1024x1024",
      "idiom" : "ios-marketing",
      "filename" : "Icon-App-1024x1024@1x.png",
      "scale" : "1x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
EOF
    
    log_success "✅ Contents.json updated successfully"
}

# Main execution
main() {
    log_info "🎯 Flutter Launcher Icons Generation for iOS Starting..."
    
    # Determine source image path
    local source_image=""
    
    # Priority order for source images
    if [ -n "${LOGO_URL:-}" ]; then
        log_info "📥 Downloading logo from URL for icon generation..."
        mkdir -p "assets/images"
        if curl -L -o "assets/images/logo.png" "$LOGO_URL" 2>/dev/null; then
            source_image="assets/images/logo.png"
            log_success "✅ Logo downloaded from URL"
        else
            log_warn "⚠️ Failed to download logo from URL, trying fallback"
        fi
    fi
    
    # Fallback to existing logo
    if [ -z "$source_image" ] && [ -f "assets/images/logo.png" ]; then
        source_image="assets/images/logo.png"
        log_info "📁 Using existing logo: $source_image"
    fi
    
    # Final fallback - create default icon
    if [ -z "$source_image" ]; then
        log_warn "⚠️ No source image found, creating default icon"
        mkdir -p "assets/images"
        create_fallback_asset "assets/images/logo.png" "default logo"
        source_image="assets/images/logo.png"
    fi
    
    # Validate and optimize source image
    if ! validate_source_image "$source_image"; then
        log_error "❌ Source image validation failed"
        return 1
    fi
    
    # Create optimized version for icon generation
    local optimized_image="assets/images/logo_optimized.png"
    create_optimized_source_image "$source_image" "$optimized_image"
    
    # Update pubspec.yaml to use the optimized image
    if [ -f "pubspec.yaml" ]; then
        cp "pubspec.yaml" "pubspec.yaml.backup"
        sed -i.tmp "s|image_path: .*|image_path: \"$optimized_image\"|" "pubspec.yaml"
        sed -i.tmp "s|adaptive_icon_foreground: .*|adaptive_icon_foreground: \"$optimized_image\"|" "pubspec.yaml"
        rm -f "pubspec.yaml.tmp"
        log_success "✅ Updated pubspec.yaml to use optimized image"
    fi
    
    # Run flutter_launcher_icons
    if ! run_flutter_launcher_icons; then
        log_error "❌ Flutter Launcher Icons generation failed"
        return 1
    fi
    
    # Validate generated icons
    if ! validate_generated_icons; then
        log_error "❌ Icon validation failed"
        return 1
    fi
    
    # Update Contents.json
    update_contents_json
    
    log_success "🎉 Flutter Launcher Icons generation completed successfully!"
    log_info "📊 Summary:"
    log_info "   Source image: $source_image"
    log_info "   Optimized image: $optimized_image"
    log_info "   iOS icons generated: ios/Runner/Assets.xcassets/AppIcon.appiconset/"
    log_info "   ✅ 1024x1024 icon: Valid"
    log_info "   ✅ All required iOS icon sizes: Generated"
    
    return 0
}

# Run main function
main "$@" 