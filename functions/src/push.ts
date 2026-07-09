import * as admin from "firebase-admin";

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
  if (!tokens.length) return;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: payload.data ?? {},
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
          contentAvailable: true,
        },
      },
    },
  };

  const res = await admin.messaging().sendEachForMulticast(message);

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
      data: payload.data ?? {},
      android: {
        priority: "high",
        notification: { channelId: payload.channelId, sound: "default" },
      },
      apns: { payload: { aps: { sound: "default" } } },
    });
  }
}
