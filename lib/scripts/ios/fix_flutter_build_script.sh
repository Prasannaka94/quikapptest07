#!/bin/bash

# Fix Flutter Build Script Issue
# This script fixes the Flutter build script that's causing Xcode archive failures

set -euo pipefail

echo "🔧 Fixing Flutter Build Script Issues..."

# Get project root
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
echo "📁 Project root: $PROJECT_ROOT"

# Define paths
PBXPROJ_FILE="$PROJECT_ROOT/ios/Runner.xcodeproj/project.pbxproj"
BACKUP_FILE="$PROJECT_ROOT/ios/Runner.xcodeproj/project.pbxproj.backup.flutter_fix.$(date +%Y%m%d_%H%M%S)"

# Check if project file exists
if [ ! -f "$PBXPROJ_FILE" ]; then
    echo "❌ iOS project file not found: $PBXPROJ_FILE"
    exit 1
fi

# Create backup
echo "📋 Creating backup..."
cp "$PBXPROJ_FILE" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"

# Function to fix Flutter environment variables
fix_flutter_environment() {
    echo "🔧 Setting up Flutter environment..."
    
    # Ensure FLUTTER_ROOT is set
    if [ -z "${FLUTTER_ROOT:-}" ]; then
        # Try to find Flutter installation
        if command -v flutter >/dev/null 2>&1; then
            FLUTTER_BIN=$(which flutter)
            export FLUTTER_ROOT=$(dirname $(dirname "$FLUTTER_BIN"))
            echo "✅ Found Flutter at: $FLUTTER_ROOT"
        else
            echo "❌ Flutter not found in PATH"
            return 1
        fi
    else
        echo "✅ FLUTTER_ROOT already set: $FLUTTER_ROOT"
    fi
    
    # Verify Flutter tools exist
    if [ ! -f "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" ]; then
        echo "❌ Flutter xcode_backend.sh not found at: $FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh"
        return 1
    fi
    
    echo "✅ Flutter tools validated"
    return 0
}

# Function to update Flutter build script in project file
fix_flutter_build_script() {
    echo "🔧 Fixing Flutter build script in project file..."
    
    # Find the problematic script section (9740EEB61CF901F6004384FC)
    if grep -q "9740EEB61CF901F6004384FC" "$PBXPROJ_FILE"; then
        echo "✅ Found Flutter build script section"
        
        # Update the script to be more robust
        sed -i.tmp '
        /9740EEB61CF901F6004384FC.*Run Script/,/};/ {
            /shellScript = / {
                s|shellScript = .*|shellScript = "set -e\\nif [ \\\"\\${FLUTTER_ROOT}\\\" = \\\"\\\" ]; then\\n  export FLUTTER_ROOT=\\\"$(dirname $(dirname $(which flutter)))\\\"\\nfi\\nif [ ! -f \\\"\\${FLUTTER_ROOT}/packages/flutter_tools/bin/xcode_backend.sh\\\" ]; then\\n  echo \\\"Error: Flutter tools not found\\\"\\n  exit 1\\nfi\\n/bin/sh \\\"\\${FLUTTER_ROOT}/packages/flutter_tools/bin/xcode_backend.sh\\\" build";|
            }
        }' "$PBXPROJ_FILE"
        
        # Clean up temp file
        rm -f "$PBXPROJ_FILE.tmp"
        
        echo "✅ Flutter build script updated with robust error handling"
    else
        echo "⚠️ Flutter build script section not found"
    fi
}

# Function to add Flutter environment to build settings
add_flutter_build_settings() {
    echo "🔧 Adding Flutter build settings..."
    
    # Add FLUTTER_ROOT to build settings if not present
    if ! grep -q "FLUTTER_ROOT" "$PBXPROJ_FILE"; then
        # Find build configuration sections and add FLUTTER_ROOT
        sed -i.tmp '/buildSettings = {/,/};/ {
            /buildSettings = {/a\
				FLUTTER_ROOT = "$(dirname $(dirname $(which flutter)))";
        }' "$PBXPROJ_FILE"
        
        rm -f "$PBXPROJ_FILE.tmp"
        echo "✅ Added FLUTTER_ROOT to build settings"
    else
        echo "✅ FLUTTER_ROOT already in build settings"
    fi
}

