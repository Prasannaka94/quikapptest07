#!/bin/bash

# IPA Export Script for iOS Build (Enhanced Version v3.0)
# Purpose: Export IPA file from Xcode archive with profile-type-based configuration
# Supports: app-store, ad-hoc, enterprise, development

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/utils.sh"

log_info "Starting IPA Export... (Enhanced Version v3.0 with Profile Type Support)"

# Function to create ExportOptions.plist based on profile type
create_export_options() {
    log_info "Creating ExportOptions.plist for $PROFILE_TYPE distribution..."
    
    local export_options_path="ios/ExportOptions.plist"
    local method="app-store"
    local upload_bitcode="false"
    local upload_symbols="true"
    local compile_bitcode="false"
    local signing_style="automatic"
    local strip_swift_symbols="true"
    local thinning="<none>"
    
    # Determine export method and settings based on profile type
    case "${PROFILE_TYPE:-app-store}" in
        "app-store")
            method="app-store"
            upload_bitcode="false"
            upload_symbols="true"
            compile_bitcode="false"
            signing_style="automatic"
            strip_swift_symbols="true"
            thinning="<none>"
            ;;
        "ad-hoc")
            method="ad-hoc"
            upload_bitcode="false"
            upload_symbols="false"
            compile_bitcode="false"
            signing_style="automatic"
            strip_swift_symbols="true"
            thinning="<none>"
            ;;
        "enterprise")
            method="enterprise"
            upload_bitcode="false"
            upload_symbols="false"
            compile_bitcode="false"
            signing_style="automatic"
            strip_swift_symbols="true"
            thinning="<none>"
            ;;
        "development")
            method="development"
            upload_bitcode="false"
            upload_symbols="false"
            compile_bitcode="false"
            signing_style="automatic"
            strip_swift_symbols="false"
            thinning="<none>"
            ;;
        *)
            log_error "Invalid profile type: $PROFILE_TYPE"
            log_info "Supported types: app-store, ad-hoc, enterprise, development"
            return 1
            ;;
    esac
    
    log_info "Export configuration:"
    log_info "  - Method: $method"
    log_info "  - Profile Type: $PROFILE_TYPE"
    log_info "  - Signing Style: $signing_style"
    log_info "  - Upload Bitcode: $upload_bitcode"
    log_info "  - Upload Symbols: $upload_symbols"
    log_info "  - Strip Swift Symbols: $strip_swift_symbols"
    log_info "  - Thinning: $thinning"
    
    # Create ExportOptions.plist with App Store compliance settings
    cat > "$export_options_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>$method</string>
    <key>teamID</key>
    <string>${APPLE_TEAM_ID:-}</string>
    <key>uploadBitcode</key>
    <$upload_bitcode/>
    <key>uploadSymbols</key>
    <$upload_symbols/>
    <key>compileBitcode</key>
    <$compile_bitcode/>
    <key>signingStyle</key>
    <string>$signing_style</string>
    <key>stripSwiftSymbols</key>
    <$strip_swift_symbols/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
    <key>generateAppStoreInformation</key>
    <true/>
    <key>destination</key>
    <string>export</string>
    <key>signingCertificate</key>
    <string>Apple Distribution</string>
EOF

    # Add App Store specific configurations
    if [ "$method" = "app-store" ]; then
        cat >> "$export_options_path" << EOF
    <key>uploadToAppStore</key>
    <false/>
    <key>distributionBundleIdentifier</key>
    <string>${BUNDLE_ID:-}</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>${BUNDLE_ID:-}</key>
        <string>match AppStore ${BUNDLE_ID:-}</string>
    </dict>
    <key>iCloudContainerEnvironment</key>
    <string>Production</string>
    <key>embedOnDemandResourcesAssetPacksInBundle</key>
    <true/>
    <key>onDemandResourcesAssetPacksBaseURL</key>
    <string></string>
    <key>manageAppVersionAndBuildNumber</key>
    <true/>
EOF
    fi

    # Add profile-specific bundle identifier configurations
    if [ -n "${BUNDLE_ID:-}" ]; then
        cat >> "$export_options_path" << EOF
    <key>provisioningProfiles</key>
    <dict>
        <key>${BUNDLE_ID}</key>
        <string>match $method ${BUNDLE_ID}</string>
    </dict>
EOF
    fi

    cat >> "$export_options_path" << EOF
