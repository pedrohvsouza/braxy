import styles from "./common.module.css";

const PALETTE = ["#7b4dff", "#2f8cff", "#ff7a59", "#2dd4bf", "#ff4d8d", "#ffb020", "#4ade80", "#a855f7"];

interface Props {
  name: string;
  url?: string | null;
  size?: number;
  square?: boolean;
  online?: boolean | null;
  group?: boolean;
}

/** Image avatar with an initials fallback (deterministic color per name). */
export function Avatar({ name, url, size = 40, square = false, online = null, group = false }: Props) {
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join("");
  const color = PALETTE[[...name].reduce((acc, ch) => acc + ch.charCodeAt(0), 0) % PALETTE.length];
  return (
    <span
      className={`${styles.avatar} ${square ? styles.square : ""}`}
      style={{ width: size, height: size, fontSize: size * 0.38, background: url ? undefined : color }}
      data-group={group || undefined}
    >
      {url ? <img src={url} alt="" loading="lazy" /> : <span aria-hidden>{initials || "?"}</span>}
      {online !== null && <span className={`online-dot ${online ? "on" : ""} ${styles.dot}`} />}
    </span>
  );
}
