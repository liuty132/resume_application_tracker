import { APIGatewayProxyHandler } from 'aws-lambda';
import { verifyFirebaseToken } from '../lib/auth';
import { getPresignedPutURL } from '../lib/s3';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    // Verify Firebase token
    const userId = await verifyFirebaseToken(event.headers.Authorization);

    // Generate S3 key with user ID and timestamp
    const s3Key = `html/${userId}/${Date.now()}.html`;

    // Get presigned URL for PUT
    const uploadURL = await getPresignedPutURL(s3Key);

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ uploadURL, s3Key }),
    };
  } catch (error) {
    console.error('Error in presign handler:', error);
    return {
      statusCode: 401,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Unauthorized' }),
    };
  }
};
