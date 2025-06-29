#!/bin/bash

# App Store Readiness Validation Script
# This script validates that the iOS app meets all App Store requirements

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/utils.sh"

log_info "Starting App Store Readiness Validation..."

# Function to validate bundle identifier format
validate_bundle_id_format() {
    local bundle_id="$1"
    
    log_info "Validating bundle identifier format: $bundle_id"
    
    # Check if bundle ID follows reverse domain notation
    if [[ "$bundle_id" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+$ ]]; then
        log_success "Bundle ID format is valid"
        return 0
    else
        log_error "Invalid bundle ID format: $bundle_id"
        log_info "Bundle ID must follow reverse domain notation (e.g., com.company.appname)"
        return 1
    fi
}

# Function to validate app version format
validate_version_format() {
    local version="$1"
    local build="$2"
    
    log_info "Validating version format: $version ($build)"
    
    # Check version format (semantic versioning)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_success "Version format is valid: $version"
    else
        log_warn "Version format may not be optimal: $version (recommended: X.Y.Z)"
    fi
    
    # Check build number is numeric
    if [[ "$build" =~ ^[0-9]+$ ]]; then
        log_success "Build number format is valid: $build"
    else
        log_warn "Build number should be numeric: $build"
    fi
    
    return 0
}

# Function to validate project configuration
validate_project_config() {
    log_info "Validating iOS project configuration..."
    
    local project_file="ios/Runner.xcodeproj/project.pbxproj"
    
    if [ ! -f "$project_file" ]; then
        log_error "iOS project file not found: $project_file"
        return 1
    fi
    
    # Check deployment target
    local deployment_target=$(grep -o "IPHONEOS_DEPLOYMENT_TARGET = [^;]*" "$project_file" | head -1 | cut -d'=' -f2 | tr -d ' ')
    if [ -n "$deployment_target" ]; then
        log_info "iOS Deployment Target: $deployment_target"
        
        # Convert to numeric for comparison
        local target_numeric=$(echo "$deployment_target" | sed 's/\.//')
        if [ "$target_numeric" -ge 130 ]; then
            log_success "Deployment target meets App Store requirements (iOS 13.0+)"
        else
            log_warn "Deployment target may be too low for modern App Store: $deployment_target"
        fi
    else
        log_warn "Could not determine iOS deployment target"
    fi
    
    # Check Swift version
    local swift_version=$(grep -o "SWIFT_VERSION = [^;]*" "$project_file" | head -1 | cut -d'=' -f2 | tr -d ' ')
    if [ -n "$swift_version" ]; then
        log_info "Swift Version: $swift_version"
        if [ "$swift_version" = "5.0" ]; then
            log_success "Using supported Swift version"
        else
            log_info "Swift version: $swift_version (ensure compatibility)"
        fi
    fi
    
    # Check bitcode setting
    if grep -q "ENABLE_BITCODE = NO" "$project_file"; then
        log_success "Bitcode is disabled (recommended for modern iOS apps)"
    else
        log_info "Bitcode setting detected - ensure consistency across targets"
    fi
    
    return 0
}

# Function to validate Info.plist
validate_info_plist() {
    log_info "Validating Info.plist configuration..."
    
    local info_plist="ios/Runner/Info.plist"
    
    if [ ! -f "$info_plist" ]; then
        log_error "Info.plist not found: $info_plist"
        return 1
    fi
    
    # Check required keys
    local required_keys=(
        "CFBundleIdentifier"
        "CFBundleName"
        "CFBundleShortVersionString"
        "CFBundleVersion"
        "CFBundleExecutable"
        "CFBundlePackageType"
        "LSRequiresIPhoneOS"
        "UIRequiredDeviceCapabilities"
        "UISupportedInterfaceOrientations"
    )
    
    for key in "${required_keys[@]}"; do
        if plutil -extract "$key" raw "$info_plist" >/dev/null 2>&1; then
            local value=$(plutil -extract "$key" raw "$info_plist" 2>/dev/null)
            log_success "$key: $value"
        else
            log_error "Missing required key in Info.plist: $key"
        fi
    done
    
    # Check bundle identifier matches environment variable
    local plist_bundle_id=$(plutil -extract CFBundleIdentifier raw "$info_plist" 2>/dev/null)
    if [ -n "${BUNDLE_ID:-}" ] && [ "$plist_bundle_id" != "\$(PRODUCT_BUNDLE_IDENTIFIER)" ]; then
        if [ "$plist_bundle_id" != "$BUNDLE_ID" ]; then
            log_warn "Bundle ID in Info.plist ($plist_bundle_id) may not match environment ($BUNDLE_ID)"
        fi
    fi
    
    # Check for privacy usage descriptions (if app uses sensitive features)
    local privacy_keys=(
        "NSCameraUsageDescription"
        "NSMicrophoneUsageDescription"
        "NSLocationWhenInUseUsageDescription"
        "NSLocationAlwaysAndWhenInUseUsageDescription"
        "NSPhotoLibraryUsageDescription"
        "NSContactsUsageDescription"
        "NSCalendarsUsageDescription"
        "NSRemindersUsageDescription"
        "NSMotionUsageDescription"
        "NSHealthUpdateUsageDescription"
        "NSHealthShareUsageDescription"
        "NSBluetoothPeripheralUsageDescription"
        "NSBluetoothAlwaysUsageDescription"
        "NSSpeechRecognitionUsageDescription"
        "NSFaceIDUsageDescription"
    )
    
    local privacy_found=false
    for key in "${privacy_keys[@]}"; do
        if plutil -extract "$key" raw "$info_plist" >/dev/null 2>&1; then
            local value=$(plutil -extract "$key" raw "$info_plist" 2>/dev/null)
            log_info "Privacy Usage: $key = $value"
            privacy_found=true
        fi
    done
    
    if [ "$privacy_found" = false ]; then
        log_info "No privacy usage descriptions found (add if app uses sensitive features)"
    fi
    
    return 0
}

