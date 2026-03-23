# Job Application Tracker Testing Guide

This guide walks through testing each component of the Job Application Tracker application.

## Prerequisites

- All infrastructure deployed via Terraform
- Lambda functions deployed via Serverless Framework
- macOS app built in Xcode
- Firebase project configured with valid credentials
- PostgreSQL RDS instance accessible

## Setup Verification

Run the verification script to ensure all files are in place:

```bash
./test-setup.sh
```

## Component-by-Component Testing

### 1. Database Connection

Verify RDS is accessible and schema is created:

```bash
# Connect to RDS
psql -h <RDS_ENDPOINT> -U jobpulse_user -d jobpulse

# Check jobs table
\d jobs

# Expected output:
# jobs table with columns: id, user_id, url, company_name, job_title, s3_key, applied_at, status
```

### 2. S3 Bucket

Verify S3 bucket exists and is properly configured:

```bash
# List S3 bucket
aws s3 ls jobpulse-html-snapshots-<ACCOUNT_ID>/

# Check versioning
aws s3api get-bucket-versioning \
  --bucket jobpulse-html-snapshots-<ACCOUNT_ID>

# Expected: "Status": "Enabled"

# Check encryption
aws s3api get-bucket-encryption \
  --bucket jobpulse-html-snapshots-<ACCOUNT_ID>

# Check public access block
aws s3api get-public-access-block \
  --bucket jobpulse-html-snapshots-<ACCOUNT_ID>
```

### 3. Lambda Presign Endpoint

Test presigned URL generation:

```bash
# Get Firebase token (from macOS app or Firebase CLI)
export TOKEN="your_firebase_id_token"
export API_ENDPOINT="https://YOUR_API.execute-api.us-east-1.amazonaws.com/dev"

# Call presign endpoint
curl -X GET "$API_ENDPOINT/presign" \
  -H "Authorization: Bearer $TOKEN"

# Expected response:
# {
#   "uploadURL": "https://s3.amazonaws.com/jobpulse-html-snapshots-123456789/html/user-id/timestamp.html?X-Amz-Algorithm=...",
#   "s3Key": "html/user-id/timestamp.html"
# }
```

### 4. S3 Upload via Presigned URL

Test uploading HTML to S3:

```bash
# Create a sample HTML file
cat > sample.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Senior Engineer at TechCorp</title>
    <meta property="og:title" content="Senior Engineer at TechCorp">
</head>
<body>
    <h1>Senior Engineer</h1>
    <p>TechCorp is hiring engineers.</p>
</body>
</html>
EOF

# Get presigned URL from previous step
export PRESIGNED_URL="https://s3.amazonaws.com/..."

# Upload to S3
curl -X PUT "$PRESIGNED_URL" \
  -H "Content-Type: text/html; charset=utf-8" \
  --data-binary @sample.html

# Expected: HTTP 200

# Verify in S3
aws s3 ls s3://jobpulse-html-snapshots-<ACCOUNT_ID>/html/
```

### 5. Lambda PostJob Endpoint

Test metadata extraction and RDS persistence:

```bash
# Call postJob endpoint
curl -X POST "$API_ENDPOINT/jobs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://jobs.example.com/positions/senior-engineer",
    "s3Key": "html/user-id/1234567890.html"
  }'

# Expected response:
# {
#   "id": "uuid",
#   "userId": "user-id",
#   "url": "https://jobs.example.com/positions/senior-engineer",
#   "companyName": "TechCorp",
#   "jobTitle": "Senior Engineer",
#   "s3Key": "html/user-id/1234567890.html",
#   "appliedAt": "2024-03-21T12:34:56Z",
#   "status": "applied"
# }
```

### 6. Verify RDS Data

Check that the job was persisted to the database:

```bash
psql -h <RDS_ENDPOINT> -U jobpulse_user -d jobpulse

# View the inserted job
SELECT id, url, company_name, job_title, status FROM jobs
  WHERE status = 'applied'
  ORDER BY applied_at DESC
  LIMIT 1;

# Expected output:
# uuid | https://jobs.example.com/positions/senior-engineer | TechCorp | Senior Engineer | applied
```

