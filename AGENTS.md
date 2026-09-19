# Reflex: Minimal macOS Intent Router

## Product goal

Build a small native macOS app named **Reflex** that becomes the handler for `http` and `https` links and opens each link in the most appropriate configured browser target.

Reflex must be selected as the macOS default web browser to receive normal external web-link clicks system-wide. Treat checking and guiding this setup as part of the product, not as an undocumented prerequisite.

A target is a browser plus an optional browser profile, for example:

- Safari Personal
- Chrome Work (`--profile-directory=Profile 1`)
- Chrome Personal (`--profile-directory=Default`)
- Comet
- Dia
- Helium
- Edge

Reflex sends a privacy-reduced description of the link and local context to the TypeSafe Jev API. Jev chooses one of the enabled targets. Reflex auto-routes only when confidence is high; otherwise it shows a compact chooser with Jev's suggestion highlighted.

This is deliberately a minimal app. Prefer the smallest native implementation that satisfies the acceptance criteria. Do not introduce abstractions for hypothetical future features.

## Non-goals

Do not add any of the following unless a later task explicitly asks for it:

- User accounts, cloud sync, analytics, telemetry, or a backend
- A general automation or plugin system
- File, notification, email, calendar, or download routing
- A natural-language chat interface
- An LLM fallback
- A database or link history
- Automatic rule learning
- Support for operating systems other than macOS

## Technical constraints

- Native macOS app using Swift and SwiftUI
- Target macOS 14 or newer
- Use the current stable Swift language mode supported by the installed Xcode
- Prefer Apple frameworks. Add no third-party dependency unless it is essential and documented in `README.md`
- Use `URLSession` for the TypeSafe API
- Use Keychain Services for the API key. Never store it in `UserDefaults`, source code, logs, fixtures, or screenshots
- Use `UserDefaults` for non-secret preferences
- Use `OSLog` for diagnostics, with privacy annotations. Never log the full incoming URL, query values, API key, authorization header, or API response body
- Keep networking, routing policy, URL sanitization, and browser launching testable without SwiftUI
- The app must remain useful when Jev is unavailable
- Discover browser applications through Launch Services and `NSWorkspace`; keep only Safari, Chrome, Dia, Comet, Helium, Edge, Phi, Zen, and Firefox

## Repository working rules

- Before changing code, inspect the repository and existing conventions
- Keep each change scoped to the current phase
- Do not rewrite unrelated code or configuration
- Do not claim a phase is complete until its tests and acceptance criteria pass
- After meaningful changes, run the narrowest relevant tests; before handoff, run the full test suite and build
- If Xcode or a required signing capability is unavailable, complete all work that can be verified and report the exact remaining manual step
- When requirements are ambiguous, choose the simpler behavior and record the assumption in `README.md`

## Core user flow

1. On first launch, Reflex discovers installed applications registered to open HTTP or HTTPS URLs and pre-populates its target list.
2. Reflex checks whether it is the current default handler for both HTTP and HTTPS and guides the user through making it the default browser when needed.
3. The user clicks an `http` or `https` link in another app.
4. macOS sends the URL to Reflex.
5. Reflex captures the source application's bundle identifier when macOS makes it available.
6. Reflex sanitizes the URL before making a network request.
7. Reflex asks Jev to select exactly one enabled target.
8. If the result meets the auto-route policy, Reflex opens the original, unmodified URL in that target.
9. Otherwise, Reflex displays a keyboard-accessible chooser. The suggested target is selected by default when a suggestion exists.
10. If the request fails, times out, or returns invalid data, Reflex immediately falls back to the chooser. The URL must never be lost.

## Privacy boundary

The original URL exists only in memory long enough to route it. Do not persist it.

The default Jev state may include:

- URL scheme
- Host
- Path
- Source application bundle identifier, if known
- A list of enabled targets and each target's user-authored purpose

Strip the fragment completely. Strip query parameter values. Supplying query parameter names is allowed only when useful for routing. Never send clipboard contents, page contents, browser history, cookies, local file paths, or window text.

The launcher must always receive the original URL, not the sanitized URL.

## First-launch browser discovery

Reflex should configure the initial target list automatically instead of requiring users to type browser bundle identifiers.

