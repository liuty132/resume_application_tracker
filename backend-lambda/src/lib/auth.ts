import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK
let firebaseApp: admin.app.App | null = null;

export function getFirebaseApp(): admin.app.App {
  if (!firebaseApp) {
    firebaseApp = admin.initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
    });
  }
  return firebaseApp;
}

export async function verifyFirebaseToken(authHeader?: string): Promise<string> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('Missing or invalid Authorization header');
  }

  const token = authHeader.substring('Bearer '.length);

  try {
    const app = getFirebaseApp();
    const decodedToken = await admin.auth(app).verifyIdToken(token);
    return decodedToken.uid;
  } catch (error) {
    console.error('Firebase token verification failed:', error);
    throw new Error('Invalid or expired token');
  }
}
