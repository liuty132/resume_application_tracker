---
name: project_architecture
description: Key file locations, API contract shapes, known TODOs, SwiftData models, and architectural decisions for the Job Application Tracker
type: project
---

## Key File Locations

- SwiftUI app root: `/ApplicationTracker/ApplicationTrackerApp.swift`
- State: `/ApplicationTracker/AppState.swift` — uses `@Observable`, holds `isLoggedIn`, `currentUserID`, `presentingWindow`, `urlInput`
- SwiftData model: `/ApplicationTracker/Models/PendingJob.swift` — fields: `id`, `url`, `addedAt`, `statusValue`, `cachedHTMLPath`
- Auth: `/ApplicationTracker/Services/AuthService.swift` — `actor`, wraps Firebase+GIDSignIn; `getCurrentUser()` returns `FirebaseAuth.User?`
- API service: `/ApplicationTracker/Services/JobAPIService.swift` — `actor`; `applyJob(_:modelContext:currentUserID:)`, `getJobs() -> [JobRecord]`
- Web fetcher: `/ApplicationTracker/Services/WebViewFetcher.swift` — `@MainActor`; `fetchHTML(from:)`, `fetchAndCacheHTML(url:jobID:userID:) -> String`, static `cachedHTMLPath(jobID:userID:) -> URL`
- Views: `MenuBarView`, `URLInputView`, `PendingJobRow`, `DashboardView` all in `/ApplicationTracker/Views/`
- Lambda handlers: `/backend-lambda/src/handlers/` — `getJobs.ts`, `postJob.ts`, `presign.ts`
- Drizzle schema: `/backend-lambda/src/db/schema.ts`
- Terraform infra: `/infra/`

## API Contract Shapes

### GET /presign
Response: `{ "uploadURL": String, "s3Key": String }`

### POST /jobs
Request: `{ "url": String, "s3Key": String }`
Response: 201 on success

### GET /jobs
Response: `[{ "id": Int, "url": String, "title": String?, "company": String?, "status": String, "created_at": String }]`
Note: Lambda returns snake_case; Swift decoder uses `.convertFromSnakeCase` so `JobRecord.createdAt` maps from `created_at`.

## SwiftData Model: PendingJob

Fields: `id: UUID`, `url: String`, `addedAt: Date`, `statusValue: String`, `cachedHTMLPath: String?`
Status enum: `PendingJobStatus` — `.pending`, `.applying`, `.applied`, `.disregarded`

## HTML Caching Architecture

Cache path pattern: `<cachesDir>/com.example.ApplicationTracker/<userID>/<jobID>.html`
- Pre-fetch triggered in `URLInputView.addJob()` via `Task.detached` after SwiftData save succeeds
- Pre-fetch skipped if `appState.currentUserID` is nil (user not logged in)
- `applyJob` reads from cache via `resolveHTML(jobURL:cachedPath:)` helper; falls back to live fetch on miss/corruption
- On successful apply: cache file deleted, `job.cachedHTMLPath` set to nil

## Known TODOs

- S3 upload retry logic NOT YET implemented in `JobAPIService.uploadHTMLToS3()` — flag and implement when touched
- `baseURL` in `JobAPIService.swift` is a placeholder (`https://api.applicationtracker.example.com`) — replace with real API Gateway URL after `serverless deploy`
- Run `npx drizzle-kit migrate` from `/backend-lambda` before first deploy

## Actor/Concurrency Notes

- `JobAPIService` is an `actor` — PendingJob `@Model` properties must be read inside `MainActor.run { }` blocks
- `WebViewFetcher` is `@MainActor` — calling its methods from an actor context is safe; Swift runtime hops automatically
- `AuthService` is an `actor` — `getCurrentUser()` requires `await` from outside actor context
- `AppState` uses `@Observable` (not `@ObservableObject`) — injected via `.environment(appState)` not `@EnvironmentObject`

## Dashboard Window

- Scene ID: `"dashboard"` — opened via `openWindow(id: "dashboard")` from `MenuBarView`
- `DashboardView` uses `NavigationSplitView` with sidebar width `min:180 ideal:200 max:220`
- Sidebar has `FilterSelection` enum (all/pending/applied/disregarded) with icon, accentColor, and count badges
- Detail view uses `LazyVStack` inside `ScrollView`; sections for pending (SwiftData) and applied (Lambda/RDS)
- Applied jobs fetched from Lambda via `JobAPIService.shared.getJobs()` on `.task` and on filter change
- Toolbar has a Refresh button; loading/error/empty states are fully handled
- `StatusBadge` is a file-private `View` in `DashboardView.swift` — colored pill for any status string
- `formattedDate` in `DashboardView` parses ISO-8601 with and without fractional seconds

## PendingJobRow

- Reads `appState.currentUserID` via `@Environment(AppState.self)` to pass to `JobAPIService.applyJob`
- Shows hover highlight via `onContinuousHover` + `@State private var isHovered`
- Status dot: orange=pending, blue=applying; Disregard deletes the SwiftData record

## MenuBarView

- Header uses `labelStyle(.iconOnly)` for action buttons (Dashboard / Logout / Quit)
- Job list uses `LazyVStack` inside `ScrollView` with `.frame(maxHeight: 300)`
- Empty state shown when `pendingJobs.isEmpty` — tray icon + descriptive text
- Added `import FirebaseAuth` — required to access `.uid` on `FirebaseAuth.User` returned by `AuthService.getCurrentUser()`

## currentUserID Lifecycle

- Set after `signInWithGoogle` succeeds in `MenuBarView.login()`
- Set on `.onAppear` if `isUserLoggedIn()` returns true (session restore path)
- Cleared in `MenuBarView.logout()`
- Propagated to `WebViewFetcher` and `JobAPIService` via `appState.currentUserID`