- Ask Launch Services for every installed application capable of opening representative `http` and `https` URLs. Prefer public `NSWorkspace` APIs such as `urlsForApplications(toOpen:)` rather than scanning fixed filesystem directories.
- Take the union of HTTP and HTTPS results, resolve each application bundle, and deduplicate by bundle identifier. If an application has no bundle identifier, deduplicate by standardized application URL.
- Exclude Reflex itself so it can never appear as a destination and create a routing loop.
- Limit discovery to Safari, Chrome, Dia, Comet, Helium, Edge, Phi, Zen, and Firefox. Remove other registered handlers from the target list.
- For each new browser, pre-populate its display name, bundle identifier, application icon, enabled state, and a neutral editable purpose such as `General browsing in <browser name>`.
- Enable newly discovered browsers by default. The first-launch setup must let the user disable unwanted targets and edit each purpose before completing setup.
- Browser purpose is user intent, not something Reflex can infer reliably. Do not label a browser as work or personal without the user's input.
- Discover Chromium profile names and directory identifiers for Chrome, Edge, Comet, Dia, Helium, and Phi. Read only `profile.info_cache` keys and each entry's `name` from the browser's `Local State` file. Do not read account details, history, cookies, or page data.
- A browser with more than one profile becomes one target for each profile, named `Browser (Profile)`. A browser with a single profile stays one target named `Browser`. A scan gives the plain target the first profile and keeps its purpose.
- macOS can deny access to a browser's data directory. Report the affected browser and offer the privacy settings. Profile targets come from a scan only.
- Add a **Rescan Browsers** action in Settings. A rescan merges new discoveries into the existing target list without overwriting user-authored names, purposes, enabled states, or profile settings.
- If a previously configured application is no longer installed, retain its configuration but mark it unavailable and exclude it from Jev choices until it becomes available again.
- Do not continuously watch the filesystem for browser changes in the MVP. Scan on first launch, when Settings opens, and when the user explicitly requests a rescan.

## Default-browser setup

Receiving external HTTP and HTTPS link clicks requires Reflex to be the macOS default web browser.

- Register Reflex as an eligible handler for both URL schemes in the app target configuration.
- Determine the current default application for both HTTP and HTTPS through public Launch Services or `NSWorkspace` APIs. Consider setup complete only when both schemes resolve to Reflex.
- Show the current status prominently during first-launch setup and in Settings.
- Provide a **Make Reflex Default Browser** action. Use the supported `NSWorkspace` default-application API where available and allow macOS to present any required user confirmation.
- If macOS does not allow the change programmatically, open the relevant System Settings page and show concise manual instructions. Never use private APIs or silently rewrite Launch Services databases.
- Recheck status when Reflex becomes active because the user can change the default browser while the app is running.
- Do not block manual testing or Settings access when Reflex is not the default. Explain that automatic interception will remain inactive until setup is completed.
- Document the boundary clearly: links opened by external applications normally reach the default handler, while navigation inside an existing browser, embedded web views, and non-HTTP(S) deep links may bypass Reflex.

## Minimal data model

Use simple `Codable` value types unless a platform API requires otherwise.

```swift
struct BrowserTarget: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bundleIdentifier: String
    var purpose: String
    var chromiumProfileDirectory: String?
    var isEnabled: Bool
}

struct RoutingContext: Codable, Equatable {
    var scheme: String
    var host: String
    var path: String
    var queryParameterNames: [String]
    var sourceApplicationBundleIdentifier: String?
}

struct RouteDecision: Equatable {
    var targetID: UUID
    var confidence: Double
}
```

Keep a stable mapping from Jev choice keys to target IDs. Do not use user-visible names as internal identifiers because names can collide or change. Choice keys may use a request-local format such as `target_0`, `target_1`, and so on.

## Jev integration

Use TypeSafe Jev through the OpenRouter decisions endpoint and the TypeSafe request shape:

```http
POST https://openrouter.ai/api/alpha/decisions
Authorization: Bearer <OPENROUTER_API_KEY>
Content-Type: application/json
```

```json
{
  "state": {
    "link": {
      "scheme": "https",
      "host": "github.com",
      "path": "/acme/backend/pull/123",
      "queryParameterNames": []
    },
    "sourceApplicationBundleIdentifier": "com.tinyspeck.slackmacgap",
    "targets": [
      {
        "key": "target_0",
        "name": "Chrome Work",
        "purpose": "Work accounts, GitHub, Linear, and company links"
      },
      {
        "key": "target_1",
        "name": "Safari Personal",
        "purpose": "Personal browsing, shopping, and personal accounts"
      }
    ]
  },
  "model": "~typesafe/jev-latest",
  "questions": {
    "target": {
      "type": "choice",
      "instructions": "Which enabled browser target is the best place to open `link`, considering the source application and each target's stated purpose?",
      "criteria": {
        "target_0": "Chrome Work: Work accounts, GitHub, Linear, and company links",
        "target_1": "Safari Personal: Personal browsing, shopping, and personal accounts"
      }
    }
  }
}
```

