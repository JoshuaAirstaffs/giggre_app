import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

export interface PushPayload {
  title: string;
  body: string;
  channelId: string;
  data?: Record<string, string>;
}

/**
 * Sends a push notification to every FCM token registered for a user
 * (users/{uid}.fcmTokens), and prunes tokens FCM reports as dead.
 */
export async function sendPushToUser(
  uid: string,
  payload: PushPayload
): Promise<void> {
  const userSnap = await admin.firestore().collection("users").doc(uid).get();
  const tokens: string[] = userSnap.data()?.fcmTokens ?? [];
  if (!tokens.length) {
    logger.warn("push skipped: user has no registered fcmTokens", {
      uid,
      title: payload.title,
      userDocExists: userSnap.exists,
    });
    return;
  }

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: { ...(payload.data ?? {}), channelId: payload.channelId },
    android: {
      priority: "high",
      notification: {
        channelId: payload.channelId,
        sound: "default",
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  };

  const res = await admin.messaging().sendEachForMulticast(message);

  if (res.failureCount) {
    logger.error("push send failures", {
      uid,
      title: payload.title,
      successCount: res.successCount,
      failureCount: res.failureCount,
      // Last 12 chars only — enough to correlate with a device, not the whole credential.
      errors: res.responses.flatMap((r, i) =>
        r.success
          ? []
          : [
              {
                code: r.error?.code,
                message: r.error?.message,
                token: `...${tokens[i].slice(-12)}`,
              },
            ]
      ),
    });
  } else {
    logger.info("push sent", {
      uid,
      title: payload.title,
      deviceCount: res.successCount,
    });
  }

  const staleTokens: string[] = [];
  res.responses.forEach((r, i) => {
    if (
      !r.success &&
      (r.error?.code === "messaging/invalid-registration-token" ||
        r.error?.code === "messaging/registration-token-not-registered")
    ) {
      staleTokens.push(tokens[i]);
    }
  });

  if (staleTokens.length) {
    await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleTokens),
      });
  }
}

const FCM_MULTICAST_LIMIT = 500;

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

/**
 * Sends a push notification to every registered device across all users.
 * Used for tester-wide broadcasts (daily reminder, new-build announcements)
 * rather than a single recipient — skips the per-user stale-token cleanup
 * sendPushToUser does, since this already touches every user in one pass.
 */
export async function broadcastToAllUsers(payload: PushPayload): Promise<void> {
  const usersSnap = await admin.firestore().collection("users").get();
  const allTokens = usersSnap.docs.flatMap(
    (doc) => (doc.data().fcmTokens as string[] | undefined) ?? []
  );
  if (!allTokens.length) return;

  for (const tokens of chunk(allTokens, FCM_MULTICAST_LIMIT)) {
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: payload.title, body: payload.body },
      data: { ...(payload.data ?? {}), channelId: payload.channelId },
      android: {
        priority: "high",
        notification: { channelId: payload.channelId, sound: "default" },
      },
      apns: { payload: { aps: { sound: "default" } } },
    });
  }
}
