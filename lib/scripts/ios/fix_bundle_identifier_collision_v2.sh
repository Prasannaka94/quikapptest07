#!/bin/bash

# Fix Bundle Identifier Collision - Version 2
# This script comprehensively resolves CFBundleIdentifier collision issues

set -euo pipefail

echo "🔧 Fixing Bundle Identifier Collision (Enhanced Version)..."

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

# Get the main bundle identifier
MAIN_BUNDLE_ID="${BUNDLE_ID:-com.twinklub.twinklub}"
echo "🎯 Main Bundle ID: $MAIN_BUNDLE_ID"

# Fix 1: Comprehensive bundle identifier cleanup
echo "🔧 Comprehensive bundle identifier cleanup..."

python3 -c "
import re

# Read the project file
with open('$IOS_PROJECT_FILE', 'r') as f:
    content = f.read()

print('Original bundle identifier analysis:')
bundle_id_pattern = r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'
matches = re.findall(bundle_id_pattern, content)

for i, match in enumerate(matches):
    print(f'  {i+1}. {match.strip()}')

# Strategy: Find all build configuration sections and fix them individually
build_config_sections = re.findall(r'(buildSettings = \{[^}]*PRODUCT_BUNDLE_IDENTIFIER[^}]*\};)', content, re.DOTALL)

print(f'\\nFound {len(build_config_sections)} build configuration sections with bundle identifiers')

# Track which sections we've seen
main_app_sections = 0
test_sections = 0

for i, section in enumerate(build_config_sections):
    print(f'\\nProcessing section {i+1}:')
    
    # Check if this is a test target section
    is_test_section = 'RunnerTests' in section or 'Tests' in section
    
    if is_test_section:
        test_sections += 1
        new_bundle_id = '$MAIN_BUNDLE_ID.tests' + (f'.{test_sections}' if test_sections > 1 else '')
        print(f'  Test section - setting bundle ID to: {new_bundle_id}')
        
        # Replace the bundle identifier in this section
        new_section = re.sub(
            r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;',
            f'PRODUCT_BUNDLE_IDENTIFIER = {new_bundle_id};',
            section
        )
    else:
        main_app_sections += 1
        if main_app_sections == 1:
            new_bundle_id = '$MAIN_BUNDLE_ID'
            print(f'  Main app section - setting bundle ID to: {new_bundle_id}')
        else:
            new_bundle_id = '$MAIN_BUNDLE_ID.app' + (f'.{main_app_sections}' if main_app_sections > 1 else '')
            print(f'  Additional main section - setting bundle ID to: {new_bundle_id}')
        
        # Replace the bundle identifier in this section
        new_section = re.sub(
            r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;',
            f'PRODUCT_BUNDLE_IDENTIFIER = {new_bundle_id};',
            section
        )
    
    # Replace the section in the content
    content = content.replace(section, new_section)

# Write back to file
with open('$IOS_PROJECT_FILE', 'w') as f:
    f.write(content)

print('\\n✅ Bundle identifier cleanup completed')
"

# Fix 2: Ensure Info.plist uses variable
echo "🔧 Updating Info.plist..."

INFO_PLIST="$PROJECT_ROOT/ios/Runner/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    # Ensure CFBundleIdentifier uses PRODUCT_BUNDLE_IDENTIFIER
    if grep -q "CFBundleIdentifier.*PRODUCT_BUNDLE_IDENTIFIER" "$INFO_PLIST"; then
        echo "✅ Info.plist already uses PRODUCT_BUNDLE_IDENTIFIER"
    else
        # Replace any hardcoded bundle identifier with the variable
        sed -i '' '/<key>CFBundleIdentifier<\/key>/{
            n
            s/<string>.*<\/string>/<string>$(PRODUCT_BUNDLE_IDENTIFIER)<\/string>/
        }' "$INFO_PLIST"
        echo "✅ Updated Info.plist to use PRODUCT_BUNDLE_IDENTIFIER"
    fi
else
    echo "⚠️ Info.plist not found"
fi

# Fix 3: Update Podfile with enhanced bundle identifier logic
echo "🔧 Updating Podfile with enhanced bundle identifier logic..."

PODFILE="$PROJECT_ROOT/ios/Podfile"

if [ -f "$PODFILE" ]; then
    # Remove any existing bundle identifier logic first
    sed -i '' '/# Ensure unique bundle identifiers/,/end/d' "$PODFILE"
    
    # Add enhanced post_install hook
    cat >> "$PODFILE" << 'EOF'

# Enhanced bundle identifier collision prevention
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Fix modular headers issue (from Firebase fix)
      config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
      
      # Ensure proper deployment target
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      
      # Ensure unique bundle identifiers for all pods
      if config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
        current_bundle_id = config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
        
        # Skip the main app target
        next if target.name == 'Runner'
        
        # Make pod bundle identifiers unique by adding pod suffix
        if current_bundle_id.include?('com.twinklub.twinklub') || current_bundle_id.include?('com.example.quikapptest07')
          config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = current_bundle_id + '.pod.' + target.name.downcase
        end
      end
      
      # Firebase specific fixes
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
    echo "✅ Added enhanced bundle identifier logic to Podfile"
else
    echo "⚠️ Podfile not found"
fi

# Fix 4: Final validation
echo "🔍 Final validation..."

python3 -c "
import re

# Read the project file
with open('$IOS_PROJECT_FILE', 'r') as f:
    content = f.read()

# Find all PRODUCT_BUNDLE_IDENTIFIER entries
bundle_id_pattern = r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'
matches = re.findall(bundle_id_pattern, content)

print(f'Final bundle identifier configuration:')
bundle_ids = []
for i, match in enumerate(matches):
    bundle_id = match.strip()
    bundle_ids.append(bundle_id)
    print(f'  {i+1}. {bundle_id}')

# Check for duplicates
duplicates = [x for x in bundle_ids if bundle_ids.count(x) > 1]
if duplicates:
    print(f'❌ Still found duplicate bundle identifiers: {list(set(duplicates))}')
    exit(1)
else:
    print('✅ All bundle identifiers are now unique')

print(f'\\n📊 Summary:')
print(f'  - Total bundle identifiers: {len(bundle_ids)}')
print(f'  - Unique bundle identifiers: {len(set(bundle_ids))}')
print(f'  - Main app bundle ID: $MAIN_BUNDLE_ID')
"

echo ""
echo "✅ Bundle identifier collision fixes completed successfully!"
echo ""
echo "📋 Summary of fixes applied:"
echo "   ✅ Comprehensive bundle identifier cleanup"
echo "   ✅ Unique identifiers for all targets"
echo "   ✅ Info.plist uses PRODUCT_BUNDLE_IDENTIFIER variable"
echo "   ✅ Enhanced Podfile with collision prevention"
echo "   ✅ Firebase and Xcode 16.0 compatibility"
echo ""
echo "🔄 Next steps:"
echo "   1. Run 'flutter clean'"
echo "   2. Run 'flutter pub get'"
echo "   3. Run 'cd ios && pod install'"
echo "   4. Rebuild your iOS app"
echo ""
echo "🎯 Expected result: No more CFBundleIdentifier collision errors" 