</dict>
</plist>
EOF
    
    if [ -f "$export_options_path" ]; then
        log_success "ExportOptions.plist created successfully"
        log_info "Export options saved to: $export_options_path"
        
        # Validate ExportOptions.plist syntax
        if plutil -lint "$export_options_path" >/dev/null 2>&1; then
            log_success "ExportOptions.plist syntax is valid"
        else
            log_warn "ExportOptions.plist syntax validation failed"
        fi
        
        # Log the contents for debugging
        log_info "ExportOptions.plist contents:"
        cat "$export_options_path" | while IFS= read -r line; do
            log_info "  $line"
        done
        
        return 0
    else
        log_error "Failed to create ExportOptions.plist"
        return 1
    fi
}

# Function to export IPA using App Store Connect API
export_with_app_store_connect_api() {
    log_info "Attempting export with App Store Connect API..."
    
    local archive_path="${OUTPUT_DIR:-output/ios}/Runner.xcarchive"
    local export_path="${OUTPUT_DIR:-output/ios}"
    local export_options_path="ios/ExportOptions.plist"
    
    # Validate App Store Connect API credentials
    if [ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" ] || [ -z "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" ] || [ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
        log_warn "App Store Connect API credentials incomplete, skipping..."
        log_info "Required variables:"
        log_info "  - APP_STORE_CONNECT_API_KEY_PATH: ${APP_STORE_CONNECT_API_KEY_PATH:-NOT_SET}"
        log_info "  - APP_STORE_CONNECT_KEY_IDENTIFIER: ${APP_STORE_CONNECT_KEY_IDENTIFIER:-NOT_SET}"
        log_info "  - APP_STORE_CONNECT_ISSUER_ID: ${APP_STORE_CONNECT_ISSUER_ID:-NOT_SET}"
        return 1
    fi
    
    # Download API key
    local api_key_path="/tmp/AuthKey_${APP_STORE_CONNECT_KEY_IDENTIFIER}.p8"
    log_info "Downloading API key from: ${APP_STORE_CONNECT_API_KEY_PATH}"
    
    if curl -L -o "$api_key_path" "${APP_STORE_CONNECT_API_KEY_PATH}" 2>/dev/null; then
        chmod 600 "$api_key_path"
        log_success "API key downloaded successfully"
    else
        log_error "Failed to download API key from: ${APP_STORE_CONNECT_API_KEY_PATH}"
        log_info "Please check:"
        log_info "  1. API key URL is accessible"
        log_info "  2. API key has correct permissions"
        log_info "  3. Network connectivity"
        return 1
    fi
    
    # Try export with App Store Connect API
    log_info "Running xcodebuild export with App Store Connect API..."
    if xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options_path" \
        -authenticationKeyPath "$api_key_path" \
        -authenticationKeyID "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
        -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
        -allowProvisioningUpdates; then
        
        log_success "App Store Connect API export successful!"
        rm -f "$api_key_path"
        return 0
    else
        log_warn "App Store Connect API export failed"
        rm -f "$api_key_path"
        return 1
    fi
}

# Function to export IPA using automatic signing
export_with_automatic_signing() {
    log_info "Attempting export with automatic signing..."
    
    local archive_path="${OUTPUT_DIR:-output/ios}/Runner.xcarchive"
    local export_path="${OUTPUT_DIR:-output/ios}"
    local export_options_path="ios/ExportOptions.plist"
    
    # Check if we have the required environment variables for automatic signing
    if [ -z "${APPLE_TEAM_ID:-}" ]; then
        log_warn "APPLE_TEAM_ID not set, automatic signing may fail"
        log_info "Please set APPLE_TEAM_ID environment variable"
    fi
    
    if [ -z "${BUNDLE_ID:-}" ]; then
        log_warn "BUNDLE_ID not set, automatic signing may fail"
        log_info "Please set BUNDLE_ID environment variable"
    fi
    
    log_info "Running xcodebuild export with automatic signing..."
    log_info "Team ID: ${APPLE_TEAM_ID:-NOT_SET}"
    log_info "Bundle ID: ${BUNDLE_ID:-NOT_SET}"
    
    if xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options_path" \
        -allowProvisioningUpdates; then
        
        log_success "Automatic signing export successful!"
        return 0
    else
        log_warn "Automatic signing export failed"
        log_info "Common causes:"
        log_info "  1. No Apple Developer account configured in Xcode"
        log_info "  2. Missing provisioning profiles for bundle ID: ${BUNDLE_ID:-unknown}"
        log_info "  3. Invalid team ID: ${APPLE_TEAM_ID:-unknown}"
        log_info "  4. App Store Connect API credentials required for app-store distribution"
        return 1
    fi
}

# Function to export IPA using manual certificates
export_with_manual_certificates() {
    log_info "Attempting export with manual certificates..."
    
    local archive_path="${OUTPUT_DIR:-output/ios}/Runner.xcarchive"
    local export_path="${OUTPUT_DIR:-output/ios}"
    local export_options_path="ios/ExportOptions.plist"
    
    # Validate manual certificate credentials
    if [ -z "${CERT_P12_URL:-}" ] || [ -z "${PROFILE_URL:-}" ] || [ -z "${CERT_PASSWORD:-}" ]; then
        log_warn "Manual certificate credentials incomplete, skipping..."
        log_info "Required variables:"
        log_info "  - CERT_P12_URL: ${CERT_P12_URL:-NOT_SET}"
        log_info "  - PROFILE_URL: ${PROFILE_URL:-NOT_SET}"
        log_info "  - CERT_PASSWORD: ${CERT_PASSWORD:+SET}"
        log_info "For manual certificate export, please provide all three variables"
        return 1
    fi
    
    # Download and install certificates
    local cert_dir="/tmp/certs_manual"
    mkdir -p "$cert_dir"
    
    # Download provisioning profile
    log_info "Downloading provisioning profile from: ${PROFILE_URL}"
    if curl -L -o "$cert_dir/profile.mobileprovision" "${PROFILE_URL}" 2>/dev/null; then
        log_success "Provisioning profile downloaded"
    else
        log_error "Failed to download provisioning profile from: ${PROFILE_URL}"
        rm -rf "$cert_dir"
        return 1
    fi
    
    # Download certificate
    log_info "Downloading certificate from: ${CERT_P12_URL}"
    if curl -L -o "$cert_dir/certificate.p12" "${CERT_P12_URL}" 2>/dev/null; then
        log_success "Certificate downloaded"
    else
        log_error "Failed to download certificate from: ${CERT_P12_URL}"
        rm -rf "$cert_dir"
        return 1
    fi
    
    # Install certificate in keychain
    local keychain_path="/Users/builder/Library/Keychains/ios-build.keychain-db"
    if [ ! -f "$keychain_path" ]; then
        keychain_path="/Users/builder/Library/Keychains/ios-build.keychain"
    fi
    
    log_info "Installing certificate in keychain: $keychain_path"
    if security import "$cert_dir/certificate.p12" -k "$keychain_path" -P "${CERT_PASSWORD}" -T /usr/bin/codesign 2>/dev/null; then
        log_success "Certificate installed successfully"
    else
        log_error "Failed to install certificate in keychain"
        log_info "Please check:"
        log_info "  1. Certificate password is correct"
        log_info "  2. Certificate file is valid"
        log_info "  3. Keychain permissions"
        rm -rf "$cert_dir"
        return 1
    fi
    
    # Install provisioning profile
    local profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$profile_dir"
    cp "$cert_dir/profile.mobileprovision" "$profile_dir/"
    log_success "Provisioning profile installed"
    
    # Try export with manual certificates
    log_info "Running xcodebuild export with manual certificates..."
    if xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options_path" \
        -allowProvisioningUpdates; then
        
        log_success "Manual certificate export successful!"
        rm -rf "$cert_dir"
        return 0
    else
        log_warn "Manual certificate export failed"
        log_info "Please check:"
        log_info "  1. Certificate matches provisioning profile"
        log_info "  2. Bundle ID matches provisioning profile"
        log_info "  3. Certificate is valid and not expired"
        rm -rf "$cert_dir"
        return 1
    fi
}

# Function to validate IPA file for App Store compliance
validate_ipa() {
    local ipa_file="$1"
    
    if [ ! -f "$ipa_file" ]; then
        log_error "IPA file not found: $ipa_file"
        return 1
    fi
    
    local file_size=$(du -h "$ipa_file" | cut -f1)
    local file_size_bytes=$(du -b "$ipa_file" | cut -f1)
    log_info "IPA file size: $file_size ($file_size_bytes bytes)"
    
    # Check if IPA is a valid zip file
    if ! unzip -t "$ipa_file" >/dev/null 2>&1; then
        log_error "IPA file is corrupted"
        return 1
    fi
    
    log_success "IPA file structure is valid"
    
    # App Store specific validations
    if [ "${PROFILE_TYPE:-app-store}" = "app-store" ]; then
        log_info "Performing App Store compliance validation..."
        
        # Check file size (App Store limit is 4GB)
        local max_size_bytes=4294967296  # 4GB in bytes
        if [ "$file_size_bytes" -gt "$max_size_bytes" ]; then
            log_error "IPA file too large for App Store: $file_size (max 4GB)"
            return 1
        fi
        
        # Extract IPA to temporary directory for validation
        local temp_dir="/tmp/ipa_validation_$$"
        mkdir -p "$temp_dir"
        
        if unzip -q "$ipa_file" -d "$temp_dir"; then
            log_info "IPA extracted for validation"
        else
            log_error "Failed to extract IPA for validation"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Find the app bundle
        local app_bundle=$(find "$temp_dir" -name "*.app" -type d | head -1)
        if [ -z "$app_bundle" ]; then
            log_error "No .app bundle found in IPA"
            rm -rf "$temp_dir"
            return 1
        fi
        
        log_info "App bundle found: $(basename "$app_bundle")"
        
        # Validate Info.plist
        local info_plist="$app_bundle/Info.plist"
        if [ -f "$info_plist" ]; then
            log_info "Validating Info.plist..."
            
            # Check bundle identifier
            local bundle_id=$(plutil -extract CFBundleIdentifier raw "$info_plist" 2>/dev/null)
            if [ -n "$bundle_id" ]; then
                log_info "Bundle ID: $bundle_id"
                if [ -n "${BUNDLE_ID:-}" ] && [ "$bundle_id" != "$BUNDLE_ID" ]; then
                    log_warn "Bundle ID mismatch: expected $BUNDLE_ID, found $bundle_id"
                fi
            else
                log_error "CFBundleIdentifier not found in Info.plist"
            fi
            
            # Check app version
            local version=$(plutil -extract CFBundleShortVersionString raw "$info_plist" 2>/dev/null)
            local build=$(plutil -extract CFBundleVersion raw "$info_plist" 2>/dev/null)
            if [ -n "$version" ] && [ -n "$build" ]; then
                log_info "App Version: $version ($build)"
            else
                log_error "Missing version information in Info.plist"
            fi
            
            # Check minimum iOS version
            local min_ios=$(plutil -extract MinimumOSVersion raw "$info_plist" 2>/dev/null)
            if [ -n "$min_ios" ]; then
                log_info "Minimum iOS Version: $min_ios"
            else
                log_warn "MinimumOSVersion not specified in Info.plist"
            fi
            
            # Check app name
            local app_name=$(plutil -extract CFBundleDisplayName raw "$info_plist" 2>/dev/null)
            if [ -z "$app_name" ]; then
                app_name=$(plutil -extract CFBundleName raw "$info_plist" 2>/dev/null)
            fi
            if [ -n "$app_name" ]; then
                log_info "App Name: $app_name"
            else
                log_error "App name not found in Info.plist"
            fi
            
        else
            log_error "Info.plist not found in app bundle"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Check for required app icon
        local app_icon_found=false
        for icon_path in "$app_bundle/AppIcon60x60@3x.png" "$app_bundle/AppIcon60x60@2x.png" "$app_bundle/Icon-App-60x60@3x.png" "$app_bundle/Icon-App-60x60@2x.png"; do
            if [ -f "$icon_path" ]; then
                app_icon_found=true
                log_info "App icon found: $(basename "$icon_path")"
                break
            fi
        done
        
        if [ "$app_icon_found" = false ]; then
            log_warn "No app icons found - this may cause App Store validation issues"
        fi
        
        # Check for 1024x1024 icon in Assets.car or icon files
        if find "$app_bundle" -name "*.png" | grep -q "1024"; then
            log_info "1024x1024 icon found"
        else
            log_warn "1024x1024 app icon may be missing - required for App Store"
        fi
        
        # Check code signing
        log_info "Validating code signing..."
        if codesign -v "$app_bundle" >/dev/null 2>&1; then
            log_success "App bundle is properly code signed"
            
            # Get signing identity
            local signing_identity=$(codesign -dv "$app_bundle" 2>&1 | grep "Authority=" | head -1 | cut -d'=' -f2)
            if [ -n "$signing_identity" ]; then
                log_info "Signing Identity: $signing_identity"
                
                # Check if it's a distribution certificate for App Store
                if echo "$signing_identity" | grep -q "Apple Distribution\|iPhone Distribution"; then
                    log_success "Using valid distribution certificate"
                else
                    log_warn "May not be using proper distribution certificate: $signing_identity"
                fi
            fi
        else
            log_error "App bundle code signing validation failed"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Check for embedded provisioning profile
        local provisioning_profile="$app_bundle/embedded.mobileprovision"
        if [ -f "$provisioning_profile" ]; then
            log_info "Embedded provisioning profile found"
            
            # Extract profile info
            local profile_info=$(security cms -D -i "$provisioning_profile" 2>/dev/null)
            if [ -n "$profile_info" ]; then
                # Check profile type
                if echo "$profile_info" | grep -q "get-task-allow.*false"; then
                    log_success "Using distribution provisioning profile"
                else
                    log_warn "May be using development provisioning profile"
                fi
                
                # Check expiration
                local expiration=$(echo "$profile_info" | grep -A1 "ExpirationDate" | tail -1 | sed 's/.*<date>\(.*\)<\/date>.*/\1/')
                if [ -n "$expiration" ]; then
                    log_info "Profile expires: $expiration"
                fi
            fi
        else
            log_error "No embedded provisioning profile found"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Clean up
        rm -rf "$temp_dir"
        
        log_success "App Store compliance validation completed"
    fi
    
    log_success "IPA validation passed"
    return 0
}

# Function to create archive-only export
create_archive_only_export() {
    log_info "Creating archive-only export..."
    
    local archive_path="${OUTPUT_DIR:-output/ios}/Runner.xcarchive"
    local export_dir="${OUTPUT_DIR:-output/ios}/archive_export"
    
    mkdir -p "$export_dir"
    
    # Copy archive
    if cp -r "$archive_path" "$export_dir/"; then
        log_success "Archive copied successfully"
    else
        log_error "Failed to copy archive"
        return 1
    fi
    
    # Create build information
    cat > "$export_dir/BUILD_INFO.txt" << EOF
=== iOS Build Information ===
Build Date: $(date)
Build ID: ${CM_BUILD_ID:-unknown}
App Name: ${APP_NAME:-unknown}
Bundle ID: ${BUNDLE_ID:-unknown}
Version: ${VERSION_NAME:-unknown} (${VERSION_CODE:-unknown})
Profile Type: ${PROFILE_TYPE:-unknown}
Team ID: ${APPLE_TEAM_ID:-unknown}

=== Export Status ===
Status: Archive Only Export
Reason: IPA export failed, manual export required

=== Manual Export Instructions ===
1. Download Runner.xcarchive from this build
2. Open Xcode on a Mac with Apple Developer account
3. Go to Window > Organizer
4. Click "+" and select "Import"
5. Select Runner.xcarchive
6. Click "Distribute App"
7. Choose distribution method: $PROFILE_TYPE
8. Follow the signing wizard

=== Profile Type Specific Instructions ===
EOF

    case "${PROFILE_TYPE:-app-store}" in
        "app-store")
            cat >> "$export_dir/BUILD_INFO.txt" << EOF
For App Store distribution:
- Choose "App Store Connect"
- Select "Upload" or "Export"
- Ensure your app version is higher than App Store version
EOF
            ;;
        "ad-hoc")
            cat >> "$export_dir/BUILD_INFO.txt" << EOF
