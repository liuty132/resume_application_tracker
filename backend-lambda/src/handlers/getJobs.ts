import { APIGatewayProxyHandler } from 'aws-lambda';
import { verifyFirebaseToken } from '../lib/auth';
import { getDb } from '../db/client';
import { jobs } from '../db/schema';
import { eq } from 'drizzle-orm';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    // Verify Firebase token
    const userId = await verifyFirebaseToken(event.headers.Authorization);

    // Fetch jobs for this user
    const db = getDb();
    const userJobs = await db
      .select()
      .from(jobs)
      .where(eq(jobs.userId, userId))
      .orderBy(jobs.appliedAt);

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(userJobs),
    };
  } catch (error) {
    console.error('Error in getJobs handler:', error);
    return {
      statusCode: 401,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Unauthorized' }),
    };
  }
};