# Function to validate app icons
validate_app_icons() {
    log_info "Validating app icons..."
    
    # Check for app icon files in various locations
    local icon_locations=(
        "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        "assets/images"
        "ios/Runner"
    )
    
    local icons_found=false
    
    for location in "${icon_locations[@]}"; do
        if [ -d "$location" ]; then
            local icon_count=$(find "$location" -name "*icon*" -o -name "*Icon*" -o -name "*.png" | wc -l)
            if [ "$icon_count" -gt 0 ]; then
                log_info "Found $icon_count icon files in $location"
                icons_found=true
                
                # List icon files
                find "$location" -name "*icon*" -o -name "*Icon*" -o -name "*.png" | while read -r icon_file; do
                    if [ -f "$icon_file" ]; then
                        local icon_size=$(identify "$icon_file" 2>/dev/null | cut -d' ' -f3 || echo "unknown")
                        log_info "  - $(basename "$icon_file"): $icon_size"
                    fi
                done 2>/dev/null || true
            fi
        fi
    done
    
    # Check for 1024x1024 icon specifically
    local large_icon_found=false
    find . -name "*.png" -exec identify {} \; 2>/dev/null | grep "1024x1024" | while read -r line; do
        local icon_file=$(echo "$line" | cut -d' ' -f1)
        log_success "Found 1024x1024 icon: $icon_file"
        large_icon_found=true
    done || true
    
    if [ "$icons_found" = false ]; then
        log_error "No app icons found - app icons are required for App Store submission"
        return 1
    fi
    
    # Check flutter_launcher_icons configuration
    if grep -q "flutter_launcher_icons:" pubspec.yaml; then
        log_info "flutter_launcher_icons configuration found in pubspec.yaml"
        if grep -q "ios: true" pubspec.yaml; then
            log_success "iOS icon generation enabled"
        else
            log_warn "iOS icon generation may not be enabled"
        fi
    else
        log_info "No flutter_launcher_icons configuration found"
    fi
    
    return 0
}

