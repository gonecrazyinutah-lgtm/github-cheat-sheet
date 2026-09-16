#!/bin/bash
# Build IPA for Finding app - iPhone 16+ Photo Recovery
# Requires macOS + Xcode 15+ + Apple Developer account
# Run: chmod +x build_ipa.sh && ./build_ipa.sh

set -e

APP_NAME="Finding"
SCHEME="Finding"
PROJECT_NAME="Finding"
BUNDLE_ID="com.yourname.finding"
TEAM_ID="" # Fill with your Apple Team ID, find in developer.apple.com > Membership

echo "=== Finding App IPA Builder ==="
echo "App: $APP_NAME for iPhone 16+"

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "ERROR: IPA build requires macOS with Xcode. You are on $(uname)"
  echo "Use GitHub Actions workflow .github/workflows/build-ipa.yml instead"
  echo "Or build manually in Xcode: Product > Archive > Distribute App > Ad Hoc"
  exit 1
fi

# Check Xcode
if ! command -v xcodebuild &> /dev/null; then
  echo "Xcode not found. Install from App Store."
  exit 1
fi

# Create Xcode project if not exists (simple)
if [ ! -d "$PROJECT_NAME.xcodeproj" ]; then
  echo "Creating Xcode project..."
  mkdir -p $PROJECT_NAME
  cp -r Managers Models *.swift $PROJECT_NAME/ 2>/dev/null || true
  
  # Use xcodegen or manual creation - for now, instruct user
  echo "Please open Xcode and create project manually, then re-run this script with project existing"
  echo "Steps: Xcode > New Project > iOS App > SwiftUI > Name: $PROJECT_NAME > Bundle: $BUNDLE_ID"
  echo "Then drag Managers, Models, ContentView.swift into project"
  exit 0
fi

# Build paths
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
IPA_DIR="$BUILD_DIR/ipa"
EXPORT_PLIST="$(pwd)/ExportOptions.plist"

# Create ExportOptions.plist if not exists
if [ ! -f "$EXPORT_PLIST" ]; then
cat > "$EXPORT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>compileBitcode</key>
    <false/>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF
  echo "Created $EXPORT_PLIST - edit TEAM_ID"
fi

mkdir -p "$BUILD_DIR" "$IPA_DIR"

echo "=== Cleaning ==="
xcodebuild clean -project "$PROJECT_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release

echo "=== Archiving ==="
xcodebuild archive \
  -project "$PROJECT_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "=== Exporting IPA ==="
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$IPA_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

IPA_PATH="$IPA_DIR/$APP_NAME.ipa"
if [ -f "$IPA_PATH" ]; then
  echo "=== SUCCESS ==="
  echo "IPA built: $IPA_PATH"
  ls -lh "$IPA_PATH"
  echo ""
  echo "Install via:"
  echo "1. Apple Configurator 2 - drag IPA to iPhone 16+"
  echo "2. Xcode > Window > Devices and Simulators > drag IPA"
  echo "3. AltStore / SideStore"
  echo "4. TestFlight if you have developer account"
else
  echo "IPA not found. Check $IPA_DIR"
  ls -lh "$IPA_DIR"
fi