For Ad Hoc distribution:
- Choose "Ad Hoc"
- Select registered devices
- Export IPA for device installation
EOF
            ;;
        "enterprise")
            cat >> "$export_dir/BUILD_INFO.txt" << EOF
For Enterprise distribution:
- Choose "Enterprise"
- Export IPA for internal distribution
- Ensure enterprise provisioning profile is valid
EOF
            ;;
        "development")
            cat >> "$export_dir/BUILD_INFO.txt" << EOF
For Development distribution:
- Choose "Development"
- Select development team
- Export IPA for development testing
EOF
            ;;
    esac
    
    cat >> "$export_dir/BUILD_INFO.txt" << EOF

=== Troubleshooting ===
- Verify Apple Developer account access
- Check certificates and provisioning profiles
- Ensure bundle ID matches provisioning profile
- Verify app version is higher than previous version

Build completed at: $(date)
EOF
    
    echo "ARCHIVE_ONLY_EXPORT" > "$export_dir/EXPORT_STATUS.txt"
    
    log_success "Archive-only export created: $export_dir"
    return 0
}

# Function to create artifacts summary
create_artifacts_summary() {
    local summary_file="${OUTPUT_DIR:-output/ios}/ARTIFACTS_SUMMARY.txt"
    
    cat > "$summary_file" << EOF
=== iOS Build Artifacts Summary ===
Build Date: $(date)
Build ID: ${CM_BUILD_ID:-unknown}
Workflow: ${WORKFLOW_ID:-ios-workflow}
Profile Type: ${PROFILE_TYPE:-unknown}

=== App Information ===
App Name: ${APP_NAME:-unknown}
Bundle ID: ${BUNDLE_ID:-unknown}
Version: ${VERSION_NAME:-unknown} (${VERSION_CODE:-unknown})
Team ID: ${APPLE_TEAM_ID:-unknown}

=== Build Results ===
EOF

    local ipa_file="${OUTPUT_DIR:-output/ios}/Runner.ipa"
    local archive_path="${OUTPUT_DIR:-output/ios}/Runner.xcarchive"
    
    if [ -f "$ipa_file" ]; then
        local ipa_size=$(du -h "$ipa_file" | cut -f1)
        cat >> "$summary_file" << EOF
Build Status: SUCCESS
Export Result: IPA created successfully
IPA File: Runner.ipa ($ipa_size)
Distribution: Ready for $PROFILE_TYPE distribution
EOF
    elif [ -d "$archive_path" ]; then
        local archive_size=$(du -h "$archive_path" | cut -f1)
        cat >> "$summary_file" << EOF
Build Status: PARTIAL SUCCESS
Export Result: Archive created, IPA export failed
Archive: Runner.xcarchive ($archive_size)
Next Steps: Manual IPA export required
EOF
    else
        cat >> "$summary_file" << EOF
Build Status: FAILED
Export Result: No artifacts created
Next Steps: Check build logs for errors
EOF
    fi
    
    cat >> "$summary_file" << EOF

=== Export Methods Attempted ===
1. App Store Connect API: ${APP_STORE_CONNECT_API_KEY_PATH:+Available}
2. Automatic Signing: Available
3. Manual Certificates: ${CERT_P12_URL:+Available}
4. Archive Only: Fallback

=== Environment Variables ===
PROFILE_TYPE: ${PROFILE_TYPE:-NOT_SET}
BUNDLE_ID: ${BUNDLE_ID:-NOT_SET}
APPLE_TEAM_ID: ${APPLE_TEAM_ID:-NOT_SET}
APP_STORE_CONNECT_ISSUER_ID: ${APP_STORE_CONNECT_ISSUER_ID:+SET}
APP_STORE_CONNECT_KEY_IDENTIFIER: ${APP_STORE_CONNECT_KEY_IDENTIFIER:+SET}
CERT_P12_URL: ${CERT_P12_URL:+SET}
PROFILE_URL: ${PROFILE_URL:+SET}

Build completed at: $(date)
EOF
    
    log_success "Artifacts summary created: $summary_file"
}