Decode only the fields the app needs from `answers.target`: `choice`, `probabilities`, and `confidence`. Treat an unknown choice key, missing confidence, non-finite confidence, or confidence outside `0...1` as an invalid response.

Jev questions must stay atomic. For the MVP, make one `Choice` decision. Do not add separate work/personal, sensitivity, or urgency questions unless actual product behavior consumes them.

Use an ephemeral `URLSessionConfiguration`. Set a short request timeout, initially 1.5 seconds. Networking errors must not block the main actor or leave the app stuck.

## Routing policy

Use deterministic local policy after Jev responds:

- Confidence at or above `0.85`: open the selected target automatically
- Confidence below `0.85`: show the chooser with the selected target highlighted
- No API key, timeout, network error, non-2xx response, decoding error, or invalid answer: show the chooser
- If exactly one target is enabled, open it directly without calling Jev
- If no targets are enabled, show setup instead of discarding the URL

Keep the threshold in preferences, but a settings UI for changing it is optional in the MVP. Clamp persisted values to `0...1` when reading them.

## Browser launching

- Verify that a configured bundle identifier resolves to an installed application before presenting it as available
- For a target without a profile, use `NSWorkspace` APIs to open the original URL with that application
- For a Chromium target with `chromiumProfileDirectory`, launch a new app instance through `/usr/bin/open` with an argument array equivalent to `-na <application> --args --profile-directory=<profile> <url>`
- Never build a shell command string. Use `Process` with explicit executable URL and arguments so URL contents cannot become shell syntax
- Validate profile directory values as plain profile identifiers and reject control characters
- If launching the chosen target fails, keep the original URL available and show the chooser with a visible, non-blocking error
- Do not send the URL back through the system default handler because Reflex may be the default handler and create a loop

## App shape

Use a menu bar app with two small windows/panels:

1. **Chooser**
   - Opens as a compact borderless panel at the pointer, next to the clicked link
   - Displays enabled, installed targets with the application icon and a number key badge
   - Highlights Jev's suggestion when present
   - Does not show the pending link or host
   - Supports arrow keys, Return to open, number shortcuts, and Escape to cancel
   - The pointer selects the row below it, the same as the arrow keys
   - Shows a small offline/error indicator when Jev was unavailable, without exposing raw API errors

2. **Settings**
   - Opens when the user starts Reflex without a link, and from the menu bar item
   - Reflex quits when the settings window closes, because macOS starts it again for the next link
   - A switch for the menu bar item, stored in `UserDefaults`
   - API key field with Save and Remove actions
   - Target list with name, application, purpose, optional Chromium profile directory, and enabled state
   - Drag a target by its handle to set the order. The chooser shows the targets and numbers the keys in this order
   - Targets of one browser appear in one group
   - Detected-browser availability and a Rescan Browsers action
   - Current HTTP/HTTPS default-handler status and a Make Reflex Default Browser action
   - A short privacy note describing exactly what is sent to TypeSafe
   - Instructions for selecting Reflex as the macOS default web browser if macOS requires manual confirmation in System Settings

Keep visual design plain, native, and compact. Correct routing and safe fallback matter more than animation or custom styling.

## URL handler requirements

- Register the app for both `http` and `https` URL schemes in the app target configuration
- Handle URLs delivered at cold launch and while the app is already running
- Support one pending URL at a time for the MVP
- If another URL arrives while the chooser is open, queue it in memory and process it next. A small FIFO is sufficient; do not persist it
- Reject non-HTTP(S) input without opening it

## Suggested source layout

Use the repository's existing layout if present. For a new project, prefer:

```text
Reflex/
  App/
    ReflexApp.swift
    AppDelegate.swift
  Models/
    BrowserTarget.swift
    RoutingContext.swift
  Routing/
    URLSanitizer.swift
    RoutingPolicy.swift
    LinkRouter.swift
  Services/
    JevClient.swift
    KeychainStore.swift
    BrowserLauncher.swift
  Views/
    ChooserView.swift
    SettingsView.swift
ReflexTests/
```

This is guidance, not a mandate. Do not create one-file types that add no clarity.

## Delivery phases

### Phase 1: Local router without Jev

Implement the smallest working macOS app that receives web URLs, presents the chooser, and launches the selected installed browser target.

Acceptance criteria:

