import { APIGatewayProxyHandler } from 'aws-lambda';
import { verifyFirebaseToken } from '../lib/auth';
import { getDb } from '../db/client';
import { jobs } from '../db/schema';
import { eq, gte, and, sql } from 'drizzle-orm';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    // Verify Firebase token
    const userId = await verifyFirebaseToken(event.headers.Authorization);

    // Count jobs applied today (since midnight of the current date)
    const db = getDb();
    const result = await db
      .select({ count: sql<number>`COUNT(*)` })
      .from(jobs)
      .where(
        and(
          eq(jobs.userId, userId),
          gte(jobs.appliedAt, sql`CURRENT_DATE`)
        )
      );

    const count = Number(result[0]?.count ?? 0);

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ count }),
    };
  } catch (error) {
    console.error('Error in getTodayCount handler:', error);
    return {
      statusCode: 401,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Unauthorized' }),
    };
  }
};
