// Chat markup shared by the renderer (RichText) and plain-text surfaces
// (sidebar previews, reply quotes, browser notifications).
//
//   **negrito**  *itálico* ou _itálico_  ~~riscado~~  ||spoiler||
//   `código`     ```bloco de código```   > citação

/** Fenced code blocks; the optional language tag on the first line is dropped. */
export const FENCE = /```(?:[\w+-]*\n)?([\s\S]*?)\n?```/g;

const span = (open: string, close = open, name = "") =>
  String.raw`${open}(?<${name}>(?!\s)[^\n]+?(?<!\s))${close}`;

/**
 * Inline tokens, earliest match wins. URLs come before the emphasis markers so
 * `snake_case` paths and `*` inside links stay intact; underscores and single
 * asterisks only count at word boundaries.
 */
export const INLINE = new RegExp(
  [
    "(?<code>`[^`\\n]+`)",
    String.raw`(?<url>https?:\/\/[^\s<]+[^\s<.,;:!?)\]'"*~|])`,
    "(?<mention>@[a-z0-9_]{3,20})",
    span(String.raw`\*\*`, String.raw`\*\*`, "bold"),
    span("~~", "~~", "strike"),
    span(String.raw`\|\|`, String.raw`\|\|`, "spoiler"),
    String.raw`(?<![\w*])\*(?<em>(?![\s*])[^\n*]+?(?<!\s))\*(?![\w*])`,
    String.raw`(?<![\w_])_(?<em2>(?![\s_])[^\n_]+?(?<!\s))_(?![\w_])`,
  ].join("|"),
  "giu",
);

const SPOILER_MASK = "▒▒▒";

/** Markup stripped down to what a reader would see; spoilers stay hidden. */
export function plainText(text: string): string {
  return text
    .replace(FENCE, (_, code: string) => code)
    .replace(INLINE, (whole, ...args) => {
      const g = args[args.length - 1] as Record<string, string | undefined>;
      if (g.code) return g.code.slice(1, -1);
      if (g.spoiler) return SPOILER_MASK;
      return g.bold ?? g.strike ?? g.em ?? g.em2 ?? whole;
    })
    .replace(/^> /gm, "");
}

const PICTOGRAPH = /\p{Extended_Pictographic}|\p{Regional_Indicator}/u;
const segmenter = typeof Intl !== "undefined" && "Segmenter" in Intl ? new Intl.Segmenter() : null;

/** True for 1–3 emoji and nothing else, which render large. */
export function isJumboEmoji(text: string): boolean {
  const compact = text.replace(/\s+/g, "");
  if (!compact || compact.length > 40 || !segmenter) return false;
  const graphemes = [...segmenter.segment(compact)];
  return graphemes.length <= 3 && graphemes.every((g) => PICTOGRAPH.test(g.segment));
}
