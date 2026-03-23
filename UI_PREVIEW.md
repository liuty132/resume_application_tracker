# Job Application Tracker - UI Preview

## Menubar Icon & Popup

```
┌─────────────────────────────────────────┐
│ MacOS Menu Bar:                         │
│ [⏰] [📶] [🔋]  [💼] ← Job App Tracker  │
└─────────────────────────────────────────┘
                      ↓ Click
        ┌──────────────────────────────┐
        │  JOB APPLICATION TRACKER     │ 380px wide
        ├──────────────────────────────┤
        │                              │
        │ ┌────────────────────────┐   │
        │ │ Paste job URL…      [+]│   │ ← URLInputView
        │ └────────────────────────┘   │
        │                              │
        ├──────────────────────────────┤
        │ PENDING JOBS (Scroll area)   │
        │                              │
        │ ┌────────────────────────┐   │
        │ │ greenhouse.io          │   │ ← PendingJobRow
        │ │ https://jobs.greenh... │   │
        │ │                        │   │
        │ │ [✓ Apply]  [✗]        │   │
        │ └────────────────────────┘   │
        │                              │
        │ ┌────────────────────────┐   │
        │ │ linkedin.com           │   │
        │ │ https://www.linkedin..│   │
        │ │                        │   │
        │ │ [↻ Applying...]       │   │ ← Loading State
        │ └────────────────────────┘   │
        │                              │
        │ ┌────────────────────────┐   │
        │ │ workday.com            │   │
        │ │ https://workday.com... │   │
        │ │                        │   │
        │ │ [✓ Apply]  [✗]        │   │
        │ └────────────────────────┘   │
        │                              │
        │ [No pending jobs]            │ ← Empty State
        │ 💼                           │
        │                              │
        ├──────────────────────────────┤
        │ ⚠️ Network error             │ ← Error State (optional)
        └──────────────────────────────┘
           Max Height: 500px
           Min Width: 380px
```

## Component Details

### 1. URLInputView (Top Bar)
```
┌────────────────────────────────────┐
│ [Paste job URL…]    [Plus Icon]    │
│  ← TextField          ← Add Button  │
│  - Auto-validate URL               │
│  - Press Enter or click + to add    │
│  - Shows error if invalid          │
└────────────────────────────────────┘
```

### 2. PendingJobRow (Job Item)
```
┌──────────────────────────────────────┐
│ greenhouse.io                        │ ← Domain (Headline)
│ https://jobs.greenhouse.io/example   │ ← Full URL (Caption)
│                                      │
│ [✓ Apply]  [✗]                      │ ← Actions
│ Green button  Red button            │
│ .borderedProminent  .bordered       │
└──────────────────────────────────────┘

LOADING STATE:
┌──────────────────────────────────────┐
│ linkedin.com                         │
│ https://www.linkedin.com/jobs/...    │
│                                      │
│ [↻]  Applying...                     │ ← ProgressView
│      (centered)                      │
└──────────────────────────────────────┘

EMPTY STATE:
┌──────────────────────────────────────┐
│                                      │
│             💼                       │
│        No pending jobs               │
│       (Secondary text)               │
│                                      │
└──────────────────────────────────────┘
```

### 3. Error Handling (Bottom Bar)
```
┌──────────────────────────────────────┐
│ ⚠️ Invalid URL                       │ ← Red background
│    (Caption text, 2 lines max)       │
└──────────────────────────────────────┘

Error Messages:
├─ "Invalid URL"
├─ "Network error"
├─ "S3 upload failed"
└─ "Server error (500)"
```

## User Flow - Adding a Job

```
1. User clicks menubar icon
   → Popup opens (instantly)

2. User pastes URL into text field
   → Text field shows: "https://jobs.greenhouse.io/..."

3. User presses Enter or clicks [+]
   → URL validated with URLSession
   → PendingJob inserted into SwiftData
   → Job appears in list immediately (no network delay)
   → Text field clears

4. Job row shows: "✓ Apply" button (green, prominent)
```

