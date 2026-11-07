import { type KeyboardEvent as ReactKeyboardEvent, useEffect, useRef, useState } from "react";
import { t } from "../../i18n";
import type { MessageKey } from "../../i18n/pt-BR";
import styles from "./Chat.module.css";
import { EMOJI_NAMES } from "./emojiNames";

const CATEGORIES: { key: MessageKey; icon: string; emojis: string }[] = [
  {
    key: "emoji.smileys",
    icon: "😀",
    emojis:
      "😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 😚 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 😮‍💨 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🥵 🥶 🥴 😵 🤯 🤠 🥳 😎 🤓 🧐 😕 😟 🙁 😮 😯 😲 😳 🥺 🥹 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 🤡 👻 👽 🤖 💩 😺 😸 😹 😻 😼 😽 🙀 😿 😾",
  },
  {
    key: "emoji.people",
    icon: "👋",
    emojis:
      "👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 👀 👁️ 👅 👄 🧠 🫀 👶 🧒 👦 👧 🧑 👨 👩 🧓 👴 👵 🙋 🙅 🙆 💁 🤷 🤦 🙇 💃 🕺 👯 🧑‍💻 🧑‍🎓 🧑‍🍳 🦸 🦹 🧙 🧛 🧟",
  },
  {
    key: "emoji.hearts",
    icon: "❤️",
    emojis:
      "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❤️‍🔥 💕 💞 💓 💗 💖 💘 💝 💟 💯 💢 💥 💫 💦 💨 💬 💭 💤 ✨ ⭐ 🌟 ⚡ 🔥 🎉 🎊 ✅ ❌ ⭕ ❗ ❓ ‼️ ⁉️ ⚠️ 🚫 🔞 ♻️ 🆗 🆒 🆕 🆙 🔝 🎵 🎶 ➕ ➖ ✔️ 💲 ©️ ®️ ™️",
  },
  {
    key: "emoji.nature",
    icon: "🐶",
    emojis:
      "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐢 🐍 🦖 🐙 🦑 🦀 🐠 🐬 🐳 🦈 🐊 🦒 🐘 🦥 🐾 🌵 🌲 🌴 🌱 🍀 🍁 🍂 🌷 🌹 🌻 🌸 💐 🍄 🌎 🌙 ☀️ ⛅ 🌧️ ⛈️ ❄️ ☃️ 🌈 🌊",
  },
  {
    key: "emoji.food",
    icon: "🍕",
    emojis:
      "🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🥑 🌽 🌶️ 🥕 🥔 🍞 🧀 🥚 🍳 🥓 🍔 🍟 🍕 🌭 🥪 🌮 🌯 🍝 🍜 🍣 🍱 🍤 🍙 🍦 🍩 🍪 🎂 🍰 🧁 🍫 🍬 🍭 🍿 🥤 🧃 ☕ 🍵 🧉 🍺 🍻 🥂 🍷 🍹 🍾",
  },
  {
    key: "emoji.activity",
    icon: "⚽",
    emojis:
      "⚽ 🏀 🏈 ⚾ 🎾 🏐 🎱 🏓 🥊 🛹 🏆 🥇 🥈 🥉 🏅 🎮 🕹️ 🎲 ♟️ 🎯 🎳 🎸 🎹 🥁 🎤 🎧 🎬 🎨 📸 📱 💻 ⌨️ 🖥️ 💡 📚 📖 ✏️ 📌 📎 ✂️ 🔒 🔑 🔨 🧰 💣 💊 🎁 🎈 🧸 💎 💰 💸 🚀 ✈️ 🚗 🏍️ 🚲 🏠 🏖️ 🗺️ ⏰ ⌛ 📅 🇧🇷",
  },
];

const RECENT_KEY = "braxy:emoji-recent";
const RECENT_MAX = 24;

function loadRecent(): string[] {
  try {
    const raw = JSON.parse(localStorage.getItem(RECENT_KEY) ?? "[]") as unknown;
    return Array.isArray(raw) ? raw.filter((x): x is string => typeof x === "string").slice(0, RECENT_MAX) : [];
  } catch {
    return [];
  }
}

function saveRecent(emoji: string): void {
  try {
    const next = [emoji, ...loadRecent().filter((e) => e !== emoji)].slice(0, RECENT_MAX);
    localStorage.setItem(RECENT_KEY, JSON.stringify(next));
  } catch {
    /* private mode */
  }
}

interface Props {
  onPick: (emoji: string) => void;
  onClose: () => void;
}

