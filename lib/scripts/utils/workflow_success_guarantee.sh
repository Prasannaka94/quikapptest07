#!/bin/bash

# Workflow Success Guarantee Script
# This script ensures all workflows successfully produce their expected artifacts

set -euo pipefail

echo "🎯 Workflow Success Guarantee System"

# Get current workflow ID
WORKFLOW_ID="${WORKFLOW_ID:-unknown}"
echo "🔍 Current workflow: $WORKFLOW_ID"

# Function to ensure Android build success
ensure_android_success() {
    echo "📱 Ensuring Android build success..."
    
    # Create output directory
    mkdir -p output/android
    
    # Validate APK creation
    if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
        APK_SIZE=$(du -h build/app/outputs/flutter-apk/app-release.apk | cut -f1)
        echo "✅ APK found: build/app/outputs/flutter-apk/app-release.apk ($APK_SIZE)"
        
        # Copy to output directory for consistent artifact location
        cp build/app/outputs/flutter-apk/app-release.apk output/android/app-release.apk
        echo "✅ APK copied to output/android/app-release.apk"
    else
        echo "❌ APK not found at expected location"
        echo "🔍 Searching for APK in alternative locations..."
        
        # Search for APK in alternative locations
        find . -name "*.apk" -type f 2>/dev/null | head -5 | while read apk_file; do
            echo "   Found APK: $apk_file"
        done
        
        return 1
    fi
    
    # Validate AAB creation (for publish workflows)
    if [ "$WORKFLOW_ID" = "android-publish" ] || [ "$WORKFLOW_ID" = "combined" ]; then
        if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
            AAB_SIZE=$(du -h build/app/outputs/bundle/release/app-release.aab | cut -f1)
            echo "✅ AAB found: build/app/outputs/bundle/release/app-release.aab ($AAB_SIZE)"
            
            # Copy to output directory
            cp build/app/outputs/bundle/release/app-release.aab output/android/app-release.aab
            echo "✅ AAB copied to output/android/app-release.aab"
        else
            echo "❌ AAB not found at expected location"
            echo "🔍 Searching for AAB in alternative locations..."
            
            # Search for AAB in alternative locations
            find . -name "*.aab" -type f 2>/dev/null | head -5 | while read aab_file; do
                echo "   Found AAB: $aab_file"
            done
            
            return 1
        fi
    fi
    
    echo "✅ Android build success validated"
    return 0
}

# Function to ensure iOS build success
ensure_ios_success() {
    echo "🍎 Ensuring iOS build success..."
    
    # Create output directory
    mkdir -p output/ios
    
    # Check for IPA in multiple possible locations
    IPA_FOUND=false
    
    # Primary location: output/ios/Runner.ipa
    if [ -f "output/ios/Runner.ipa" ]; then
        IPA_SIZE=$(du -h output/ios/Runner.ipa | cut -f1)
        echo "✅ IPA found: output/ios/Runner.ipa ($IPA_SIZE)"
        IPA_FOUND=true
        
    # Secondary location: build/ios/ipa/Runner.ipa
    elif [ -f "build/ios/ipa/Runner.ipa" ]; then
        IPA_SIZE=$(du -h build/ios/ipa/Runner.ipa | cut -f1)
        echo "✅ IPA found: build/ios/ipa/Runner.ipa ($IPA_SIZE)"
        
        # Copy to standard output location
        cp build/ios/ipa/Runner.ipa output/ios/Runner.ipa
        echo "✅ IPA copied to output/ios/Runner.ipa"
        IPA_FOUND=true
        
    # Tertiary location: ios/build/Runner.ipa
    elif [ -f "ios/build/Runner.ipa" ]; then
        IPA_SIZE=$(du -h ios/build/Runner.ipa | cut -f1)
        echo "✅ IPA found: ios/build/Runner.ipa ($IPA_SIZE)"
        
        # Copy to standard output location
        cp ios/build/Runner.ipa output/ios/Runner.ipa
        echo "✅ IPA copied to output/ios/Runner.ipa"
        IPA_FOUND=true
        
    # Search for any IPA files
    else
        echo "🔍 Searching for IPA files in project..."
        IPA_FILES=$(find . -name "*.ipa" -type f 2>/dev/null | head -5)
        
        if [ -n "$IPA_FILES" ]; then
            echo "📱 Found IPA files:"
            echo "$IPA_FILES" | while read ipa_file; do
                echo "   $ipa_file"
            done
            
            # Use the first found IPA
            FIRST_IPA=$(echo "$IPA_FILES" | head -1)
            if [ -f "$FIRST_IPA" ]; then
                IPA_SIZE=$(du -h "$FIRST_IPA" | cut -f1)
                echo "✅ Using IPA: $FIRST_IPA ($IPA_SIZE)"
                
                # Copy to standard output location
                cp "$FIRST_IPA" output/ios/Runner.ipa
                echo "✅ IPA copied to output/ios/Runner.ipa"
                IPA_FOUND=true
            fi
        fi
    fi
    
    # Check for archive if IPA not found
    if [ "$IPA_FOUND" = false ]; then
        echo "❌ No IPA found, checking for archive..."
        
        if [ -d "output/ios/Runner.xcarchive" ]; then
            ARCHIVE_SIZE=$(du -h output/ios/Runner.xcarchive | cut -f1)
            echo "⚠️ Archive found: output/ios/Runner.xcarchive ($ARCHIVE_SIZE)"
            echo "📋 Archive can be manually exported to IPA"
            
            # Try to export IPA from archive
            echo "🚀 Attempting to export IPA from archive..."
            if [ -f "ios/ExportOptions.plist" ]; then
                echo "📋 ExportOptions.plist found, attempting export..."
                
                if xcodebuild -exportArchive \
                    -archivePath output/ios/Runner.xcarchive \
                    -exportPath output/ios/ \
                    -exportOptionsPlist ios/ExportOptions.plist \
                    -allowProvisioningUpdates 2>/dev/null; then
                    
                    echo "✅ IPA exported successfully from archive"
                    IPA_FOUND=true
                else
                    echo "⚠️ Archive export failed, but archive is available for manual export"
                fi
            else
                echo "⚠️ ExportOptions.plist not found, cannot auto-export from archive"
            fi
        else
            echo "❌ No archive found either"
            return 1
        fi
    fi
    
    if [ "$IPA_FOUND" = true ]; then
        echo "✅ iOS build success validated"
        return 0
    else
        echo "❌ iOS build validation failed"
        return 1
    fi
}

