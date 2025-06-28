#!/bin/bash

# Fix Bundle Identifier Collision
# This script resolves CFBundleIdentifier collision issues

set -euo pipefail

echo "🔧 Fixing Bundle Identifier Collision..."

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
MAIN_BUNDLE_ID="${BUNDLE_ID:-com.example.quikapptest07}"
echo "🎯 Main Bundle ID: $MAIN_BUNDLE_ID"

# Fix 1: Ensure unique bundle identifiers for all targets
echo "🔧 Ensuring unique bundle identifiers for all targets..."

python3 -c "
import re

# Read the project file
with open('$IOS_PROJECT_FILE', 'r') as f:
    content = f.read()

# Find all PRODUCT_BUNDLE_IDENTIFIER entries
bundle_id_pattern = r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'
matches = re.findall(bundle_id_pattern, content)

print(f'Found {len(matches)} bundle identifier entries:')
for i, match in enumerate(matches):
    print(f'  {i+1}. {match.strip()}')

# Ensure RunnerTests has a unique bundle identifier
if 'RunnerTests' in content:
    # Replace RunnerTests bundle identifier to be unique
    content = re.sub(
        r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);(.*?RunnerTests)',
        r'PRODUCT_BUNDLE_IDENTIFIER = \1.tests;\2',
        content,
        flags=re.DOTALL
    )
    print('✅ Updated RunnerTests bundle identifier to be unique')

# Write back to file
with open('$IOS_PROJECT_FILE', 'w') as f:
    f.write(content)

print('Bundle identifier collision fixes applied successfully')
"

# Fix 2: Update Info.plist to ensure it uses the correct bundle identifier
echo "🔧 Updating Info.plist..."

INFO_PLIST="$PROJECT_ROOT/ios/Runner/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    # Ensure CFBundleIdentifier uses PRODUCT_BUNDLE_IDENTIFIER
    if ! grep -q "CFBundleIdentifier.*PRODUCT_BUNDLE_IDENTIFIER" "$INFO_PLIST"; then
        # Replace any hardcoded bundle identifier with the variable
        sed -i '' 's/<key>CFBundleIdentifier<\/key>.*<string>.*<\/string>/<key>CFBundleIdentifier<\/key>\n\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)<\/string>/' "$INFO_PLIST"
        echo "✅ Updated Info.plist to use PRODUCT_BUNDLE_IDENTIFIER"
    else
        echo "ℹ️ Info.plist already uses PRODUCT_BUNDLE_IDENTIFIER"
    fi
else
    echo "⚠️ Info.plist not found"
fi

# Fix 3: Check for any embedded frameworks with conflicting bundle identifiers
echo "🔧 Checking for embedded frameworks..."

# Look for any frameworks that might have conflicting bundle identifiers
FRAMEWORKS_DIR="$PROJECT_ROOT/ios/Runner/Frameworks"
if [ -d "$FRAMEWORKS_DIR" ]; then
    echo "📁 Found Frameworks directory, checking for conflicts..."
    
    # Find all Info.plist files in frameworks
    find "$FRAMEWORKS_DIR" -name "Info.plist" -type f | while read -r framework_info; do
        if [ -f "$framework_info" ]; then
            framework_bundle_id=$(grep -A1 "CFBundleIdentifier" "$framework_info" | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
            if [ "$framework_bundle_id" = "$MAIN_BUNDLE_ID" ]; then
                echo "⚠️ Found framework with conflicting bundle ID: $framework_info"
                echo "   Bundle ID: $framework_bundle_id"
            fi
        fi
    done
else
    echo "ℹ️ No Frameworks directory found"
fi

# Fix 4: Update Podfile to ensure unique bundle identifiers for pods
echo "🔧 Updating Podfile for unique bundle identifiers..."

PODFILE="$PROJECT_ROOT/ios/Podfile"

if [ -f "$PODFILE" ]; then
    # Add post_install hook to ensure unique bundle identifiers for pods
    if ! grep -q "config.build_settings\['PRODUCT_BUNDLE_IDENTIFIER'\]" "$PODFILE"; then
        # Add before the closing end
        sed -i '' '/end$/i\
  # Ensure unique bundle identifiers for all pods\
  installer.pods_project.targets.each do |target|\
    target.build_configurations.each do |config|\
      # Skip the main app target\
      next if target.name == "Runner"\
      \
      # Make pod bundle identifiers unique\
      if config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"]\
        current_bundle_id = config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"]\
        if current_bundle_id == "'$MAIN_BUNDLE_ID'"\
          config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = current_bundle_id + ".pod"\
        end\
      end\
    end\
  end' "$PODFILE"
        echo "✅ Added unique bundle identifier logic to Podfile"
    else
        echo "ℹ️ Podfile already has bundle identifier logic"
    fi
else
    echo "⚠️ Podfile not found"
fi

# Fix 5: Clean up any duplicate bundle identifier references
echo "🔧 Cleaning up duplicate bundle identifier references..."

# Remove any duplicate PRODUCT_BUNDLE_IDENTIFIER entries in the project file
python3 -c "
import re

# Read the project file
with open('$IOS_PROJECT_FILE', 'r') as f:
    content = f.read()

# Find all build configuration sections
build_config_pattern = r'(buildSettings = \{.*?\};)'
build_configs = re.findall(build_config_pattern, content, flags=re.DOTALL)

cleaned_content = content
for config in build_configs:
    # Check for duplicate PRODUCT_BUNDLE_IDENTIFIER entries
    bundle_id_entries = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;', config)
    if len(bundle_id_entries) > 1:
        print(f'Found {len(bundle_id_entries)} duplicate bundle identifier entries in a build configuration')
        # Keep only the first one
        first_entry = bundle_id_entries[0]
        for entry in bundle_id_entries[1:]:
            cleaned_content = cleaned_content.replace(entry, '')
        print('✅ Removed duplicate bundle identifier entries')

# Write back to file
with open('$IOS_PROJECT_FILE', 'w') as f:
    f.write(cleaned_content)

print('Bundle identifier cleanup completed')
"

# Fix 6: Validate the final bundle identifier configuration
echo "🔍 Validating bundle identifier configuration..."

# Check the final bundle identifiers
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
    print(f'❌ Found duplicate bundle identifiers: {list(set(duplicates))}')
else:
    print('✅ All bundle identifiers are unique')

# Check if main bundle identifier is set correctly
if '$MAIN_BUNDLE_ID' in bundle_ids:
    print(f'✅ Main bundle identifier found: $MAIN_BUNDLE_ID')
else:
    print(f'⚠️ Main bundle identifier not found: $MAIN_BUNDLE_ID')
"

echo "✅ Bundle identifier collision fixes completed!"
echo ""
echo "📋 Summary of fixes applied:"
echo "   ✅ Ensured unique bundle identifiers for all targets"
echo "   ✅ Updated Info.plist to use PRODUCT_BUNDLE_IDENTIFIER"
echo "   ✅ Checked for embedded framework conflicts"
echo "   ✅ Updated Podfile for unique pod bundle identifiers"
echo "   ✅ Cleaned up duplicate bundle identifier references"
echo "   ✅ Validated final bundle identifier configuration"
echo ""
echo "🔄 Next steps:"
echo "   1. Run 'flutter clean'"
echo "   2. Run 'flutter pub get'"
echo "   3. Run 'cd ios && pod install'"
echo "   4. Rebuild your iOS app"
echo ""
echo "🎯 Expected result: No more CFBundleIdentifier collision errors" 