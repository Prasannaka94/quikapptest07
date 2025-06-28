#!/bin/bash

# Fix Firebase compilation issues with Xcode 16.0
# This script addresses the non-modular header include error

set -euo pipefail

echo "🔧 Fixing Firebase compilation issues for Xcode 16.0..."

# Get project root
PROJECT_ROOT=$(pwd)
IOS_PROJECT_FILE="$PROJECT_ROOT/ios/Runner.xcodeproj/project.pbxproj"

# Check if project file exists
if [ ! -f "$IOS_PROJECT_FILE" ]; then
    echo "❌ iOS project file not found: $IOS_PROJECT_FILE"
    exit 1
fi

echo "📁 Project root: $PROJECT_ROOT"
echo "📱 iOS project file: $IOS_PROJECT_FILE"

# Create a backup
cp "$IOS_PROJECT_FILE" "$IOS_PROJECT_FILE.backup.$(date +%Y%m%d_%H%M%S)"

echo "✅ Backup created"

# Fix 1: Add modular headers configuration
echo "🔧 Adding modular headers configuration..."

# Add CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES
# This allows non-modular headers in framework modules (fixes Firebase issue)
sed -i '' '/CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;/a\
				CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES;' "$IOS_PROJECT_FILE"

# Fix 2: Add Firebase-specific build settings
echo "🔧 Adding Firebase-specific build settings..."

# Add Firebase build settings to all configurations
python3 -c "
import re

# Read the project file
with open('$IOS_PROJECT_FILE', 'r') as f:
    content = f.read()

# Add Firebase-specific settings to all build configurations
firebase_settings = '''
				CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES;
				OTHER_LDFLAGS = \"\$(inherited)\";
				FRAMEWORK_SEARCH_PATHS = \"\$(inherited)\";
				HEADER_SEARCH_PATHS = \"\$(inherited)\";
				LIBRARY_SEARCH_PATHS = \"\$(inherited)\";
				SWIFT_OBJC_BRIDGING_HEADER = \"Runner/Runner-Bridging-Header.h\";
				SWIFT_VERSION = 5.0;
				ENABLE_BITCODE = NO;
				IPHONEOS_DEPLOYMENT_TARGET = 13.0;
'''

# Find all build configuration sections and add Firebase settings
pattern = r'(buildSettings = \{.*?)(\};)'
replacement = r'\1' + firebase_settings + r'\2'

# Apply the replacement
modified_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

# Write back to file
with open('$IOS_PROJECT_FILE', 'w') as f:
    f.write(modified_content)

print('Firebase build settings added successfully')
"

# Fix 3: Update Podfile to handle Firebase properly
echo "🔧 Updating Podfile configuration..."

PODFILE="$PROJECT_ROOT/ios/Podfile"

if [ -f "$PODFILE" ]; then
    # Add post_install hook to fix Firebase issues
    if ! grep -q "post_install do |installer|" "$PODFILE"; then
        cat >> "$PODFILE" << 'EOF'

# Fix Firebase compilation issues with Xcode 16.0
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Fix modular headers issue
      config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
      
      # Ensure proper deployment target
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      
      # Fix Firebase specific issues
      if target.name.start_with?('Firebase') || target.name.start_with?('firebase')
        config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
        config.build_settings['DEFINES_MODULE'] = 'YES'
        config.build_settings['SWIFT_INSTALL_OBJC_HEADER'] = 'NO'
      end
      
      # Fix for Xcode 16.0
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      config.build_settings['SWIFT_VERSION'] = '5.0'
    end
  end
end
EOF
        echo "✅ Podfile post_install hook added"
    else
        echo "ℹ️ Podfile post_install hook already exists"
    fi
else
    echo "⚠️ Podfile not found, skipping Podfile updates"
fi

# Fix 4: Create Firebase configuration file if needed
echo "🔧 Checking Firebase configuration..."

FIREBASE_CONFIG="$PROJECT_ROOT/ios/Runner/GoogleService-Info.plist"

if [ ! -f "$FIREBASE_CONFIG" ]; then
    echo "⚠️ Firebase configuration file not found: $FIREBASE_CONFIG"
    echo "   Please ensure you have the correct GoogleService-Info.plist file"
else
    echo "✅ Firebase configuration file found"
fi

# Fix 5: Update Info.plist for Firebase
echo "🔧 Updating Info.plist for Firebase..."

INFO_PLIST="$PROJECT_ROOT/ios/Runner/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    # Add Firebase messaging configuration if not present
    if ! grep -q "FirebaseAppDelegateProxyEnabled" "$INFO_PLIST"; then
        # Add before the closing </dict>
        sed -i '' '/<\/dict>/i\
	<key>FirebaseAppDelegateProxyEnabled</key>\
	<false/>' "$INFO_PLIST"
        echo "✅ Firebase AppDelegate proxy disabled in Info.plist"
    fi
else
    echo "⚠️ Info.plist not found"
fi

echo "✅ Firebase Xcode 16.0 fixes completed!"
echo ""
echo "📋 Summary of fixes applied:"
echo "   ✅ Added CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES"
echo "   ✅ Updated build settings for Firebase compatibility"
echo "   ✅ Added Podfile post_install hook"
echo "   ✅ Updated Info.plist for Firebase"
echo "   ✅ Set proper deployment target (iOS 13.0+)"
echo ""
echo "🔄 Next steps:"
echo "   1. Run 'flutter clean'"
echo "   2. Run 'flutter pub get'"
echo "   3. Run 'cd ios && pod install'"
echo "   4. Rebuild your iOS app" 