#!/bin/bash

# Main iOS Build Orchestration Script
# Purpose: Orchestrate the entire iOS build workflow

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/utils.sh"

log_info "Starting iOS Build Workflow..."

# Function to send email notifications
send_email() {
    local email_type="$1"
    local platform="$2"
    local build_id="$3"
    local error_message="$4"
    
    if [ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" = "true" ]; then
        log_info "Sending $email_type email for $platform build $build_id"
        "${SCRIPT_DIR}/email_notifications.sh" "$email_type" "$platform" "$build_id" "$error_message" || log_warn "Failed to send email notification"
    fi
}

# Function to load environment variables
load_environment_variables() {
    log_info "Loading environment variables..."
    
    # Validate essential variables
    if [ -z "${BUNDLE_ID:-}" ]; then
        log_error "BUNDLE_ID is not set. Exiting."
        return 1
    fi
    
    if [ -z "${PROFILE_TYPE:-}" ]; then
        log_error "PROFILE_TYPE is not set. Exiting."
        return 1
    fi
    
    # Set default values
export OUTPUT_DIR="${OUTPUT_DIR:-output/ios}"
export PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
export CM_BUILD_DIR="${CM_BUILD_DIR:-$(pwd)}"
    export PROFILE_TYPE="${PROFILE_TYPE:-app-store}"
    
    log_success "Environment variables loaded successfully"
    return 0
}

# Main execution function
main() {
    log_info "iOS Build Workflow Starting..."
    
    # Load environment variables
    if ! load_environment_variables; then
        log_error "Environment variable loading failed"
        return 1
    fi
    
    # Stage 1: Pre-build Setup
    log_info "--- Stage 1: Pre-build Setup ---"
    if ! "${SCRIPT_DIR}/setup_environment.sh"; then
        send_email "build_failed" "iOS" "${CM_BUILD_ID:-unknown}" "Pre-build setup failed."
        return 1
    fi
    
    # Stage 2: Email Notification - Build Started
    if [ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" = "true" ]; then
        log_info "--- Stage 2: Sending Build Started Email ---"
        "${SCRIPT_DIR}/email_notifications.sh" "build_started" "iOS" "${CM_BUILD_ID:-unknown}" || log_warn "Failed to send build started email."
    fi
    
    # Stage 3: Handle Certificates and Provisioning Profiles
    log_info "--- Stage 3: Handling Certificates and Provisioning Profiles ---"
    if ! "${SCRIPT_DIR}/handle_certificates.sh"; then
        send_email "build_failed" "iOS" "${CM_BUILD_ID:-unknown}" "Certificate and profile handling failed."
        return 1
    fi
    
    # Stage 4: Branding Assets Setup
    log_info "--- Stage 4: Setting up Branding Assets ---"
    if ! "${SCRIPT_DIR}/branding_assets.sh"; then
        send_email "build_failed" "iOS" "${CM_BUILD_ID:-unknown}" "Branding assets setup failed."
        return 1
    fi
    
    # Stage 4.5: Generate Flutter Launcher Icons (iOS-specific)
    log_info "--- Stage 4.5: Generating Flutter Launcher Icons ---"
    if ! "${SCRIPT_DIR}/generate_launcher_icons.sh"; then
        send_email "build_failed" "iOS" "${CM_BUILD_ID:-unknown}" "Flutter Launcher Icons generation failed."
        return 1
    fi
    
    # Stage 5: Dynamic Permission Injection
    log_info "--- Stage 5: Injecting Dynamic Permissions ---"
    if ! "${SCRIPT_DIR}/inject_permissions.sh"; then
        send_email "build_failed" "iOS" "${CM_BUILD_ID:-unknown}" "Permission injection failed."
        return 1
    fi
    
    # Stage 6: Firebase Integration (Conditional)
if [ "${PUSH_NOTIFY:-false}" = "true" ]; then
        log_info "--- Stage 6: Setting up Firebase ---"
        if ! "${SCRIPT_DIR}/firebase_setup.sh"; then
            send_email "build_failed" "iOS" "${CM_BUILD_ID:-unknown}" "Firebase setup failed."
            return 1
        fi
    else
        log_info "--- Stage 6: Skipping Firebase (Push notifications disabled) ---"
    fi
    
    # Stage 7: Flutter Build Process
    log_info "--- Stage 7: Building Flutter iOS App ---"
    if ! "${SCRIPT_DIR}/build_flutter_app.sh"; then
        send_email "build_failed" "iOS" "${CM_BUILD_ID:-unknown}" "Flutter build failed."
        return 1
    fi
    
    # Stage 8: IPA Export
    log_info "--- Stage 8: Exporting IPA ---"
    if ! "${SCRIPT_DIR}/export_ipa.sh"; then
        send_email "build_failed" "iOS" "${CM_BUILD_ID:-unknown}" "IPA export failed."
        return 1
    fi
    
    # Stage 8.5: App Store Readiness Validation (for app-store profile)
    if [ "${PROFILE_TYPE:-app-store}" = "app-store" ]; then
        log_info "--- Stage 8.5: App Store Readiness Validation ---"
        if [ -f "${SCRIPT_DIR}/validate_app_store_readiness.sh" ]; then
            chmod +x "${SCRIPT_DIR}/validate_app_store_readiness.sh"
            if "${SCRIPT_DIR}/validate_app_store_readiness.sh"; then
                log_success "App Store readiness validation passed"
            else
                log_warn "App Store readiness validation found issues"
                log_info "Check APP_STORE_READINESS_REPORT.txt for details"
            fi
        else
            log_warn "App Store readiness validation script not found"
        fi
    fi
    
    # Stage 9: Email Notification - Build Success
    if [ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" = "true" ]; then
        log_info "--- Stage 9: Sending Build Success Email ---"
        "${SCRIPT_DIR}/email_notifications.sh" "build_success" "iOS" "${CM_BUILD_ID:-unknown}" || log_warn "Failed to send build success email."
    fi
    
    log_success "iOS workflow completed successfully!"
    log_info "Build Summary:"
    log_info "   App: ${APP_NAME:-Unknown} v${VERSION_NAME:-Unknown}"
    log_info "   Bundle ID: ${BUNDLE_ID:-Unknown}"
    log_info "   Profile Type: ${PROFILE_TYPE:-Unknown}"
    log_info "   Output: ${OUTPUT_DIR:-Unknown}"
    
    # Check for build artifacts
    if [ -f "${OUTPUT_DIR:-output/ios}/Runner.ipa" ]; then
        local ipa_size=$(du -h "${OUTPUT_DIR:-output/ios}/Runner.ipa" | cut -f1)
        log_info "   IPA: Runner.ipa ($ipa_size)"
        
        # App Store specific information
        if [ "${PROFILE_TYPE:-app-store}" = "app-store" ]; then
            log_info "   Distribution: Ready for App Store Connect"
            log_info "   Next Steps:"
            log_info "     1. Download Runner.ipa from build artifacts"
            log_info "     2. Upload to App Store Connect using Transporter or Xcode"
            log_info "     3. Submit for App Store review"
            
            # Check for App Store readiness report
            if [ -f "${OUTPUT_DIR:-output/ios}/APP_STORE_READINESS_REPORT.txt" ]; then
                log_info "   📋 App Store Readiness Report available in artifacts"
            fi
        fi
    elif [ -d "${OUTPUT_DIR:-output/ios}/Runner.xcarchive" ]; then
        local archive_size=$(du -h "${OUTPUT_DIR:-output/ios}/Runner.xcarchive" | cut -f1)
        log_info "   Archive: Runner.xcarchive ($archive_size)"
        log_warn "   IPA export failed - manual export required"
        
        if [ "${PROFILE_TYPE:-app-store}" = "app-store" ]; then
            log_info "   Manual Export for App Store:"
            log_info "     1. Download Runner.xcarchive from build artifacts"
            log_info "     2. Open Xcode > Window > Organizer"
            log_info "     3. Import archive and select 'Distribute App'"
            log_info "     4. Choose 'App Store Connect' > 'Upload'"
        fi
    fi
    
    return 0
}

# Run main function
main "$@"
