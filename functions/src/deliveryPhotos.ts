import { onSchedule } from "firebase-functions/v2/scheduler";
import { getStorage } from "firebase-admin/storage";
import { firestoreTriggerRegion } from "./region";

// ── Delivery proof photos cleanup ───────────────────────────────────────────
// Workers photograph the item at the pick-up and the drop-off of a delivery
// gig (delivery_photo_service.dart). They're only needed while a dispute is
// still likely, so files older than 60 days are deleted — we don't keep
// pictures of people's items and doorsteps forever. The gig doc keeps its
// (now dead) URL and the time the photo was taken.
const PREFIX = "delivery_photos/";
const KEEP_DAYS = 60;

export const cleanupDeliveryPhotos = onSchedule(
  {
    schedule: "every day 03:30",
    timeZone: "Asia/Manila",
    region: firestoreTriggerRegion(),
  },
  async () => {
    const cutoff = Date.now() - KEEP_DAYS * 24 * 60 * 60 * 1000;
    const bucket = getStorage().bucket();
    let deleted = 0;
    let pageToken: string | undefined;
    do {
      const [files, next] = await bucket.getFiles({
        prefix: PREFIX,
        maxResults: 500,
        autoPaginate: false,
        pageToken,
      });
      for (const f of files) {
        const created = Date.parse(String(f.metadata.timeCreated ?? ""));
        if (Number.isFinite(created) && created < cutoff) {
          try {
            await f.delete();
            deleted++;
          } catch (e) {
            console.warn(`cleanupDeliveryPhotos: couldn't delete ${f.name}`, e);
          }
        }
      }
      pageToken = (next as { pageToken?: string } | undefined)?.pageToken;
    } while (pageToken);
    console.log(`cleanupDeliveryPhotos: deleted ${deleted} file(s) older than ${KEEP_DAYS} days`);
  },
);
