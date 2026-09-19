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

## Profiles

A scan reads the local profile list of Chrome, Edge, Comet, Dia, Helium, and Phi. Reflex reads the profile directory and profile metadata from each browser's `Local State` file. It does not read history, cookies, or page data.

- A browser with more than one profile becomes one target for each profile, for example **Google Chrome (Personal)** and **Google Chrome (Slumber)**.
- A browser with a single profile stays one target, named after the browser.
- The name normally comes from the label you gave the profile. Edge often keeps a placeholder such as `Profile 2`. In that case, Reflex can use the Edge account first and last name, Google account display name, or user name from the same profile record. The user name can be an email address.
- The resolved profile name becomes part of the target name. When the target is enabled and an OpenRouter API key is configured, Reflex sends that target name to OpenRouter for the Jev decision. Thus, an Edge account name or user name can leave the Mac.
- A rescan adds a new profile and keeps your names, purposes, order, and switches. It replaces only a name Reflex built from a placeholder.
- Safari, Firefox, and Zen have no profile support, because they do not accept the Chromium profile argument.

macOS keeps browser data behind Full Disk Access. Chrome and Edge are the usual ones it blocks. The **Profile access** section in Settings shows the state:

- It names the browsers macOS blocks.
- It says what Reflex reads: the profile list and, for an Edge placeholder, the account-name fields described above. Reflex reads no history, cookies, or page data.
- **Open Full Disk Access** opens the list in System Settings. Add Reflex, switch it on, start Reflex again, and select **Rescan Browsers**.

macOS gives no way for an application to ask for this access in a dialog, so Reflex can only open that list for you.

Without the access, each blocked browser stays one target. Reflex does not invent profiles.

Select **Make Reflex Default Browser**. Setup is complete only when Reflex is the handler for both HTTP and HTTPS. If macOS does not allow the direct change, Reflex opens System Settings. In **Desktop & Dock**, set **Default web browser** to Reflex.

To use automatic selection, paste an OpenRouter API key into Settings and select **Save**. Reflex saves the key in macOS Keychain. It does not save the key in repository files or `UserDefaults`.

External applications normally send links to the default browser. Navigation inside an existing browser, embedded web views, and non-HTTP(S) deep links can bypass Reflex. Reflex does not block Settings or manual tests when another default browser is active.

## The chooser

When Reflex needs your decision, it opens a small panel at the pointer, next to the link you clicked. Each row shows the browser name, a number key badge, and the application icon. The suggested target is selected and has a sparkle mark.

- Press a number key to open that target.
- Use the arrow keys and Return to open the selected target.
- Move the pointer across the list to select a row, the same as the arrow keys. Click to open it.

Reflex has no Dock icon while it routes a link. A link shows the panel and nothing else. The Dock icon appears only while the settings window is open.

The chooser uses the target order from Settings. Drag a target by the handle at the left of its row to change the order. The number badge shows the key that opens that target. A disabled or unavailable target has no number.
- Press Escape, or click outside the panel, to cancel the link.
- Select the gear at the bottom right to open Settings. This cancels the link, the same as Escape.

The chooser shortcut uses **Option + click** by default. Settings lets you change the modifier to Control, Shift, Command, or Fn. Hold the selected modifier while you click a link to skip automatic selection. The chooser opens with every target, even when Jev is sure and even when only one target is enabled. This is also the way back to Settings when the menu bar item is hidden: the chooser has the gear.

The source application can use a modified click before it sends the link to macOS. For example, Control-click often opens a context menu and Command-click often opens a browser tab. Reflex can show the chooser only when the source application sends the link to Reflex.

The footer line shows the state of automatic selection: **active** while an API key is configured and Jev answers, **unavailable** after a failure or without a key, and **skipped** when you held the selected modifier.

The panel does not show the link or its host.

## Settings and quitting

Start Reflex without a link, from the Applications folder or the Dock, and Settings opens. When the menu bar item is on, closing Settings removes the Dock icon and keeps Reflex running in the menu bar. When the menu bar item is off, closing Settings quits Reflex unless a link is pending.

The menu bar item is a switch in Settings. Turn it off to keep the menu bar clean. macOS starts Reflex again when it receives a link, and you still reach Settings by starting Reflex again.

## Purposes, which decide the routing

Jev reads the purpose text of each target. It is the strongest signal, so write it for the targets you care about. Reflex leaves the field empty and never invents one.

Write the accounts, sites, and work behind a target:

- `Slumber company work: GitHub, Linear, company mail, deploy dashboards`
- `Personal Google account: shopping, YouTube, personal mail, travel`
- `Acadia university account: Microsoft 365, Teams, coursework`
- `Banking, government sites, and Apple services`

Measured against a list of twelve targets:

| Purposes | Link | Confidence |
| --- | --- | --- |
| `General browsing in ...` everywhere | a work pull request, opened from Slack | 0.26, chooser |
| written as above | the same link | 0.99, opens by itself |
| written for four targets only | the same link | 1.00, opens by itself |
| written as above | a Teams meeting from Outlook, two work accounts | 0.72, chooser with the suggestion |

You do not need a purpose for every target. Describe the ones that matter, and leave the rest empty.

## Privacy

Original URLs stay only in memory while they wait for routing. Reflex does not save link history or URL data. It does not log incoming URLs, API keys, authorization headers, or API response bodies.

For Jev selection, Reflex sends only:

- The URL scheme, host, and path
- Query parameter names without their values
- The source application bundle identifier when macOS provides it, and the application name it resolves to
- Enabled and available target names and user-written purposes. A target name can contain an Edge account name or user name found during profile discovery.

The URL fragment is removed. The browser launcher always receives the original URL. Reflex sends the reduced state to the OpenRouter decisions endpoint with the `~typesafe/jev-latest` model. If the request fails or does not return a valid answer in 1.5 seconds, Reflex shows the chooser.

## Current limits

- Profile discovery supports installed Chromium-based targets with a recognized local data directory.
- Reflex supports one chooser selection at a time. More incoming links wait in memory in FIFO order.
- A Chromium profile value is treated as a profile identifier. Control characters are not allowed.
- The target name and purpose are editable. The browser application is identified by its discovered bundle identifier.
