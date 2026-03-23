# Project: Job Application Tracker for MacOS

## Context & Goals
A macOS MenuBar app to queue and track job applications.
- **Core Loop:** URL Input -> Queue -> Apply/Disregard decision -> RDS/S3 Storage.
- **Primary Tech:** SwiftUI (macOS), PostgreSQL (RDS), AWS Lambda, S3.

## Main Dashboard View [PLANNED]
- **View Pattern:** NavigationSplitView (Sidebar for status filters, Detail for job list).
- **Data Fetching:** Fetch from `/jobs` endpoint (Lambda -> RDS).
- **Batch Actions [PLANNED]:** Use Swift's `EditMode` to allow multiple selection for `DELETE` requests.
- **S3 Integration [PLANNED]:** Selecting a job should provide a "View Original Posting" button that opens the S3 HTML in a WebView.

## Tech Stack & Architecture
- **Frontend:** SwiftUI (AppKit/MenuBarExtra)
- **Database:** PostgreSQL (RDS) via Prisma/Drizzle (Node.js Lambda)
- **Storage:** AWS S3 (HTML snapshots)
- **Auth:** Google OAuth (Firebase/Supabase)

## Coding Standards & Patterns
- **State Management:** Use `@Observable` (SwiftUI) for the job queue.
- **Error Handling:** Every network call must have a retry mechanism for S3 uploads. [TODO: not yet implemented in `JobAPIService.uploadHTMLToS3()`]
- **Naming:** CamelCase for Swift, snake_case for PostgreSQL columns.
- **Concurrency:** Use modern Swift `async/await` for all API interactions.

## Critical Workflows
1. **The Scraper Loop:**
   - User pastes URL → saved to SwiftData (local-first).
   - `WKWebView` pre-fetches the HTML in the background and caches it locally on the client.
   - When user hits "Apply": cached HTML is uploaded to S3, then Lambda reads the S3 HTML, extracts metadata (title, company) via Cheerio, and saves the job record to RDS.
2. **Local-First Queue:**
   - New URLs go to a local SwiftData store first.
   - Make sure URLs belong to the correct users.
   - Only move to RDS once "Applied" is clicked.

## File Structure
- `/ApplicationTracker`: SwiftUI Project (`ApplicationTracker.xcodeproj`)
- `/backend-lambda`: Serverless Framework / Node.js
- `/infra`: Terraform for RDS & S3

## Deployment Notes
- `JobAPIService.swift` has a placeholder `baseURL` — must be replaced with the real API Gateway URL after deploying the Lambda.
- Run `npx drizzle-kit migrate` from `/backend-lambda` before the first deploy to apply the schema to RDS.