# Main export function
export_ipa() {
    log_info "Starting IPA export process..."
    
    local archive_path="${OUTPUT_DIR:-output/ios}/Runner.xcarchive"
    
    # Verify archive exists
    if [ ! -d "$archive_path" ]; then
        log_error "Archive not found: $archive_path"
        return 1
    fi
    
    log_info "Archive found: $archive_path"
    
    # Create ExportOptions.plist
    if ! create_export_options; then
        log_error "Failed to create ExportOptions.plist"
        return 1
    fi
    
    # Try export methods in order of preference
    local export_success=false
    local method_attempted=""
    
    # Method 1: App Store Connect API (for app-store profile type)
    if [ "${PROFILE_TYPE:-app-store}" = "app-store" ]; then
        method_attempted="App Store Connect API"
        if ! export_with_app_store_connect_api; then
            log_warn "App Store Connect API export failed, trying automatic signing..."
        else
            export_success=true
        fi
    fi
    
    # Method 2: Automatic signing
    if [ "$export_success" = false ]; then
        method_attempted="Automatic Signing"
        if ! export_with_automatic_signing; then
            log_warn "Automatic signing export failed, trying manual certificates..."
        else
            export_success=true
        fi
    fi
    
    # Method 3: Manual certificates
    if [ "$export_success" = false ]; then
        method_attempted="Manual Certificates"
        if ! export_with_manual_certificates; then
            log_warn "Manual certificate export failed"
        else
            export_success=true
        fi
    fi
    
    # Check if any export method succeeded
    local ipa_file="${OUTPUT_DIR:-output/ios}/Runner.ipa"
    if [ "$export_success" = true ] && [ -f "$ipa_file" ]; then
        if validate_ipa "$ipa_file"; then
            log_success "IPA export completed successfully!"
            create_artifacts_summary
            return 0
        else
            log_error "IPA validation failed"
            return 1
        fi
    else
        log_error "All export methods failed"
        log_info "Export methods attempted:"
        log_info "  1. App Store Connect API: ${APP_STORE_CONNECT_API_KEY_PATH:+Available}"
        log_info "  2. Automatic Signing: Available"
        log_info "  3. Manual Certificates: ${CERT_P12_URL:+Available}"
        
        # Create detailed troubleshooting information
        create_detailed_troubleshooting_guide
        return 1
    fi
}

