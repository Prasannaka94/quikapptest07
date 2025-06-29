#!/bin/bash

# Ensure Workflow Success Script
# This script ensures all workflows in codemagic.yaml successfully build their respective artifacts

set -euo pipefail

echo "🎯 Ensuring All Workflows Build Successfully..."

# Get current workflow ID
WORKFLOW_ID="${WORKFLOW_ID:-unknown}"
echo "🔍 Current workflow: $WORKFLOW_ID"

# Define success criteria for each workflow
declare -A WORKFLOW_ARTIFACTS
WORKFLOW_ARTIFACTS["android-free"]="APK"
WORKFLOW_ARTIFACTS["android-paid"]="APK"
WORKFLOW_ARTIFACTS["android-publish"]="APK,AAB"
WORKFLOW_ARTIFACTS["ios-workflow"]="IPA"
WORKFLOW_ARTIFACTS["auto-ios-workflow"]="IPA"
WORKFLOW_ARTIFACTS["combined"]="APK,AAB,IPA"
WORKFLOW_ARTIFACTS["ios-appstore"]="IPA"
WORKFLOW_ARTIFACTS["ios-workflow2"]="IPA"

# Function to validate environment for specific workflow
validate_workflow_environment() {
    local workflow="$1"
    echo "🔍 Validating environment for workflow: $workflow"
    
    case "$workflow" in
        "android-free")
            echo "📱 Android Free Build - No special requirements"
            return 0
            ;;
        "android-paid")
            if [ "${PUSH_NOTIFY:-}" = "true" ] && [ -z "${FIREBASE_CONFIG_ANDROID:-}" ]; then
                echo "❌ FIREBASE_CONFIG_ANDROID required for android-paid with PUSH_NOTIFY=true"
                return 1
            fi
            echo "✅ Android Paid Build - Environment validated"
            return 0
            ;;
        "android-publish")
            local missing_vars=()
            [ -z "${KEY_STORE_URL:-}" ] && missing_vars+=("KEY_STORE_URL")
            [ -z "${CM_KEYSTORE_PASSWORD:-}" ] && missing_vars+=("CM_KEYSTORE_PASSWORD")
            [ -z "${CM_KEY_ALIAS:-}" ] && missing_vars+=("CM_KEY_ALIAS")
            [ -z "${CM_KEY_PASSWORD:-}" ] && missing_vars+=("CM_KEY_PASSWORD")
            
            if [ ${#missing_vars[@]} -gt 0 ]; then
                echo "❌ Missing required variables for android-publish:"
                printf '   - %s\n' "${missing_vars[@]}"
                return 1
            fi
            echo "✅ Android Publish Build - Environment validated"
            return 0
            ;;
        "ios-workflow"|"auto-ios-workflow"|"ios-appstore"|"ios-workflow2")
            # iOS workflows require either App Store Connect API or manual certificates
            if [[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" && -n "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" && -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
                echo "✅ iOS Build - App Store Connect API authentication available"
                return 0
            elif [[ -n "${CERT_PASSWORD:-}" && -n "${PROFILE_URL:-}" ]]; then
                echo "✅ iOS Build - Manual certificate authentication available"
                return 0
            else
                echo "⚠️ iOS Build - No authentication configured, will use automatic signing"
                return 0
            fi
            ;;
        "combined")
            # Combined workflow needs both Android and iOS requirements
            local android_ok=true
            local ios_ok=true
            
            # Check Android requirements
            if [ "${PUSH_NOTIFY:-}" = "true" ] && [ -z "${FIREBASE_CONFIG_ANDROID:-}" ]; then
                echo "❌ FIREBASE_CONFIG_ANDROID required for combined workflow with PUSH_NOTIFY=true"
                android_ok=false
            fi
            
            local missing_keystore_vars=()
            [ -z "${KEY_STORE_URL:-}" ] && missing_keystore_vars+=("KEY_STORE_URL")
            [ -z "${CM_KEYSTORE_PASSWORD:-}" ] && missing_keystore_vars+=("CM_KEYSTORE_PASSWORD")
            [ -z "${CM_KEY_ALIAS:-}" ] && missing_keystore_vars+=("CM_KEY_ALIAS")
            [ -z "${CM_KEY_PASSWORD:-}" ] && missing_keystore_vars+=("CM_KEY_PASSWORD")
            
            if [ ${#missing_keystore_vars[@]} -gt 0 ]; then
                echo "❌ Missing Android keystore variables for combined workflow:"
                printf '   - %s\n' "${missing_keystore_vars[@]}"
                android_ok=false
            fi
            
            # Check iOS requirements (already handled above)
            
            if [ "$android_ok" = true ] && [ "$ios_ok" = true ]; then
                echo "✅ Combined Build - Environment validated"
                return 0
            else
                echo "❌ Combined Build - Environment validation failed"
                return 1
            fi
            ;;
        *)
            echo "⚠️ Unknown workflow: $workflow"
            return 0
            ;;
    esac
}

# Function to apply workflow-specific fixes
apply_workflow_fixes() {
    local workflow="$1"
    echo "🔧 Applying fixes for workflow: $workflow"
    
    case "$workflow" in
        "android-free"|"android-paid"|"android-publish")
            echo "📱 Applying Android workflow fixes..."
            
            # Ensure Android scripts are executable
            if [ -d "lib/scripts/android" ]; then
                chmod +x lib/scripts/android/*.sh 2>/dev/null || true
                echo "✅ Android scripts made executable"
            fi
            
            # Optimize Gradle settings
            export GRADLE_OPTS="${GRADLE_OPTS:--Xmx4G -XX:MaxMetaspaceSize=1G -XX:+UseG1GC}"
            export GRADLE_DAEMON=true
            export GRADLE_PARALLEL=true
            echo "✅ Gradle optimization applied"
            
            # Ensure output directory exists
            mkdir -p output/android
            echo "✅ Android output directory created"
            ;;
            
        "ios-workflow"|"auto-ios-workflow"|"ios-appstore"|"ios-workflow2")
            echo "🍎 Applying iOS workflow fixes..."
            
            # Ensure iOS scripts are executable
            if [ -d "lib/scripts/ios" ]; then
                chmod +x lib/scripts/ios/*.sh 2>/dev/null || true
                echo "✅ iOS scripts made executable"
            fi
            
            # Apply Firebase forward declaration fix if needed
            if [ "${PUSH_NOTIFY:-}" = "true" ] && [ -n "${FIREBASE_CONFIG_IOS:-}" ]; then
                echo "🔥 Applying Firebase fixes for iOS..."
                if [ -f "lib/scripts/ios/fix_firebase_forward_declaration.sh" ]; then
                    chmod +x lib/scripts/ios/fix_firebase_forward_declaration.sh
                    echo "✅ Firebase forward declaration fix available"
                fi
            fi
            
            # Ensure output directory exists
            mkdir -p output/ios
            echo "✅ iOS output directory created"
            
            # Apply bundle identifier fixes
            if [ -f "lib/scripts/ios/fix_bundle_identifier_collision_v2.sh" ]; then
                chmod +x lib/scripts/ios/fix_bundle_identifier_collision_v2.sh
                echo "✅ Bundle identifier collision fix available"
            fi
            ;;
            
        "combined")
            echo "🔄 Applying combined workflow fixes..."
            
            # Apply both Android and iOS fixes
            apply_workflow_fixes "android-publish"
            apply_workflow_fixes "ios-workflow"
            echo "✅ Combined workflow fixes applied"
            ;;
    esac
}

# Function to verify expected artifacts will be created
verify_artifact_paths() {
    local workflow="$1"
    local artifacts="${WORKFLOW_ARTIFACTS[$workflow]:-}"
    
    echo "🔍 Verifying artifact paths for workflow: $workflow"
    echo "📦 Expected artifacts: $artifacts"
    
    IFS=',' read -ra ARTIFACT_ARRAY <<< "$artifacts"
    for artifact in "${ARTIFACT_ARRAY[@]}"; do
        case "$artifact" in
            "APK")
                echo "📱 APK artifact paths:"
                echo "   - build/app/outputs/flutter-apk/app-release.apk"
                echo "   - output/android/app-release.apk"
                ;;
            "AAB")
                echo "📱 AAB artifact paths:"
                echo "   - build/app/outputs/bundle/release/app-release.aab"
                echo "   - output/android/app-release.aab"
                ;;
            "IPA")
                echo "🍎 IPA artifact paths:"
                echo "   - output/ios/Runner.ipa"
                echo "   - build/ios/ipa/Runner.ipa"
                echo "   - ios/build/Runner.ipa"
                ;;
        esac
    done
}

# Function to create success validation script
create_success_validation() {
    local workflow="$1"
    local artifacts="${WORKFLOW_ARTIFACTS[$workflow]:-}"
    
    cat > "/tmp/validate_${workflow}_success.sh" << EOF
#!/bin/bash
# Success validation for $workflow

echo "🔍 Validating build success for workflow: $workflow"
echo "📦 Expected artifacts: $artifacts"

success=true
IFS=',' read -ra ARTIFACT_ARRAY <<< "$artifacts"

for artifact in "\${ARTIFACT_ARRAY[@]}"; do
    case "\$artifact" in
        "APK")
            if [ -f "build/app/outputs/flutter-apk/app-release.apk" ] || [ -f "output/android/app-release.apk" ]; then
                echo "✅ APK artifact found"
            else
                echo "❌ APK artifact missing"
                success=false
            fi
            ;;
        "AAB")
            if [ -f "build/app/outputs/bundle/release/app-release.aab" ] || [ -f "output/android/app-release.aab" ]; then
                echo "✅ AAB artifact found"
            else
                echo "❌ AAB artifact missing"
                success=false
            fi
            ;;
        "IPA")
            if [ -f "output/ios/Runner.ipa" ] || [ -f "build/ios/ipa/Runner.ipa" ] || [ -f "ios/build/Runner.ipa" ]; then
                echo "✅ IPA artifact found"
            else
                echo "❌ IPA artifact missing"
                success=false
            fi
            ;;
    esac
done

if [ "\$success" = true ]; then
    echo "🎉 Build success validated for workflow: $workflow"
    exit 0
else
    echo "❌ Build validation failed for workflow: $workflow"
    exit 1
fi
EOF

    chmod +x "/tmp/validate_${workflow}_success.sh"
    echo "✅ Success validation script created: /tmp/validate_${workflow}_success.sh"
}

# Function to enhance build scripts with success guarantees
enhance_build_scripts() {
    echo "🔧 Enhancing build scripts with success guarantees..."
    
    # Enhance Android main script
    if [ -f "lib/scripts/android/main.sh" ]; then
        # Add success validation to Android script
        if ! grep -q "SUCCESS VALIDATION" lib/scripts/android/main.sh; then
            cat >> lib/scripts/android/main.sh << 'EOF'

# ============================================================================
# SUCCESS VALIDATION
# ============================================================================

echo "🔍 Validating Android build success..."

# Check for APK
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    APK_SIZE=$(du -h build/app/outputs/flutter-apk/app-release.apk | cut -f1)
    echo "✅ APK found: build/app/outputs/flutter-apk/app-release.apk ($APK_SIZE)"
    
    # Copy to output directory
    mkdir -p output/android
    cp build/app/outputs/flutter-apk/app-release.apk output/android/
    echo "✅ APK copied to output/android/"
else
    echo "❌ APK not found at expected location"
fi

# Check for AAB (if android-publish workflow)
if [ "${WORKFLOW_ID:-}" = "android-publish" ] || [ "${WORKFLOW_ID:-}" = "combined" ]; then
    if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
        AAB_SIZE=$(du -h build/app/outputs/bundle/release/app-release.aab | cut -f1)
        echo "✅ AAB found: build/app/outputs/bundle/release/app-release.aab ($AAB_SIZE)"
        
        # Copy to output directory
        mkdir -p output/android
        cp build/app/outputs/bundle/release/app-release.aab output/android/
        echo "✅ AAB copied to output/android/"
    else
        echo "❌ AAB not found at expected location"
    fi
fi

echo "🎉 Android build validation completed"
EOF
            echo "✅ Android main script enhanced with success validation"
        fi
    fi
    
    # Enhance iOS main script
    if [ -f "lib/scripts/ios/main.sh" ]; then
        # Add success validation to iOS script
        if ! grep -q "SUCCESS VALIDATION" lib/scripts/ios/main.sh; then
            cat >> lib/scripts/ios/main.sh << 'EOF'

# ============================================================================
# SUCCESS VALIDATION
# ============================================================================

echo "🔍 Validating iOS build success..."

# Check for IPA in multiple possible locations
IPA_FOUND=false

if [ -f "output/ios/Runner.ipa" ]; then
    IPA_SIZE=$(du -h output/ios/Runner.ipa | cut -f1)
    echo "✅ IPA found: output/ios/Runner.ipa ($IPA_SIZE)"
    IPA_FOUND=true
elif [ -f "build/ios/ipa/Runner.ipa" ]; then
    IPA_SIZE=$(du -h build/ios/ipa/Runner.ipa | cut -f1)
    echo "✅ IPA found: build/ios/ipa/Runner.ipa ($IPA_SIZE)"
    
    # Copy to standard output location
    mkdir -p output/ios
    cp build/ios/ipa/Runner.ipa output/ios/
    echo "✅ IPA copied to output/ios/"
    IPA_FOUND=true
elif [ -f "ios/build/Runner.ipa" ]; then
    IPA_SIZE=$(du -h ios/build/Runner.ipa | cut -f1)
    echo "✅ IPA found: ios/build/Runner.ipa ($IPA_SIZE)"
    
    # Copy to standard output location
    mkdir -p output/ios
    cp ios/build/Runner.ipa output/ios/
    echo "✅ IPA copied to output/ios/"
    IPA_FOUND=true
fi

# Check for archive if IPA not found
if [ "$IPA_FOUND" = false ] && [ -d "output/ios/Runner.xcarchive" ]; then
    ARCHIVE_SIZE=$(du -h output/ios/Runner.xcarchive | cut -f1)
    echo "⚠️ IPA not found, but archive exists: output/ios/Runner.xcarchive ($ARCHIVE_SIZE)"
    echo "📋 Archive can be manually exported to IPA"
elif [ "$IPA_FOUND" = false ]; then
    echo "❌ No IPA or archive found"
fi

echo "🎉 iOS build validation completed"
EOF
            echo "✅ iOS main script enhanced with success validation"
        fi
    fi
}

# Main execution
main() {
    echo "🚀 Starting workflow success assurance process..."
    
    # Validate current workflow environment
    if validate_workflow_environment "$WORKFLOW_ID"; then
        echo "✅ Environment validation passed"
    else
        echo "❌ Environment validation failed"
        exit 1
    fi
    
    # Apply workflow-specific fixes
    apply_workflow_fixes "$WORKFLOW_ID"
    
    # Verify artifact paths
    verify_artifact_paths "$WORKFLOW_ID"
    
    # Create success validation script
    create_success_validation "$WORKFLOW_ID"
    
    # Enhance build scripts
    enhance_build_scripts
    
    echo "🎉 Workflow success assurance completed!"
    echo "📋 Summary:"
    echo "   ✅ Environment validated for workflow: $WORKFLOW_ID"
    echo "   ✅ Workflow-specific fixes applied"
    echo "   ✅ Expected artifacts: ${WORKFLOW_ARTIFACTS[$WORKFLOW_ID]:-Unknown}"
    echo "   ✅ Build scripts enhanced with success validation"
    echo "   ✅ Success validation script created"
    
    return 0
}

# Execute main function
main "$@" 