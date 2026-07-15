import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as admin from 'firebase-admin';

export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Wraps the Firebase Admin SDK. Falls back to a no-op logger when
 * FIREBASE_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY are not set (dev machines /
 * environments without a Firebase project yet) — mirrors the MockPrinterAdapter
 * pattern so the rest of the app runs unchanged before the hardware/creds exist.
 */
@Injectable()
export class FcmService implements OnModuleInit {
  private readonly logger = new Logger(FcmService.name);
  private app: admin.app.App | null = null;

  onModuleInit() {
    const projectId = process.env.FIREBASE_PROJECT_ID;
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
    const privateKey = process.env.FIREBASE_PRIVATE_KEY;

    if (!projectId || !clientEmail || !privateKey) {
      this.logger.warn(
        'FIREBASE_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY not set — FCM disabled (push notifications will only be logged).',
      );
      return;
    }

    // admin.initializeApp() throws if a default app already exists (e.g. hot
    // reload in dev re-running onModuleInit) — reuse it instead of crashing.
    this.app = admin.apps.length
      ? admin.apps[0]
      : admin.initializeApp({
          credential: admin.credential.cert({
            projectId,
            clientEmail,
            // .env stores the key with literal "\n" — turn them back into real newlines.
            privateKey: privateKey.replace(/\\n/g, '\n'),
          }),
        });
  }

  get isEnabled(): boolean {
    return this.app !== null;
  }

  // Firebase rejects sendEachForMulticast() outright above this many tokens per call.
  private static readonly MAX_TOKENS_PER_CALL = 500;

  /** Send to a batch of device tokens. Invalid/unregistered tokens are returned so callers can prune them. */
  async sendToTokens(tokens: string[], message: PushMessage): Promise<{ invalidTokens: string[] }> {
    if (tokens.length === 0) return { invalidTokens: [] };

    if (!this.app) {
      this.logger.log(`[FCM disabled] would send "${message.title}" to ${tokens.length} device(s)`);
      return { invalidTokens: [] };
    }

    const invalidTokens: string[] = [];
    for (let i = 0; i < tokens.length; i += FcmService.MAX_TOKENS_PER_CALL) {
      const chunk = tokens.slice(i, i + FcmService.MAX_TOKENS_PER_CALL);
      const response = await admin.messaging(this.app!).sendEachForMulticast({
        tokens: chunk,
        notification: { title: message.title, body: message.body },
        data: message.data,
      });

      response.responses.forEach((r, j) => {
        if (!r.success && r.error) {
          const code = r.error.code;
          if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
            invalidTokens.push(chunk[j]);
          } else {
            this.logger.error(`FCM send failed for token ${chunk[j]}: ${r.error.message}`);
          }
        }
      });
    }

    return { invalidTokens };
  }
}
