import { Fragment, type ReactNode, useState } from "react";
import { t } from "../../i18n";
import { FENCE, INLINE } from "../../lib/markup";
import styles from "./Chat.module.css";

interface Ctx {
  me: string;
}

/**
 * Message text with light markdown, clickable links and highlighted
 * @mentions. Everything becomes React elements, so no HTML ever reaches the
 * page.
 */
export function RichText({ text, me }: { text: string; me: string }) {
  const ctx = { me };
  const out: ReactNode[] = [];
  let last = 0;
  for (const m of text.matchAll(FENCE)) {
    const idx = m.index ?? 0;
    if (idx > last) out.push(<Lines key={`t${last}`} text={trimBreaks(text.slice(last, idx))} ctx={ctx} />);
    out.push(
      <pre key={`c${idx}`} className={styles.codeBlock}>
        <code>{m[1]}</code>
      </pre>,
    );
    last = idx + m[0].length;
  }
  if (last < text.length) out.push(<Lines key={`t${last}`} text={trimBreaks(text.slice(last))} ctx={ctx} />);
  return <>{out}</>;
}

/** A newline right next to a code block is the block's own line break. */
function trimBreaks(s: string): string {
  return s.replace(/^\n/, "").replace(/\n$/, "");
}

function Lines({ text, ctx }: { text: string; ctx: Ctx }) {
  if (!text) return null;
  const lines = text.split("\n");
  const isQuote = (line: string | undefined) => line?.startsWith("> ") ?? false;
  return (
    <>
      {lines.map((line, li) => {
        const quote = isQuote(line);
        const content = inline(quote ? line.slice(2) : line, ctx, `${li}`);
        // Quote lines are blocks and break on their own.
        const br = li > 0 && !quote && !isQuote(lines[li - 1]);
        return (
          <Fragment key={li}>
            {br && <br />}
            {quote ? <span className={styles.mdQuote}>{content}</span> : content}
          </Fragment>
        );
      })}
    </>
  );
}

function inline(text: string, ctx: Ctx, key: string): ReactNode[] {
  const parts: ReactNode[] = [];
  let last = 0;
  for (const m of text.matchAll(INLINE)) {
    const idx = m.index ?? 0;
    const g = m.groups ?? {};
    const k = `${key}.${idx}`;
    if (idx > last) parts.push(text.slice(last, idx));
    if (g.code) {
      parts.push(
        <code key={k} className={styles.code}>
          {g.code.slice(1, -1)}
        </code>,
      );
    } else if (g.url) {
      parts.push(
        <a key={k} href={g.url} target="_blank" rel="noreferrer noopener">
          {g.url}
        </a>,
      );
    } else if (g.mention) {
      const self = g.mention.slice(1).toLowerCase() === ctx.me;
      parts.push(
        <span key={k} className={`${styles.mention} ${self ? styles.mentionMe : ""}`}>
          {g.mention}
        </span>,
      );
    } else if (g.bold) {
      parts.push(<strong key={k}>{inline(g.bold, ctx, k)}</strong>);
    } else if (g.strike) {
      parts.push(<s key={k}>{inline(g.strike, ctx, k)}</s>);
    } else if (g.spoiler) {
      parts.push(<Spoiler key={k}>{inline(g.spoiler, ctx, k)}</Spoiler>);
    } else {
      parts.push(<em key={k}>{inline(g.em ?? g.em2 ?? "", ctx, k)}</em>);
    }
    last = idx + m[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}

function Spoiler({ children }: { children: ReactNode }) {
  const [shown, setShown] = useState(false);
  if (shown) return <span className={`${styles.spoiler} ${styles.spoilerShown}`}>{children}</span>;
  return (
    <span
      className={styles.spoiler}
      role="button"
      tabIndex={0}
      aria-label={t("chat.spoiler")}
      title={t("chat.spoiler")}
      onClick={() => setShown(true)}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          setShown(true);
        }
      }}
    >
      <span aria-hidden="true">{children}</span>
    </span>
  );
}
