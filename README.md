# Reflex

Reflex is a small native macOS link router. It receives HTTP and HTTPS links, keeps them in an in-memory FIFO, and opens each original URL in an installed browser target. It can use TypeSafe Jev through OpenRouter to select a target.

## Requirements

- macOS 14 or newer
- Xcode with the current stable Swift language mode

## Build and test

Open `Reflex.xcodeproj` in Xcode, select the Reflex scheme, and run the app. You can also use these commands:

```sh
xcodebuild -project Reflex.xcodeproj -scheme Reflex -destination 'platform=macOS' build
xcodebuild -project Reflex.xcodeproj -scheme Reflex -destination 'platform=macOS' test
```

Local builds use Apple Development signing for team `FA8NWUSJ95` and the hardened runtime. This gives Reflex a stable signing identity for Keychain access. If Keychain asks after a newly signed build replaces an older ad-hoc build, select **Always Allow** once.

## Direct distribution

Reflex uses Developer ID distribution outside the Mac App Store. Apple requires a **Developer ID Application** certificate, hardened runtime, a secure timestamp, notarization, and a stapled ticket. The existing **Apple Distribution** certificate is not valid for this workflow.

Before the first production release:

1. Create and install a **Developer ID Application** certificate for team `FA8NWUSJ95` in the Apple Developer account.
2. Save notarization credentials in Keychain. This command asks for the Apple ID and app-specific password without saving them in the repository:

   ```sh
   xcrun notarytool store-credentials ReflexNotary --apple-id YOUR_APPLE_ID --team-id FA8NWUSJ95
   ```

3. Run the distribution workflow:

   ```sh
   NOTARY_PROFILE=ReflexNotary ./Scripts/distribute.sh
   ```

The script runs all tests, creates a Release archive with Developer ID signing, verifies the signature, submits a ZIP to Apple with `notarytool`, staples and validates the ticket, checks the app with Gatekeeper, and writes the final ZIP and SHA-256 digest under `dist/`. It stops before building if the required certificate or Keychain profile name is missing. It does not store signing secrets in the repository.

## First setup

Reflex scans the applications that Launch Services reports for representative HTTP and HTTPS URLs. It keeps Safari, Chrome, Dia, Comet, Helium, Edge, Phi, Zen, and Firefox. It removes other handlers from the target list. It enables new supported browsers and gives each one a neutral purpose. Open Settings to disable unwanted targets, edit names and purposes, or select **Rescan Browsers**.

Select **Rescan Profiles** to find local Chromium profile names and directory identifiers for Chrome, Edge, Comet, Dia, Helium, and Phi. Reflex reads only those two fields from each browser's `Local State` file. It does not read account details, history, cookies, or page data. A discovered name stays local until you select **Add** to create a separate editable routing target. Safari, Firefox, and Zen profile discovery is not supported because they do not use the same Chromium launch argument.

macOS can deny access to some browser data directories. Reflex reports the affected browser and keeps the manual profile directory field available. Reflex does not ask for Full Disk Access.

Select **Make Reflex Default Browser**. Setup is complete only when Reflex is the handler for both HTTP and HTTPS. If macOS does not allow the direct change, Reflex opens System Settings. In **Desktop & Dock**, set **Default web browser** to Reflex.

To use automatic selection, paste an OpenRouter API key into Settings and select **Save**. Reflex saves the key in macOS Keychain. It does not save the key in repository files or `UserDefaults`.

External applications normally send links to the default browser. Navigation inside an existing browser, embedded web views, and non-HTTP(S) deep links can bypass Reflex. Reflex does not block Settings or manual tests when another default browser is active.

## Privacy

Original URLs stay only in memory while they wait for routing. Reflex does not save link history or URL data. It does not log incoming URLs, API keys, authorization headers, or API response bodies.

For Jev selection, Reflex sends only:

- The URL scheme, host, and path
- Query parameter names without their values
- The source application bundle identifier when macOS provides it
- Enabled and available target names and user-written purposes

The URL fragment is removed. The browser launcher always receives the original URL. Reflex sends the reduced state to the OpenRouter decisions endpoint with the `~typesafe/jev-latest` model. If the request fails or does not return a valid answer in 1.5 seconds, Reflex shows the chooser.

## Current limits

- Profile discovery supports installed Chromium-based targets with a recognized local data directory.
- Reflex supports one chooser selection at a time. More incoming links wait in memory in FIFO order.
- A Chromium profile value is treated as a profile identifier. Control characters are not allowed.
- The target name and purpose are editable. The browser application is identified by its discovered bundle identifier.
