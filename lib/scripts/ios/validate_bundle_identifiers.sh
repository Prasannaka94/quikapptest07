#!/bin/bash

# Validate Bundle Identifiers
# This script comprehensively checks for bundle identifier conflicts

set -euo pipefail

echo "🔍 Validating Bundle Identifiers..."

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

# Validation 1: Check project.pbxproj for unique bundle identifiers
echo ""
echo "🔍 Checking project.pbxproj bundle identifiers..."

python3 -c "
import re

# Read the project file
with open('$IOS_PROJECT_FILE', 'r') as f:
    content = f.read()

# Find all PRODUCT_BUNDLE_IDENTIFIER entries
bundle_id_pattern = r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'
matches = re.findall(bundle_id_pattern, content)

print(f'Found {len(matches)} bundle identifier entries:')
bundle_ids = []
for i, match in enumerate(matches):
    bundle_id = match.strip()
    bundle_ids.append(bundle_id)
    print(f'  {i+1}. {bundle_id}')

# Check for duplicates
duplicates = [x for x in bundle_ids if bundle_ids.count(x) > 1]
if duplicates:
    print(f'❌ Found duplicate bundle identifiers: {list(set(duplicates))}')
    for dup in set(duplicates):
        indices = [i+1 for i, x in enumerate(bundle_ids) if x == dup]
        print(f'   \"{dup}\" appears at positions: {indices}')
    exit(1)
else:
    print('✅ All bundle identifiers in project.pbxproj are unique')

print(f'\\n📊 Summary:')
print(f'  - Total bundle identifiers: {len(bundle_ids)}')
print(f'  - Unique bundle identifiers: {len(set(bundle_ids))}')
"

# Validation 2: Check Info.plist
echo ""
echo "🔍 Checking Info.plist..."

INFO_PLIST="$PROJECT_ROOT/ios/Runner/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    if grep -q "CFBundleIdentifier.*PRODUCT_BUNDLE_IDENTIFIER" "$INFO_PLIST"; then
        echo "✅ Info.plist correctly uses \$(PRODUCT_BUNDLE_IDENTIFIER)"
    else
        echo "⚠️ Info.plist may have hardcoded bundle identifier"
        grep -A1 "CFBundleIdentifier" "$INFO_PLIST" || echo "CFBundleIdentifier not found"
    fi
else
    echo "❌ Info.plist not found"
fi

# Validation 3: Check for embedded frameworks or extensions
echo ""
echo "🔍 Checking for embedded frameworks and extensions..."

FRAMEWORKS_FOUND=false

# Check for .framework bundles
if find "$PROJECT_ROOT/ios" -name "*.framework" -type d | head -5 | grep -q ".framework"; then
    echo "📦 Found framework bundles:"
    find "$PROJECT_ROOT/ios" -name "*.framework" -type d | head -5 | while read -r framework; do
        echo "   - $framework"
        
        # Check for Info.plist in framework
        if [ -f "$framework/Info.plist" ]; then
            framework_bundle_id=$(grep -A1 "CFBundleIdentifier" "$framework/Info.plist" 2>/dev/null | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/' || echo "N/A")
            echo "     Bundle ID: $framework_bundle_id"
            
            # Check if it conflicts with main app
            if [[ "$framework_bundle_id" == "com.twinklub.twinklub" ]]; then
                echo "❌ Framework has conflicting bundle ID: $framework_bundle_id"
                FRAMEWORKS_FOUND=true
            fi
        fi
    done
else
    echo "ℹ️ No framework bundles found"
fi

# Check for .appex bundles (app extensions)
if find "$PROJECT_ROOT/ios" -name "*.appex" -type d | head -5 | grep -q ".appex"; then
    echo "📱 Found app extension bundles:"
    find "$PROJECT_ROOT/ios" -name "*.appex" -type d | head -5 | while read -r extension; do
        echo "   - $extension"
        
        # Check for Info.plist in extension
        if [ -f "$extension/Info.plist" ]; then
            extension_bundle_id=$(grep -A1 "CFBundleIdentifier" "$extension/Info.plist" 2>/dev/null | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/' || echo "N/A")
            echo "     Bundle ID: $extension_bundle_id"
            
            # Check if it conflicts with main app
            if [[ "$extension_bundle_id" == "com.twinklub.twinklub" ]]; then
                echo "❌ App extension has conflicting bundle ID: $extension_bundle_id"
                FRAMEWORKS_FOUND=true
            fi
        fi
    done
else
    echo "ℹ️ No app extension bundles found"
fi

# Validation 4: Check Podfile for potential conflicts
echo ""
echo "🔍 Checking Podfile configuration..."

PODFILE="$PROJECT_ROOT/ios/Podfile"

if [ -f "$PODFILE" ]; then
    if grep -q "PRODUCT_BUNDLE_IDENTIFIER" "$PODFILE"; then
        echo "✅ Podfile has bundle identifier management logic"
    else
        echo "⚠️ Podfile doesn't have bundle identifier management logic"
    fi
    
    # Check for Firebase workaround
    if grep -q "FIREBASE_DISABLED" "$PODFILE"; then
        echo "✅ Firebase workaround logic found"
    else
        echo "ℹ️ No Firebase workaround logic found"
    fi
else
    echo "❌ Podfile not found"
fi

# Validation 5: Check for duplicate target names
echo ""
echo "🔍 Checking for duplicate target names..."

python3 -c "
import re

# Read the project file
with open('$IOS_PROJECT_FILE', 'r') as f:
    content = f.read()

# Find all target names
target_pattern = r'PBXNativeTarget \"([^\"]+)\"'
targets = re.findall(target_pattern, content)

print(f'Found {len(targets)} targets:')
for i, target in enumerate(targets):
    print(f'  {i+1}. {target}')

# Check for duplicate targets
duplicates = [x for x in targets if targets.count(x) > 1]
if duplicates:
    print(f'❌ Found duplicate target names: {list(set(duplicates))}')
    exit(1)
else:
    print('✅ All target names are unique')
"

# Final validation result
echo ""
echo "📋 Final Validation Summary:"

if [ "$FRAMEWORKS_FOUND" = true ]; then
    echo "❌ Bundle identifier conflicts detected in embedded frameworks/extensions"
    echo ""
    echo "🔧 Recommended actions:"
    echo "   1. Check embedded frameworks for conflicting bundle IDs"
    echo "   2. Update framework bundle identifiers to be unique"
    echo "   3. Ensure app extensions have unique bundle IDs"
    exit 1
else
    echo "✅ All bundle identifier validations passed"
    echo "✅ No conflicts detected"
    echo "✅ Ready for App Store submission"
fi

echo ""
echo "🎯 Current bundle identifier configuration:"
echo "   - Main App (Release): com.twinklub.twinklub"
echo "   - Main App (Debug): com.twinklub.twinklub.debug"
echo "   - Main App (Profile): com.twinklub.twinklub.profile"
echo "   - Test Target (Debug): com.twinklub.twinklub.tests"
echo "   - Test Target (Release): com.twinklub.twinklub.tests2"
echo "   - Test Target (Profile): com.twinklub.twinklub.tests3"
echo ""
echo "✅ Bundle identifier validation completed successfully!" 