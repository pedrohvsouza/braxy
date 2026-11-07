// Read receipts, throttled per conversation: the first one goes out at once
// (so a quiet DM shows "Visto" right away), then at most one request per
// window carrying the highest message id seen meanwhile.
import { api } from "./api";

export const READ_WINDOW_MS = 500;

interface Slot {
  /** Highest id waiting to be sent. */
  pending: number;
  /** Highest id already sent. */
  sent: number;
  timer: number | null;
}

const slots = new Map<number, Slot>();

function send(conversationId: number, slot: Slot): void {
  const upto = slot.pending;
  if (upto <= slot.sent) return;
  slot.sent = upto;
  void api.markRead(conversationId, upto).catch(() => {
    // Let the next receipt retry this one.
    if (slot.sent === upto) slot.sent = 0;
  });
}

export function queueRead(conversationId: number, messageId: number): void {
  if (messageId <= 0) return;
  let slot = slots.get(conversationId);
  if (!slot) {
    slot = { pending: 0, sent: 0, timer: null };
    slots.set(conversationId, slot);
  }
  if (messageId <= slot.pending) return;
  slot.pending = messageId;
  if (slot.timer !== null) return; // the window's trailing send will carry it
  send(conversationId, slot);
  const s = slot;
  const tick = () => {
    if (s.pending > s.sent) {
      send(conversationId, s);
      s.timer = window.setTimeout(tick, READ_WINDOW_MS);
    } else {
      s.timer = null;
    }
  };
  s.timer = window.setTimeout(tick, READ_WINDOW_MS);
}

/** Test hook. */
export function resetReadQueue(): void {
  for (const s of slots.values()) if (s.timer !== null) window.clearTimeout(s.timer);
  slots.clear();
}
