import { useEffect, useRef, useState } from "react";
import { t } from "../../i18n";
import { plainText } from "../../lib/markup";
import type { ChatMessage } from "../../lib/types";

export const ANNOUNCE_WINDOW_MS = 1500;

/**
 * Text for a polite live region: other people's new messages in the open
 * conversation, grouped per window so a busy room does not flood the screen
 * reader. The first load and older pages are never announced.
 */
export function useAnnouncer(messages: ChatMessage[], meId: number): string {
  const [text, setText] = useState("");
  const seen = useRef<number | null>(null);
  const queue = useRef<ChatMessage[]>([]);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    let newest = 0;
    for (const m of messages) if (m.id > newest) newest = m.id;
    if (seen.current === null) {
      if (newest) seen.current = newest; // history already on screen
      return;
    }
    const fresh = messages.filter((m) => m.id > seen.current! && m.author?.id !== meId && !m.deleted);
    if (newest > seen.current) seen.current = newest;
    if (!fresh.length) return;
    queue.current.push(...fresh);
    if (timer.current !== null) return;
    timer.current = window.setTimeout(() => {
      timer.current = null;
      const batch = queue.current;
      queue.current = [];
      if (batch.length === 1) {
        const m = batch[0];
        const body = m.body ? plainText(m.body).slice(0, 140) : t("chat.image");
        setText(t("chat.newMessage", { name: m.author?.name ?? t("common.someone"), text: body }));
      } else {
        setText(t("chat.newMessagesCount", { count: batch.length }));
      }
    }, ANNOUNCE_WINDOW_MS);
  }, [messages, meId]);

  useEffect(() => () => {
    if (timer.current !== null) window.clearTimeout(timer.current);
  }, []);

  return text;
}
