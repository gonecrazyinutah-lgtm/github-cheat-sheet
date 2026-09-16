# Finding - iPhone 16+ Photo Recovery & USB Export

App does everything in order, now with automatic Google Takeout Groups import.

**App Name:** Finding

### Features In Order

1. **AUDIT** - Counts local, hidden, recently deleted, videos. Includes hidden assets.
2. **UNHIDE** - Unhides iPhone Hidden album via `PHAssetChangeRequest.isHidden = false`. Shows instructions for Google Archive.
3. **ORGANIZE** - Sorts by date and type.
4. **GOOGLE TAKEOUTS AUTO GROUP** - NEW - Select multiple Takeout .zip files, auto-detects email from `archive_browser.html`, groups by `account/year/album`, copies to USB with hash verification.
5. **EXPORT TO USB** - Direct to USB-C drive via Files picker. Creates `iPhone16_Photos/`, `iPhone16_Videos/`, `Organized_By_Date/`, `GoogleTakeout_Groups/`.

### Build IPA

#### Option A: On Mac (Signed IPA for your iPhone 16+)
```bash
cd iPhone16PhotoRecoveryApp
chmod +x build_ipa.sh
./build_ipa.sh
# Edit ExportOptions.plist with your TEAM_ID first
```
Or manual: Xcode > Product > Archive > Distribute App > Ad Hoc > Export IPA

Install: Apple Configurator 2 > drag IPA to iPhone, or Xcode > Devices > drag IPA.

#### Option B: GitHub Actions (Unsigned IPA for testing)
Push to GitHub, workflow `.github/workflows/build-ipa.yml` builds on macOS-14 runner.
Actions tab > Build Finding IPA > Download artifact `Finding-IPA` > `Finding-unsigned.ipa`

Unsigned IPA needs AltStore/SideStore to install.

#### Option C: Direct Run (No IPA needed)
Xcode > Run on your iPhone 16+ via USB-C cable.

### How Google Takeout Groups Import Works

1. On computer, download Takeouts: takeout.google.com > Select Google Photos > Create Export (do for each Google account on iPhone)
2. Save zips to iCloud Drive or directly to USB drive
3. On iPhone, open Finding app:
   - Step 4 > Select Takeout Zips/Folders > pick multiple zips from Files app
   - App auto-detects:
     - Email from `archive_browser.html`
     - Year from folder name "Photos from 2023"
     - Album from parent folder
   - Creates: `USB/GoogleTakeout_Groups/email/year/album/IMG_xxx.jpg`
   - Writes `TAKEOUT_GROUPS_SUMMARY.txt` + `TAKEOUT_VERIFICATION_HASHES.txt`

Supports multiple accounts at once - e.g., select `takeout-john@gmail.com.zip` + `takeout-jane@gmail.com.zip` together, it groups separately.

### Project Structure
- `PhotoRecoveryApp.swift`
- `ContentView.swift` - 5-step UI
- `Managers/PhotoLibraryManager.swift`
- `Managers/USBExportManager.swift`
- `Managers/GooglePhotosManager.swift`
- `Managers/TakeoutImportManager.swift` - NEW automatic grouping
- `Models/MediaItem.swift`

### Required Packages
Xcode > File > Add Package:
- https://github.com/google/GoogleSignIn-iOS
- https://github.com/weichsel/ZIPFoundation (for unzipping Takeouts on device)

### Info.plist
Use `Info.plist.template` - includes NSPhotoLibraryUsageDescription for Finding.

### iPhone 16+ Specific
- USB-C direct - no adapter needed for USB-C drives
- For USB-A drives, use Apple USB-C to USB-A adapter
- Format drive exFAT for 4GB+ videos
- Files app shows drive in sidebar automatically