const fold = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
// `rank`: position inside its category, whose lists run from the most used.
const INDEX = CATEGORIES.flatMap((c) =>
  c.emojis.split(" ").map((e, rank) => {
    const [name, words] = EMOJI_NAMES[e] ?? [e, ""];
    return { e, rank, name: fold(name), words: fold(`${name} ${words}`).split(/[\s:,]+/) };
  }),
);
const COLS = 8;

/** Emoji whose name words start with every typed term; name-prefix hits first. */
export function searchEmoji(query: string): string[] {
  const terms = fold(query).split(/\s+/).filter(Boolean);
  if (!terms.length) return [];
  return INDEX.filter((x) => terms.every((term) => x.words.some((w) => w.startsWith(term))))
    .sort((a, b) => Number(b.name.startsWith(terms[0])) - Number(a.name.startsWith(terms[0])) || a.rank - b.rank)
    .map((x) => x.e);
}

export const emojiLabel = (e: string) => EMOJI_NAMES[e]?.[0] ?? e;

/** Searchable category grid with remembered recents; Escape or an outside click closes it. */
export function EmojiPicker({ onPick, onClose }: Props) {
  const [recent] = useState(loadRecent);
  const tabs = recent.length
    ? [{ key: "emoji.recent" as MessageKey, icon: "🕘", emojis: recent.join(" ") }, ...CATEGORIES]
    : CATEGORIES;
  const [tab, setTab] = useState<MessageKey>(tabs[0].key);
  const [query, setQuery] = useState("");
  const ref = useRef<HTMLDivElement>(null);
  const grid = useRef<HTMLDivElement>(null);
  const current = tabs.find((c) => c.key === tab) ?? tabs[0];
  const searching = query.trim().length > 0;
  const list = searching ? searchEmoji(query) : current.emojis.split(" ");

  useEffect(() => {
    const onDown = (e: MouseEvent) => {
      const target = e.target as Element;
      if (ref.current?.contains(target) || target.closest?.("[data-emoji-toggle]")) return;
      onClose();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        onClose();
      }
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey, true);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey, true);
    };
  }, [onClose]);

  const pick = (e: string) => {
    saveRecent(e);
    onPick(e);
  };

  const focusCell = (i: number) => {
    const cells = grid.current?.querySelectorAll<HTMLButtonElement>("button");
    if (!cells?.length) return;
    cells[Math.max(0, Math.min(cells.length - 1, i))].focus();
  };

  // Arrow keys move through the grid (one tab stop for the whole grid).
  const onGridKey = (e: ReactKeyboardEvent<HTMLDivElement>) => {
    const cells = [...(grid.current?.querySelectorAll<HTMLButtonElement>("button") ?? [])];
    const i = cells.indexOf(document.activeElement as HTMLButtonElement);
    if (i < 0) return;
    const step = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: COLS, ArrowUp: -COLS, Home: -i, End: cells.length } as Record<string, number>;
    if (e.key in step) {
      e.preventDefault();
      focusCell(i + step[e.key]);
    }
  };

  return (
    <div className={styles.emojiPanel} ref={ref} role="dialog" aria-label={t("chat.emoji")} data-testid="emoji-picker">
      <input
        className={styles.emojiSearch}
        type="search"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && list[0]) {
            e.preventDefault();
            pick(list[0]);
          } else if (e.key === "ArrowDown") {
            e.preventDefault();
            focusCell(0);
          }
        }}
        placeholder={t("emoji.search")}
        aria-label={t("emoji.search")}
        // On touch screens the keyboard would cover the grid.
        autoFocus={!window.matchMedia?.("(pointer: coarse)").matches}
      />
      {!searching && (
        <div className={styles.emojiTabs} role="tablist">
          {tabs.map((c) => (
            <button
              key={c.key}
              type="button"
              role="tab"
              aria-selected={c.key === current.key}
              aria-label={t(c.key)}
              title={t(c.key)}
              className={c.key === current.key ? styles.emojiTabOn : ""}
              onClick={() => setTab(c.key)}
            >
              {c.icon}
            </button>
          ))}
        </div>
      )}
      <p className={styles.emojiTitle} id="emoji-grid-title">
        {searching ? t("emoji.results", { count: list.length }) : t(current.key)}
      </p>
      <div className={styles.emojiGrid} ref={grid} role="group" aria-labelledby="emoji-grid-title" onKeyDown={onGridKey}>
        {list.map((e, i) => (
          <button key={e} type="button" aria-label={emojiLabel(e)} title={emojiLabel(e)} tabIndex={i === 0 ? 0 : -1} onClick={() => pick(e)}>
            {e}
          </button>
        ))}
        {searching && list.length === 0 && <p className={styles.emojiEmpty}>{t("emoji.none")}</p>}
      </div>
      <p className={styles.emojiHint}>{t("chat.formatHint")}</p>
    </div>
  );
}