- The project builds from a clean checkout
- The app registers as an `http` and `https` handler
- First launch discovers all applications that Launch Services reports as capable of opening HTTP or HTTPS URLs
- Discovery excludes Reflex, deduplicates applications, and keeps only the supported browser list
- The initial setup pre-populates discovered browsers and lets the user edit their purposes or disable them
- Reflex reports whether it is the default handler for both HTTP and HTTPS
- The Make Reflex Default Browser action uses supported APIs or opens the appropriate System Settings page with instructions
- URLs are handled at cold launch and while running
- The chooser can open the original URL in Safari, Chrome, or Dia when installed and configured
- A configured Chromium profile is passed as an argument array, never through a shell
- A failed launch leaves the URL recoverable in the chooser
- Non-HTTP(S) URLs are rejected

### Phase 2: Jev decision path

Add Keychain-backed credentials, URL sanitization, the Jev client, response validation, and confidence-based routing.

Acceptance criteria:

- The API key never appears in repository files or `UserDefaults`
- The outgoing state contains only fields allowed by the privacy boundary
- Query values and fragments are absent from the encoded request
- One Jev `Choice` question contains every enabled and installed target
- A valid response at or above the threshold auto-opens the selected target
- A low-confidence, failed, timed-out, non-2xx, or malformed response opens the chooser
- Exactly one enabled target bypasses Jev
- All network work occurs off the main actor; UI state changes occur on the main actor

### Phase 3: Minimal settings and hardening

Add the settings UI, keyboard behavior, queueing, and final verification.

Acceptance criteria:

- The user can add, edit, enable, disable, and remove targets
- Rescanning adds newly installed browsers without overwriting existing target customization
- Removed browsers remain configured but unavailable and are excluded from Jev choices
- The user can save and remove the API key
- The chooser is fully usable by keyboard and VoiceOver labels exist for interactive controls
- Multiple incoming URLs are processed in FIFO order without persistence
- No sensitive values appear in logs during a manual routing test
- `README.md` documents setup, default-browser selection, the Jev privacy boundary, local build steps, test steps, and known limitations

## Required tests

At minimum, add unit tests for:

- URL sanitization removes fragments and query values while preserving allowed fields
- Routing policy at confidence values below, equal to, and above `0.85`
- Single-target bypass and zero-target setup behavior
- Jev request encoding uses stable request-local choice keys
- Jev response decoding and rejection of malformed or unknown choices
- Timeout and network failure fall back to chooser behavior
- Profile identifier validation
- Browser discovery union, deduplication, and self-exclusion
- Discovery merge preserves user-authored target configuration
- Default-handler status requires Reflex to own both HTTP and HTTPS schemes
- FIFO handling of multiple incoming URLs

Use dependency injection only at real boundaries: HTTP transport, credential storage, workspace/application launching, and preferences. Avoid a large framework or container.

## Manual verification checklist

Before final handoff, verify and report results for:

1. Build the app and run all tests.
2. Confirm that each installed supported browser appears after a rescan, other handlers do not appear, and Reflex does not appear as a target.
3. Edit an existing target, rescan, and confirm that the customization remains intact.
4. Complete the default-browser flow and confirm Reflex is the handler for both HTTP and HTTPS.
5. Configure at least two installed targets with distinct purposes.
6. Open a GitHub or Linear link from a work app and confirm high-confidence routing or highlighted suggestion.
7. Open a clearly personal link and confirm the expected target.
8. Disable networking and confirm the chooser appears promptly.
9. Use a URL containing query values, a fragment, spaces, and shell metacharacters; confirm the original URL opens correctly and none of those values are interpreted as command syntax.
10. Remove the API key and confirm the app remains usable.
11. Send two links while the chooser is open and confirm FIFO processing.

## Definition of done

The MVP is done when all phase acceptance criteria pass, the repository contains no secrets, the full test suite and a release build succeed, and the README is sufficient for another developer to configure and run the app without undocumented steps.

Do not expand the feature set while closing bugs. Record attractive follow-up ideas in a short `Future work` section in `README.md` instead of implementing them.

## Authoritative references

When the TypeSafe API and this file disagree, verify the current behavior in the official documentation before changing integration code:

- Quick start: <https://docs.typesafe.ai/introduction/quickstart>
- Question primitives: <https://docs.typesafe.ai/primitives>
- Confidence: <https://docs.typesafe.ai/confidence>
- OpenRouter TypeSafe models: <https://openrouter.ai/typesafe>

Do not silently adapt to an API change. Update request/response fixtures, tests, and this document together.