### 7. Lambda GetJobs Endpoint

Test retrieving user's applied jobs:

```bash
curl -X GET "$API_ENDPOINT/jobs" \
  -H "Authorization: Bearer $TOKEN"

# Expected response:
# [
#   {
#     "id": "uuid",
#     "userId": "user-id",
#     "url": "https://...",
#     "companyName": "...",
#     "jobTitle": "...",
#     "s3Key": "...",
#     "appliedAt": "...",
#     "status": "applied"
#   }
# ]
```

### 8. macOS App - Local Queue

Test local SwiftData functionality:

1. Open the Job Application Tracker menubar app
2. Click the menubar icon to open the popup
3. Paste a valid job URL in the "Paste job URL…" field
4. Press Enter or click the "+" button
5. **Expected:** Job appears immediately in the pending list with "Apply" and "Disregard" buttons

### 9. macOS App - Disregard Flow

Test removing jobs from the queue:

1. With a job in the pending list, click the red "X" button
2. **Expected:** Job disappears instantly; nothing written to RDS

Verify RDS is untouched:

```bash
psql -h <RDS_ENDPOINT> -U jobpulse_user -d jobpulse
SELECT COUNT(*) FROM jobs;
# Should not have increased
```

### 10. macOS App - Full Apply Flow

Test the complete 4-step Apply process:

1. Open Job Application Tracker menubar app
2. Paste a job URL and add it (e.g., `https://jobs.greenhouse.io/example`)
3. Click "Apply" button
4. **Expected:**
   - Button changes to loading spinner
   - After 2-5 seconds, job disappears from list
   - Spinner shows during all 4 steps:
     - Step 1: Requesting presigned URL
     - Step 2: Fetching HTML via WKWebView
     - Step 3: Uploading to S3
     - Step 4: Posting to Lambda for extraction

5. **Verify in RDS:**
   ```bash
   psql -h <RDS_ENDPOINT> -U jobpulse_user -d jobpulse
   SELECT url, company_name, job_title FROM jobs
     WHERE status = 'applied'
     ORDER BY applied_at DESC
     LIMIT 1;
   ```
   - Should show the URL, company, and job title

6. **Verify in S3:**
   ```bash
   aws s3 ls s3://jobpulse-html-snapshots-<ACCOUNT_ID>/html/
   # Should see new .html file with recent timestamp
   ```

### 11. WKWebView Persistence Testing

Test that WKWebView maintains persistent login sessions:

1. First Apply with LinkedIn URL (will show login page in WKWebView)
   - Add "Sign in" button to open visible WKWebView
   - User logs into LinkedIn
   - HTML captured will be login page (extraction returns NULL)

2. Second Apply with different LinkedIn URL
   - WKWebView uses persistent cookies
   - HTML should be actual job posting (not login page)
   - Extraction should work correctly

### 12. Error Handling

Test error conditions:

#### Invalid URL
```bash
# In app, paste invalid URL
# Expected: Error message "Invalid URL"
```

#### Network Error
```bash
# Temporarily disable network
# Click "Apply" on a pending job
# Expected: Error message "Network error" after timeout
# Status reverts to "pending" for retry
```

#### Firebase Token Expiry
```bash
# Wait for Firebase token to expire (1+ hour)
# Click "Apply"
# Expected: Firebase auto-refresh, Apply succeeds
# (If not, error message with guidance to re-authenticate)
```

#### S3 Upload Failure
```bash
# Manually delete S3 bucket permissions for Lambda
# Click "Apply"
# Expected: Error message "S3 upload failed"
# Status reverts to "pending"

# Restore permissions and retry
```

#### RDS Connection Failure
```bash
# Temporarily disable Lambda security group RDS access
# Click "Apply"
# Expected: Error after Step 3 completes but Step 4 fails
# Status reverts to "pending"

# Restore access and retry
```