# Function to create detailed troubleshooting guide
create_detailed_troubleshooting_guide() {
    log_info "Creating detailed troubleshooting guide..."
    
    local troubleshooting_file="${OUTPUT_DIR:-output/ios}/TROUBLESHOOTING_GUIDE.txt"
    
    cat > "$troubleshooting_file" << EOF
=== iOS IPA Export Troubleshooting Guide ===
Build Date: $(date)
Profile Type: ${PROFILE_TYPE:-unknown}
Bundle ID: ${BUNDLE_ID:-unknown}
Team ID: ${APPLE_TEAM_ID:-unknown}

=== Export Methods Attempted ===
1. App Store Connect API: ${APP_STORE_CONNECT_API_KEY_PATH:+Available}
2. Automatic Signing: Available
3. Manual Certificates: ${CERT_P12_URL:+Available}

=== Environment Variables Status ===
PROFILE_TYPE: ${PROFILE_TYPE:-NOT_SET}
BUNDLE_ID: ${BUNDLE_ID:-NOT_SET}
APPLE_TEAM_ID: ${APPLE_TEAM_ID:-NOT_SET}

App Store Connect API:
- APP_STORE_CONNECT_ISSUER_ID: ${APP_STORE_CONNECT_ISSUER_ID:+SET}
- APP_STORE_CONNECT_KEY_IDENTIFIER: ${APP_STORE_CONNECT_KEY_IDENTIFIER:+SET}
- APP_STORE_CONNECT_API_KEY_PATH: ${APP_STORE_CONNECT_API_KEY_PATH:+SET}

Manual Certificates:
- CERT_P12_URL: ${CERT_P12_URL:+SET}
- PROFILE_URL: ${PROFILE_URL:+SET}
- CERT_PASSWORD: ${CERT_PASSWORD:+SET}

=== Solutions by Profile Type ===

EOF

    case "${PROFILE_TYPE:-app-store}" in
        "app-store")
            cat >> "$troubleshooting_file" << EOF
