import { useEffect, useRef, useState } from "react";
import { t } from "../../i18n";
import type { MessageKey } from "../../i18n/pt-BR";
import styles from "./Chat.module.css";

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

/** Category grid with remembered recents; closes on outside click or Escape. */
export function EmojiPicker({ onPick, onClose }: Props) {
  const [recent] = useState(loadRecent);
  const tabs = recent.length
    ? [{ key: "emoji.recent" as MessageKey, icon: "🕘", emojis: recent.join(" ") }, ...CATEGORIES]
    : CATEGORIES;
  const [tab, setTab] = useState<MessageKey>(tabs[0].key);
  const ref = useRef<HTMLDivElement>(null);
  const current = tabs.find((c) => c.key === tab) ?? tabs[0];

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

  return (
    <div className={styles.emojiPanel} ref={ref} role="dialog" aria-label={t("chat.emoji")} data-testid="emoji-picker">
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
      <p className={styles.emojiTitle}>{t(current.key)}</p>
      <div className={styles.emojiGrid} role="tabpanel">
        {current.emojis.split(" ").map((e) => (
          <button
            key={e}
            type="button"
            aria-label={e}
            onClick={() => {
              saveRecent(e);
              onPick(e);
            }}
          >
            {e}
          </button>
        ))}
      </div>
      <p className={styles.emojiHint}>{t("chat.formatHint")}</p>
    </div>
  );
}