## User Flow - Applying to a Job

```
1. User clicks "Apply" on a job row
   → Status changes to .applying
   → Row shows spinner: "[↻] Applying..."

2. Backend orchestrates 4 steps:
   Step 1: Fetch presigned URL (Lambda)
   Step 2: Get HTML via WKWebView
   Step 3: Upload to S3
   Step 4: Extract metadata + Save to RDS

3. After 2-5 seconds:
   → Status changes to .applied
   → Row disappears from list
   → Job now only in RDS
   → User sees next pending job (if any)

4. If error occurs:
   → Status reverts to .pending
   → Error message shows at bottom
   → User can retry Apply
```

## User Flow - Disregarding a Job

```
1. User clicks red [✗] button on job row
   → Job immediately deleted from SwiftData
   → Row disappears instantly
   → No network call
```

## Visual Hierarchy

```
SIZE:
├─ Title (Domain name)      → .headline
├─ Subtitle (Full URL)      → .caption (secondary)
├─ Button text              → .caption
└─ Error message            → .caption

COLORS:
├─ Apply button             → .green (system)
├─ Disregard button         → .red (system)
├─ Loading spinner          → .secondary (gray)
├─ Text                     → .primary / .secondary
└─ Error background         → .systemRed.opacity(0.1)

SPACING:
├─ Padding inside row       → 10pt
├─ Row margin               → 0pt (full width in list)
├─ Top bar padding          → 12pt
├─ List row separator       → hidden
└─ Corner radius            → 6pt
```

## Interactive States

```
BUTTON STATES:
├─ Normal     → [✓ Apply] with green tint
├─ Hover      → Button highlights (system behavior)
├─ Pressed    → Button darkens
└─ Disabled   → N/A (buttons always available)

LOADING STATE:
├─ ProgressView spinner    → Rotating circle
├─ Text "Applying..."      → Secondary gray
└─ Buttons hidden          → Replaced by spinner

ERROR STATE:
├─ Background color        → Light red
├─ Icon                    → ⚠️ exclamationmark.circle.fill
├─ Text                    → Error message (2 lines max)
└─ Auto-dismiss            → Can be clicked away
```

## Responsive Behavior

```
MIN WIDTH: 380pt
MAX HEIGHT: 500pt (popup)
WINDOW STYLE: .menuBarExtraStyle(.window)

- Window floats above all apps
- Position: anchored to menubar icon
- Always on top
- Click outside to close
- Persistent across menu switches
```

## Dark Mode Support

```
✓ Automatic via SwiftUI
├─ Text colors auto-invert
├─ Background colors invert
└─ System colors adapt

Preview: Light and Dark mode both supported
```

## Accessibility

```
✓ VoiceOver support (built-in)
├─ Buttons labeled: "Apply to {domain}"
├─ URL read as: "https://jobs.example.com"
└─ Loading state announced: "Applying"

✓ Keyboard navigation
├─ Tab between buttons
├─ Enter to submit URL
├─ Escape to close popup
└─ Space to activate button
```

## Performance Notes

```
LOCAL UI UPDATES:
├─ URL input     → Instant (TextField)
├─ Add job       → <50ms (SwiftData insert + @Query update)
├─ Disregard     → <50ms (delete + re-render)
└─ Status change → <50ms (binding update)

NETWORK-DEPENDENT:
├─ Apply flow    → 2-5s (presign + WKWebView + S3 + Lambda)
└─ Spinner shows → entire time, then row disappears
```

## Open in Xcode

The app is structured as a Swift Package. To open:

```bash
open /Users/liuty132/Desktop/resume_application_tracker/ApplicationTracker/
```

Or:
1. Open Xcode
2. File → Open
3. Select `ApplicationTracker` folder
4. Package.swift will load automatically
5. Select your Mac as target
6. Product → Run (⌘R)

**Note:** Before running, you need:
- Download `GoogleService-Info.plist` from Firebase
- Add to Xcode project
- Configure Firebase credentials
