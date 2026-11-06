import { Fragment, type ReactNode } from "react";
import styles from "./Chat.module.css";

const TOKEN = /(https?:\/\/[^\s<]+[^\s<.,;:!?)\]'"])|(@[a-z0-9_]{3,20})/gi;

/** Plain text with clickable links and highlighted @mentions (no HTML). */
export function RichText({ text, me }: { text: string; me: string }) {
  const lines = text.split("\n");
  return (
    <>
      {lines.map((line, li) => {
        const parts: ReactNode[] = [];
        let last = 0;
        for (const m of line.matchAll(TOKEN)) {
          const idx = m.index ?? 0;
          if (idx > last) parts.push(line.slice(last, idx));
          if (m[1]) {
            parts.push(
              <a key={idx} href={m[1]} target="_blank" rel="noreferrer noopener">
                {m[1]}
              </a>,
            );
          } else {
            const self = m[2].slice(1).toLowerCase() === me;
            parts.push(
              <span key={idx} className={`${styles.mention} ${self ? styles.mentionMe : ""}`}>
                {m[2]}
              </span>,
            );
          }
          last = idx + m[0].length;
        }
        if (last < line.length) parts.push(line.slice(last));
        return (
          <Fragment key={li}>
            {li > 0 && <br />}
            {parts}
          </Fragment>
        );
      })}
    </>
  );
}
