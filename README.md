# Job Application Tracker macOS Menubar App

A macOS menubar application to queue and track job applications. The app captures job posting HTML via a persistent WebKit session, uploads snapshots to S3, and uses Lambda to extract company/job title metadata before persisting to PostgreSQL.

## Architecture

```
[macOS Menubar Popup]
  ↓ paste URL → SwiftData (local queue)
  ↓ "Apply" clicked:
    1. Swift: GET /presign → Lambda returns presigned S3 URL
    2. Swift: fetch HTML via persistent WKWebView
    3. Swift: PUT HTML to S3 presigned URL
    4. Swift: POST /jobs { url, s3Key } → Lambda extracts + saves to RDS
    5. Job marked .applied → disappears from pending list
  ↓ "Disregard" → delete from SwiftData
```

## Directory Structure

```
/ApplicationTracker/            ← Xcode project (SwiftUI, macOS 14+)
/backend-lambda/            ← Node.js Lambda, Serverless Framework
/infra/                     ← Terraform for RDS, S3, Lambda IAM
```

## Quick Start

### Backend

```bash
cd backend-lambda
npm install

# Deploy with Terraform
cd ../infra
terraform init
terraform apply -var="db_password=your_password"

# Deploy Lambda
cd ../backend-lambda
npm run build
serverless deploy
```

### macOS App

1. Open `/ApplicationTracker/` in Xcode
2. Download `GoogleService-Info.plist` from Firebase and add to project
3. Update API endpoint in `Services/JobAPIService.swift`
4. Product → Run

## Testing

### Presign Endpoint
```bash
curl -X GET https://YOUR_API/dev/presign \
  -H "Authorization: Bearer YOUR_TOKEN"
# Response: { "uploadURL": "...", "s3Key": "html/..." }
```

### Full Apply Flow
1. Click menubar icon
2. Paste job URL and click "Add"
3. Click "Apply" on job
4. Verify job in RDS after ~2-5s

### Verify RDS
```bash
psql -h <RDS_ENDPOINT> -U jobpulse_user -d jobpulse \
  -c "SELECT url, company_name, job_title FROM jobs;"
```

## Key Features

- **Persistent WKWebView Session**: Maintains login state across app restarts
- **Presigned S3 URLs**: No AWS credentials in app; Lambda controls authorization
- **Tiered Extraction**: Domain-specific selectors → Open Graph → Title tag fallback
- **Local-First Queue**: SwiftData for instant UI feedback; sync to RDS on Apply
- **Type-Safe Backend**: Drizzle ORM + TypeScript for database queries

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| WebView shows login page | Site requires auth | Add "Sign in" button to WKWebView |
| "Invalid presigned URL" | API endpoint wrong | Update baseURL in JobAPIService.swift |
| NULL company/title | Site not in Tier 1 selectors | Site gracefully saves; future: Claude Haiku |
| RDS timeout | Security group issue | Verify Lambda SG allowed on port 5432 |

## Future Enhancements

- Dashboard with applied/disregarded job tracking
- Resume attachment and auto-apply workflows
- Claude Haiku extraction for unsupported domains
- Email notifications and ATS integrations
- Bulk job URL import

## Tech Stack

| Layer | Tech |
|-------|------|
| Frontend | SwiftUI, WKWebView, SwiftData |
| Backend | Node.js, Serverless Framework, Lambda |
| Database | PostgreSQL (Aurora Serverless v2) |
| Storage | S3 (HTML snapshots) |
| Auth | Firebase Auth + Google OAuth |
| ORM | Drizzle ORM |
| IaC | Terraform |