For App Store Distribution:
1. App Store Connect API (Recommended):
   - Set APP_STORE_CONNECT_ISSUER_ID
   - Set APP_STORE_CONNECT_KEY_IDENTIFIER
   - Set APP_STORE_CONNECT_API_KEY_PATH to a valid URL
   - Ensure API key has App Manager role

2. Manual Certificates (Alternative):
   - Set CERT_P12_URL to your distribution certificate
   - Set PROFILE_URL to your App Store provisioning profile
   - Set CERT_PASSWORD to your certificate password
   - Ensure certificate matches provisioning profile

3. Automatic Signing (Limited):
   - Requires Apple Developer account in Xcode
   - Requires valid App Store provisioning profile
   - May not work in CI/CD environments

Common Issues:
- "No Accounts": Apple Developer account not configured
- "No profiles found": Missing App Store provisioning profile
- "API key download failed": Check URL accessibility and permissions
EOF
            ;;
        "ad-hoc")
            cat >> "$troubleshooting_file" << EOF
For Ad Hoc Distribution:
1. Manual Certificates (Recommended):
   - Set CERT_P12_URL to your distribution certificate
   - Set PROFILE_URL to your Ad Hoc provisioning profile
   - Set CERT_PASSWORD to your certificate password
   - Ensure profile includes target device UDIDs

