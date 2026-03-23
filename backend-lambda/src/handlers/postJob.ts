import { APIGatewayProxyHandler } from 'aws-lambda';
import { verifyFirebaseToken } from '../lib/auth';
import { getHTMLFromS3 } from '../lib/s3';
import { extractJobMetadata } from '../lib/extractor';
import { getDb } from '../db/client';
import { jobs } from '../db/schema';

interface PostJobRequest {
  url: string;
  s3Key: string;
}

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    // Verify Firebase token
    const userId = await verifyFirebaseToken(event.headers.Authorization);

    // Parse request body
    const { url, s3Key } = JSON.parse(event.body || '{}') as PostJobRequest;

    if (!url || !s3Key) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Missing url or s3Key' }),
      };
    }

    // Read HTML from S3
    const html = await getHTMLFromS3(s3Key);

    // Extract company name and job title
    const { companyName, jobTitle } = extractJobMetadata(html, url);

    // Save to RDS using Drizzle
    const db = getDb();
    const [savedJob] = await db
      .insert(jobs)
      .values({
        userId,
        url,
        s3Key,
        companyName: companyName || null,
        jobTitle: jobTitle || null,
        status: 'applied',
      })
      .returning();

    return {
      statusCode: 201,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(savedJob),
    };
  } catch (error) {
    console.error('Error in postJob handler:', error);
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        error: error instanceof Error ? error.message : 'Internal server error',
      }),
    };
  }
};