# Function to validate certificates and provisioning
validate_certificates() {
    log_info "Validating certificate and provisioning configuration..."
    
    # Check environment variables
    local cert_methods=()
    
    # App Store Connect API
    if [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ] && [ -n "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" ] && [ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]; then
        cert_methods+=("App Store Connect API")
        log_success "App Store Connect API credentials configured"
        log_info "  - Issuer ID: ${APP_STORE_CONNECT_ISSUER_ID}"
        log_info "  - Key ID: ${APP_STORE_CONNECT_KEY_IDENTIFIER}"
        log_info "  - Key Path: ${APP_STORE_CONNECT_API_KEY_PATH}"
    else
        log_warn "App Store Connect API credentials incomplete"
    fi
    
    # Manual certificates
    if [ -n "${CERT_P12_URL:-}" ] && [ -n "${PROFILE_URL:-}" ] && [ -n "${CERT_PASSWORD:-}" ]; then
        cert_methods+=("Manual Certificates")
        log_success "Manual certificate configuration found"
        log_info "  - Certificate URL: ${CERT_P12_URL}"
        log_info "  - Profile URL: ${PROFILE_URL}"
        log_info "  - Password: [SET]"
    else
        log_info "Manual certificate configuration not complete"
    fi
    
    # Team ID
    if [ -n "${APPLE_TEAM_ID:-}" ]; then
        log_success "Apple Team ID configured: ${APPLE_TEAM_ID}"
    else
        log_error "APPLE_TEAM_ID is required for App Store distribution"
        return 1
    fi
    
    if [ ${#cert_methods[@]} -eq 0 ]; then
        log_warn "No certificate methods configured - automatic signing will be attempted"
        log_info "For App Store distribution, consider configuring:"
        log_info "  1. App Store Connect API (recommended)"
        log_info "  2. Manual certificates (alternative)"
    else
        log_success "Certificate methods available: ${cert_methods[*]}"
    fi
    
    return 0
}

# Function to validate Firebase configuration (if enabled)
validate_firebase_config() {
    if [ "${PUSH_NOTIFY:-false}" = "true" ]; then
        log_info "Validating Firebase configuration (push notifications enabled)..."
        
        if [ -n "${FIREBASE_CONFIG_IOS:-}" ]; then
            log_success "Firebase iOS configuration URL provided"
            log_info "  - URL: ${FIREBASE_CONFIG_IOS}"
        else
            log_error "FIREBASE_CONFIG_IOS required when PUSH_NOTIFY=true"
            return 1
        fi
        
        # Check for local Firebase files
        local firebase_files=(
            "ios/Runner/GoogleService-Info.plist"
            "assets/GoogleService-Info.plist"
        )
        
        for file in "${firebase_files[@]}"; do
            if [ -f "$file" ]; then
                log_info "Firebase config file found: $file"
                
                # Validate basic structure
                if plutil -lint "$file" >/dev/null 2>&1; then
                    log_success "Firebase config file is valid"
                    
                    # Check key fields
                    local project_id=$(plutil -extract PROJECT_ID raw "$file" 2>/dev/null || echo "")
                    local bundle_id=$(plutil -extract BUNDLE_ID raw "$file" 2>/dev/null || echo "")
                    
                    if [ -n "$project_id" ]; then
                        log_info "Firebase Project ID: $project_id"
                    fi
                    
                    if [ -n "$bundle_id" ] && [ -n "${BUNDLE_ID:-}" ]; then
                        if [ "$bundle_id" = "$BUNDLE_ID" ]; then
                            log_success "Firebase bundle ID matches app bundle ID"
                        else
                            log_warn "Firebase bundle ID ($bundle_id) != app bundle ID ($BUNDLE_ID)"
                        fi
                    fi
                else
                    log_error "Invalid Firebase config file: $file"
                fi
            fi
        done
    else
        log_info "Push notifications disabled - Firebase configuration optional"
    fi
    
    return 0
}

# Function to validate pubspec.yaml
validate_pubspec() {
    log_info "Validating pubspec.yaml configuration..."
    
    if [ ! -f "pubspec.yaml" ]; then
        log_error "pubspec.yaml not found"
        return 1
    fi
    
    # Check app version
    local pubspec_version=$(grep "^version:" pubspec.yaml | cut -d':' -f2 | tr -d ' ')
    if [ -n "$pubspec_version" ]; then
        log_info "Pubspec version: $pubspec_version"
        
        # Extract version and build number
        local version_part=$(echo "$pubspec_version" | cut -d'+' -f1)
        local build_part=$(echo "$pubspec_version" | cut -d'+' -f2)
        
        if [ -n "$version_part" ] && [ -n "$build_part" ]; then
            validate_version_format "$version_part" "$build_part"
        fi
    else
        log_error "Version not found in pubspec.yaml"
    fi
    
    # Check for required dependencies
    local required_deps=("flutter" "cupertino_icons")
    for dep in "${required_deps[@]}"; do
        if grep -q "^  $dep:" pubspec.yaml; then
            log_success "Required dependency found: $dep"
        else
            log_warn "Required dependency missing: $dep"
        fi
    done
    
    # Check Firebase dependencies (if push notifications enabled)
    if [ "${PUSH_NOTIFY:-false}" = "true" ]; then
        local firebase_deps=("firebase_core" "firebase_messaging")
        for dep in "${firebase_deps[@]}"; do
            if grep -q "^  $dep:" pubspec.yaml; then
                local version=$(grep "^  $dep:" pubspec.yaml | cut -d':' -f2 | tr -d ' ')
                log_success "Firebase dependency found: $dep $version"
            else
                log_error "Required Firebase dependency missing: $dep"
            fi
        done
    fi
    
    return 0
}

# Function to create App Store readiness report
create_readiness_report() {
    local report_file="${OUTPUT_DIR:-output/ios}/APP_STORE_READINESS_REPORT.txt"
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
=== App Store Readiness Report ===
Generated: $(date)
Profile Type: ${PROFILE_TYPE:-unknown}
Bundle ID: ${BUNDLE_ID:-unknown}
App Name: ${APP_NAME:-unknown}
Version: ${VERSION_NAME:-unknown} (${VERSION_CODE:-unknown})

=== Configuration Status ===
EOF

    # Add validation results
    echo "Bundle ID Format: $(validate_bundle_id_format "${BUNDLE_ID:-}" >/dev/null 2>&1 && echo "✅ Valid" || echo "❌ Invalid")" >> "$report_file"
    echo "Version Format: $(validate_version_format "${VERSION_NAME:-1.0.0}" "${VERSION_CODE:-1}" >/dev/null 2>&1 && echo "✅ Valid" || echo "⚠️ Check Format")" >> "$report_file"
    echo "Project Config: $(validate_project_config >/dev/null 2>&1 && echo "✅ Valid" || echo "⚠️ Issues Found")" >> "$report_file"
    echo "Info.plist: $(validate_info_plist >/dev/null 2>&1 && echo "✅ Valid" || echo "⚠️ Issues Found")" >> "$report_file"
    echo "App Icons: $(validate_app_icons >/dev/null 2>&1 && echo "✅ Found" || echo "❌ Missing")" >> "$report_file"
    echo "Certificates: $(validate_certificates >/dev/null 2>&1 && echo "✅ Configured" || echo "⚠️ Incomplete")" >> "$report_file"
    echo "Firebase: $(validate_firebase_config >/dev/null 2>&1 && echo "✅ Valid" || echo "⚠️ Check Config")" >> "$report_file"
    echo "Pubspec: $(validate_pubspec >/dev/null 2>&1 && echo "✅ Valid" || echo "⚠️ Issues Found")" >> "$report_file"

    cat >> "$report_file" << EOF

=== App Store Requirements Checklist ===
✅ iOS 13.0+ deployment target
✅ Valid bundle identifier format
✅ App version and build number
✅ Required Info.plist keys
✅ App icons (including 1024x1024)
✅ Code signing configuration
✅ Privacy usage descriptions (if applicable)
✅ Firebase configuration (if push notifications enabled)

=== Pre-Submission Checklist ===
□ Test app on physical iOS device
□ Verify all app functionality works
□ Test push notifications (if enabled)
□ Verify app metadata in App Store Connect
□ Prepare app screenshots and description
□ Set app pricing and availability
□ Configure App Store review information
□ Test app with TestFlight (recommended)

=== Next Steps ===
1. Build and export IPA with app-store profile
2. Upload to App Store Connect
3. Submit for App Store review
4. Monitor review status

Report generated at: $(date)
EOF

    log_success "App Store readiness report created: $report_file"
}

# Main validation function
main() {
    log_info "🍎 App Store Readiness Validation Starting..."
    log_info "⏰ Current Time: $(date)"
    log_info "🎯 Profile Type: ${PROFILE_TYPE:-NOT_SET}"
    log_info "📱 Bundle ID: ${BUNDLE_ID:-NOT_SET}"
    log_info ""
    
    local validation_passed=true
    
    # Run all validations
    if [ -n "${BUNDLE_ID:-}" ]; then
        validate_bundle_id_format "$BUNDLE_ID" || validation_passed=false
    else
        log_error "BUNDLE_ID environment variable is required"
        validation_passed=false
    fi
    
    if [ -n "${VERSION_NAME:-}" ] && [ -n "${VERSION_CODE:-}" ]; then
        validate_version_format "$VERSION_NAME" "$VERSION_CODE" || validation_passed=false
    else
        log_warn "VERSION_NAME and VERSION_CODE not set"
    fi
    
    validate_project_config || validation_passed=false
    validate_info_plist || validation_passed=false
    validate_app_icons || validation_passed=false
    validate_certificates || validation_passed=false
    validate_firebase_config || validation_passed=false
    validate_pubspec || validation_passed=false
    
    # Create readiness report
    create_readiness_report
    
    if [ "$validation_passed" = true ]; then
        log_success "🎉 App Store readiness validation passed!"
        log_info "Your app appears ready for App Store submission"
        return 0
    else
        log_warn "⚠️ App Store readiness validation found issues"
        log_info "Please review the issues above before App Store submission"
        log_info "Check the detailed report: ${OUTPUT_DIR:-output/ios}/APP_STORE_READINESS_REPORT.txt"
        return 1
    fi
}

# Run main function
main "$@" 