import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

export interface PushPayload {
  title: string;
  body: string;
  channelId: string;
  data?: Record<string, string>;
  // APNs sound filename — must be a .caf/.aiff/.wav bundled in the iOS app
  // (Android's sound is fixed per-channelId instead, at channel creation).
  // Defaults to the system default sound.
  iosSound?: string;
}

/**
 * Fetches uid's fcmTokens, sends a prebuilt message to all of them, logs the
 * result, and prunes any token FCM reports as dead. Shared by
 * sendPushToUser and sendIncomingCallPush so both get identical delivery/
 * logging/cleanup behavior without duplicating it.
 */
async function sendToUserTokens(
  uid: string,
  logTitle: string,
  buildMessage: (tokens: string[]) => admin.messaging.MulticastMessage
): Promise<void> {
  const userSnap = await admin.firestore().collection("users").doc(uid).get();
  const tokens: string[] = userSnap.data()?.fcmTokens ?? [];
  if (!tokens.length) {
    logger.warn("push skipped: user has no registered fcmTokens", {
      uid,
      title: logTitle,
      userDocExists: userSnap.exists,
    });
    return;
  }

  const message = buildMessage(tokens);
  const res = await admin.messaging().sendEachForMulticast(message);

  if (res.failureCount) {
    logger.error("push send failures", {
      uid,
      title: logTitle,
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
      title: logTitle,
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

/**
 * Sends a push notification to every FCM token registered for a user
 * (users/{uid}.fcmTokens), and prunes tokens FCM reports as dead.
 */
export async function sendPushToUser(
  uid: string,
  payload: PushPayload
): Promise<void> {
  await sendToUserTokens(uid, payload.title, (tokens) => ({
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
          sound: payload.iosSound ?? "default",
        },
      },
    },
  }));
}

export interface IncomingCallPushPayload {
  title: string;
  body: string;
  androidChannelId: string;
  // Bundled as ios/Runner/<file> — see sendPushToUser's iosSound doc.
  iosSound: string;
  data: Record<string, string>;
}

/**
 * Sends the incoming-call push as Android data-only (no top-level
 * `notification`/`android.notification`) so Android does NOT auto-render a
 * plain notification before the app can attach its own custom sound —
 * instead it invokes the app's FirebaseMessaging.onBackgroundMessage
 * handler, which builds the real notification itself, even when the app is
 * fully killed, the same as the foreground path already does.
 *
 * iOS still auto-renders directly from apns.payload.aps.alert regardless of
 * app state — unlike Android, iOS can't reliably run app code to build a
 * notification when the app is truly terminated.
 */
export async function sendIncomingCallPush(
  uid: string,
  payload: IncomingCallPushPayload
): Promise<void> {
  await sendToUserTokens(uid, payload.title, (tokens) => ({
    tokens,
    data: {
      ...payload.data,
      title: payload.title,
      body: payload.body,
      channelId: payload.androidChannelId,
    },
    android: {
      priority: "high",
    },
    apns: {
      payload: {
        aps: {
          alert: { title: payload.title, body: payload.body },
          sound: payload.iosSound,
        },
      },
    },
  }));
}

/**
 * Tells a device to dismiss the incoming-call notification sendIncomingCallPush
 * showed, sent when the call stops ringing (answered elsewhere, declined,
 * timed out, or the caller hung up) — without this, a killed app has nothing
 * to wake it and dismiss the notification, since it was never running to see
 * the Firestore change that already handles this for a live app.
 * Silent on both platforms: no alert/sound, just enough to invoke
 * FirebaseMessaging.onBackgroundMessage (Android) or wake the app in the
 * background (iOS, via content-available) to call NotificationsPlugin.cancel.
 */
export async function sendCancelIncomingCallPush(uid: string): Promise<void> {
  await sendToUserTokens(uid, "cancel_incoming_call", (tokens) => ({
    tokens,
    data: { type: "cancel_incoming_call" },
    android: { priority: "high" },
    apns: {
      payload: {
        aps: { "content-available": 1 },
      },
    },
  }));
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