# Function to validate project file syntax
validate_project_file() {
    echo "🔍 Validating project file syntax..."
    
    # Check for basic syntax issues
    if ! plutil -lint "$PBXPROJ_FILE" >/dev/null 2>&1; then
        echo "❌ Project file has syntax errors"
        echo "🔄 Restoring backup..."
        cp "$BACKUP_FILE" "$PBXPROJ_FILE"
        return 1
    fi
    
    echo "✅ Project file syntax is valid"
    return 0
}

# Function to create fallback build script
create_fallback_build_script() {
    echo "🔧 Creating fallback build script..."
    
    local script_path="$PROJECT_ROOT/ios/flutter_build_fallback.sh"
    
    cat > "$script_path" << 'EOF'
#!/bin/bash

# Fallback Flutter Build Script
# This script provides a fallback for Flutter builds when the main script fails

set -e

echo "🚀 Running fallback Flutter build..."

# Find Flutter installation
if [ -z "${FLUTTER_ROOT:-}" ]; then
    if command -v flutter >/dev/null 2>&1; then
        FLUTTER_BIN=$(which flutter)
        export FLUTTER_ROOT=$(dirname $(dirname "$FLUTTER_BIN"))
        echo "✅ Found Flutter at: $FLUTTER_ROOT"
    else
        echo "❌ Flutter not found"
        exit 1
    fi
fi

# Verify Flutter tools
if [ ! -f "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" ]; then
    echo "❌ Flutter xcode_backend.sh not found"
    exit 1
fi

# Run Flutter build
echo "🏗️ Running Flutter build..."
/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" build

echo "✅ Fallback Flutter build completed"
EOF

    chmod +x "$script_path"
    echo "✅ Fallback build script created: $script_path"
}

# Function to update build script to use fallback
use_fallback_script() {
    echo "🔧 Updating build script to use fallback..."
    
    local fallback_script="ios/flutter_build_fallback.sh"
    
    # Update the Flutter build script to use the fallback
    sed -i.tmp '
    /9740EEB61CF901F6004384FC.*Run Script/,/};/ {
        /shellScript = / {
            s|shellScript = .*|shellScript = "set -e\\nif [ -f \\\"'"$fallback_script"'\\\" ]; then\\n  /bin/sh \\\"'"$fallback_script"'\\\"\\nelse\\n  if [ \\\"\\${FLUTTER_ROOT}\\\" = \\\"\\\" ]; then\\n    export FLUTTER_ROOT=\\\"$(dirname $(dirname $(which flutter)))\\\"\\n  fi\\n  /bin/sh \\\"\\${FLUTTER_ROOT}/packages/flutter_tools/bin/xcode_backend.sh\\\" build\\nfi";|
        }
    }' "$PBXPROJ_FILE"
    
    rm -f "$PBXPROJ_FILE.tmp"
    echo "✅ Build script updated to use fallback"
}

# Main execution
main() {
    echo "🚀 Starting Flutter build script fix..."
    
    # Fix Flutter environment
    if fix_flutter_environment; then
        echo "✅ Flutter environment is ready"
    else
        echo "⚠️ Flutter environment issues detected"
    fi
    
    # Create fallback script
    create_fallback_build_script
    
    # Fix the build script
    fix_flutter_build_script
    
    # Add build settings
    add_flutter_build_settings
    
    # Use fallback approach
    use_fallback_script
    
    # Validate the changes
    if validate_project_file; then
        echo "✅ Project file updated successfully"
    else
        echo "❌ Project file validation failed"
        exit 1
    fi
    
    echo "🎉 Flutter build script fix completed!"
    echo "📋 Changes made:"
    echo "   ✅ Added robust error handling to Flutter build script"
    echo "   ✅ Created fallback build script"
    echo "   ✅ Added FLUTTER_ROOT to build settings"
    echo "   ✅ Validated project file syntax"
    
    return 0
}

# Execute main function
main "$@" 