# Function to validate workflow success
validate_workflow_success() {
    local workflow="$1"
    echo "🔍 Validating success for workflow: $workflow"
    
    case "$workflow" in
        "android-free"|"android-paid")
            echo "📱 Validating Android APK workflow..."
            if [ -f "output/android/app-release.apk" ] || [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
                echo "✅ APK artifact validated"
                return 0
            else
                echo "❌ APK artifact missing"
                return 1
            fi
            ;;
            
        "android-publish")
            echo "📱 Validating Android APK+AAB workflow..."
            local apk_ok=false
            local aab_ok=false
            
            if [ -f "output/android/app-release.apk" ] || [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
                echo "✅ APK artifact validated"
                apk_ok=true
            else
                echo "❌ APK artifact missing"
            fi
            
            if [ -f "output/android/app-release.aab" ] || [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
                echo "✅ AAB artifact validated"
                aab_ok=true
            else
                echo "❌ AAB artifact missing"
            fi
            
            if [ "$apk_ok" = true ] && [ "$aab_ok" = true ]; then
                return 0
            else
                return 1
            fi
            ;;
            
        "ios-workflow"|"auto-ios-workflow"|"ios-appstore"|"ios-workflow2")
            echo "🍎 Validating iOS IPA workflow..."
            if [ -f "output/ios/Runner.ipa" ] || [ -f "build/ios/ipa/Runner.ipa" ] || [ -f "ios/build/Runner.ipa" ]; then
                echo "✅ IPA artifact validated"
                return 0
            else
                echo "❌ IPA artifact missing"
                return 1
            fi
            ;;
            
        "combined")
            echo "🔄 Validating combined workflow..."
            local android_ok=false
            local ios_ok=false
            
            # Check Android artifacts
            if [ -f "output/android/app-release.apk" ] && [ -f "output/android/app-release.aab" ]; then
                echo "✅ Android artifacts validated"
                android_ok=true
            else
                echo "❌ Android artifacts missing"
            fi
            
            # Check iOS artifacts
            if [ -f "output/ios/Runner.ipa" ]; then
                echo "✅ iOS artifacts validated"
                ios_ok=true
            else
                echo "❌ iOS artifacts missing"
            fi
            
            if [ "$android_ok" = true ] && [ "$ios_ok" = true ]; then
                return 0
            else
                return 1
            fi
            ;;
            
        *)
            echo "⚠️ Unknown workflow: $workflow"
            return 0
            ;;
    esac
}

# Main execution
main() {
    echo "🚀 Starting workflow success guarantee..."
    
    # Apply workflow-specific success guarantees
    case "$WORKFLOW_ID" in
        "android-free"|"android-paid"|"android-publish")
            if ensure_android_success; then
                echo "✅ Android build success guaranteed"
            else
                echo "❌ Android build success could not be guaranteed"
                exit 1
            fi
            ;;
            
        "ios-workflow"|"auto-ios-workflow"|"ios-appstore"|"ios-workflow2")
            if ensure_ios_success; then
                echo "✅ iOS build success guaranteed"
            else
                echo "❌ iOS build success could not be guaranteed"
                exit 1
            fi
            ;;
            
        "combined")
            local android_success=false
            local ios_success=false
            
            if ensure_android_success; then
                echo "✅ Android component success guaranteed"
                android_success=true
            else
                echo "❌ Android component failed"
            fi
            
            if ensure_ios_success; then
                echo "✅ iOS component success guaranteed"
                ios_success=true
            else
                echo "❌ iOS component failed"
            fi
            
            if [ "$android_success" = true ] && [ "$ios_success" = true ]; then
                echo "✅ Combined build success guaranteed"
            else
                echo "❌ Combined build success could not be guaranteed"
                exit 1
            fi
            ;;
            
        *)
            echo "⚠️ Unknown workflow: $WORKFLOW_ID"
            echo "ℹ️ Performing generic validation..."
            
            # Generic validation - check for any build artifacts
            if find . -name "*.apk" -o -name "*.aab" -o -name "*.ipa" | grep -q .; then
                echo "✅ Build artifacts found"
            else
                echo "❌ No build artifacts found"
                exit 1
            fi
            ;;
    esac
    
    # Final validation
    if validate_workflow_success "$WORKFLOW_ID"; then
        echo "🎉 Workflow success guarantee completed!"
        echo "📦 All required artifacts are available"
        return 0
    else
        echo "❌ Workflow success validation failed"
        exit 1
    fi
}

# Execute main function
main "$@" 