### 13. Multi-User Testing

Test that each user only sees their own jobs:

1. **User A:**
   - Log in with Firebase account A
   - Add and Apply to 3 jobs
   - Run `GET /jobs` → should see 3 jobs

2. **User B:**
   - Log in with Firebase account B (different email)
   - Add and Apply to 2 jobs
   - Run `GET /jobs` → should see only 2 jobs (not User A's)

3. **User A again:**
   - Switch back to User A
   - Run `GET /jobs` → should still see only 3 jobs

## Extraction Quality Testing

Test extraction across different job boards:

### Greenhouse
```bash
URL="https://jobs.greenhouse.io/example"
# Expected extraction: companyName + jobTitle from og:title
```

### LinkedIn
```bash
URL="https://www.linkedin.com/jobs/view/123456789"
# May require login first
# Expected: NULL on first Apply (login page), valid data after login
```

### Lever
```bash
URL="https://jobs.lever.co/example"
# Expected extraction from job page selectors
```

### Workday
```bash
URL="https://workday.example.com/careers"
# Expected extraction from Workday-specific selectors
```

### Unknown Job Board
```bash
URL="https://custom-job-board.com/job/123"
# Expected: Fallback to og:title or <title> tag
# If none available: NULL values saved (graceful degradation)
```

## Performance Testing

Measure response times for each step:

```bash
# Time the full Apply flow
time curl -X GET "$API_ENDPOINT/presign" -H "Authorization: Bearer $TOKEN"
time curl -X PUT "$PRESIGNED_URL" --data-binary @sample.html
time curl -X POST "$API_ENDPOINT/jobs" -H "Authorization: Bearer $TOKEN" -d '{...}'

# Expected times:
# Presign: <100ms
# S3 upload: <500ms (depends on HTML size)
# PostJob: <500ms (depends on RDS latency)
# Total app-side: 2-5 seconds including WKWebView fetch
```

## Load Testing

Test system under multiple concurrent Applies:

```bash
# Using Apache Bench or similar
ab -n 10 -c 5 https://YOUR_API.execute-api.us-east-1.amazonaws.com/dev/presign
# Monitor CloudWatch logs for Lambda errors

# Check RDS connection pool
psql -h <RDS_ENDPOINT> -U jobpulse_user -d jobpulse
SELECT * FROM pg_stat_activity WHERE datname = 'jobpulse';
# Should show <= 3 connections (Lambda pool max)
```

## Cleanup After Testing

```bash
# Delete test jobs from RDS
psql -h <RDS_ENDPOINT> -U jobpulse_user -d jobpulse
DELETE FROM jobs WHERE status = 'applied' AND applied_at < NOW() - INTERVAL '1 hour';

# Delete test files from S3
aws s3 rm s3://jobpulse-html-snapshots-<ACCOUNT_ID>/html/ --recursive

# Keep infrastructure running for integration tests
```

## Troubleshooting Common Test Failures

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| "Unauthorized" on API calls | Invalid/expired Firebase token | Get fresh token from Firebase CLI or macOS app |
| "Access Denied" on S3 upload | Lambda IAM policy missing | Verify S3 policy in Lambda role |
| RDS connection timeout | SG rule missing or VPC issue | Check Lambda SG allows port 5432 to RDS SG |
| NULL company/title | Extraction selectors don't match | Check HTML structure for that job board |
| App can't reach API | Endpoint URL wrong in JobAPIService.swift | Verify API_ENDPOINT environment variable |
| WKWebView shows error page | Network issue or invalid URL | Test URL in Safari first |

## Success Criteria

✅ All component tests pass
✅ Full end-to-end flow completes in <10 seconds
✅ Jobs persist correctly to RDS with extracted metadata
✅ S3 HTML snapshots are accessible and versioned
✅ Multi-user data isolation confirmed
✅ Error handling gracefully reverts status for retry
✅ No errors in CloudWatch logs