2. Automatic Signing (Alternative):
   - Requires Apple Developer account in Xcode
   - Requires valid Ad Hoc provisioning profile
   - May not work in CI/CD environments

Common Issues:
- "No profiles found": Missing Ad Hoc provisioning profile
- "Device not registered": Add device UDIDs to provisioning profile
- "Certificate mismatch": Ensure certificate matches profile
EOF
            ;;
        "enterprise")
            cat >> "$troubleshooting_file" << EOF
For Enterprise Distribution:
1. Manual Certificates (Required):
   - Set CERT_P12_URL to your enterprise distribution certificate
   - Set PROFILE_URL to your enterprise provisioning profile
   - Set CERT_PASSWORD to your certificate password
   - Ensure enterprise account is active

2. Automatic Signing (Limited):
   - Requires enterprise Apple Developer account
   - Requires valid enterprise provisioning profile
   - May not work in CI/CD environments

Common Issues:
- "Enterprise account required": Need enterprise Apple Developer account
- "No profiles found": Missing enterprise provisioning profile
- "Certificate expired": Renew enterprise distribution certificate
EOF
            ;;
        "development")
            cat >> "$troubleshooting_file" << EOF
For Development Distribution:
1. Manual Certificates (Recommended):
   - Set CERT_P12_URL to your development certificate
   - Set PROFILE_URL to your development provisioning profile
   - Set CERT_PASSWORD to your certificate password
   - Ensure profile includes target device UDIDs

2. Automatic Signing (Alternative):
   - Requires Apple Developer account in Xcode
   - Requires valid development provisioning profile
   - May not work in CI/CD environments

Common Issues:
- "No profiles found": Missing development provisioning profile
- "Device not registered": Add device UDIDs to provisioning profile
- "Certificate mismatch": Ensure certificate matches profile
EOF
            ;;
    esac
    
    cat >> "$troubleshooting_file" << EOF

=== Manual Export Instructions ===
1. Download Runner.xcarchive from this build
2. Open Xcode on a Mac with Apple Developer account
3. Go to Window > Organizer
4. Click "+" and select "Import"
5. Select Runner.xcarchive
6. Click "Distribute App"
7. Choose distribution method: $PROFILE_TYPE
8. Follow the signing wizard

=== Alternative Solutions ===
1. Use Fastlane (if available):
   - Install fastlane: gem install fastlane
   - Run: fastlane gym --archive_path Runner.xcarchive

2. Use Xcode Command Line:
   - xcodebuild -exportArchive -archivePath Runner.xcarchive -exportPath . -exportOptionsPlist ExportOptions.plist

3. Use Transporter App:
   - Download archive
   - Use Apple Transporter app for upload

=== Contact Support ===
If you need assistance:
1. Check build logs for detailed error messages
2. Verify all environment variables are set correctly
3. Ensure certificates and profiles are valid
4. Contact your development team with build ID

Build completed at: $(date)
EOF
    
    log_success "Detailed troubleshooting guide created: $troubleshooting_file"
}

# Main execution
main() {
    log_info "IPA Export Starting..."
    log_info "🔧 Script Version: Enhanced v3.0 with Profile Type Support"
    log_info "📂 Script Location: $(realpath "$0")"
    log_info "⏰ Current Time: $(date)"
    log_info "🎯 Profile Type: ${PROFILE_TYPE:-NOT_SET}"
    log_info ""
    
    # Validate required environment variables
    if [ -z "${PROFILE_TYPE:-}" ]; then
        log_error "PROFILE_TYPE is required"
        log_info "Supported types: app-store, ad-hoc, enterprise, development"
        return 1
    fi
    
    if [ -z "${BUNDLE_ID:-}" ]; then
        log_error "BUNDLE_ID is required"
        return 1
    fi
    
    if [ -z "${APPLE_TEAM_ID:-}" ]; then
        log_error "APPLE_TEAM_ID is required"
        return 1
    fi
    
    # Try to export IPA
    if export_ipa; then
        log_success "IPA export process completed successfully!"
        return 0
    else
        log_warn "IPA export failed, creating archive-only export"
        create_archive_only_export
        create_artifacts_summary
        return 0
    fi
}

# Run main function
main "$@"
