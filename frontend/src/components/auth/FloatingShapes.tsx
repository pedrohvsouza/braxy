import styles from "./FloatingShapes.module.css";

type Kind = "plus" | "times" | "triangle" | "circle" | "diamond" | "square" | "ring";

const COLORS = ["#a86bff", "#ff4d8d", "#ffd23f", "#2dd4bf", "#2f8cff", "#3ddc84", "#ff9a1f"];
const KINDS: Kind[] = ["plus", "times", "triangle", "circle", "diamond", "square", "ring"];

// Deterministic pseudo-random layout (same on every render/SSR snapshot).
function rand(seed: number): number {
  const x = Math.sin(seed * 9301 + 49297) * 233280;
  return x - Math.floor(x);
}

const SHAPES = Array.from({ length: 26 }, (_, i) => ({
  kind: KINDS[i % KINDS.length],
  color: COLORS[Math.floor(rand(i + 1) * COLORS.length)],
  left: rand(i + 11) * 100,
  top: rand(i + 23) * 100,
  size: 12 + rand(i + 37) * 22,
  duration: 9 + rand(i + 51) * 12,
  delay: -rand(i + 67) * 20,
  drift: rand(i + 79) > 0.5 ? 1 : -1,
}));

function Shape({ kind, color }: { kind: Kind; color: string }) {
  const stroke = { stroke: color, strokeWidth: 2.5, fill: "none", strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  switch (kind) {
    case "plus":
      return <path d="M12 3v18M3 12h18" {...stroke} />;
    case "times":
      return <path d="M5 5l14 14M19 5L5 19" {...stroke} />;
    case "triangle":
      return <path d="M12 3l9 17H3z" {...stroke} />;
    case "circle":
      return <circle cx="12" cy="12" r="8" {...stroke} />;
    case "diamond":
      return <path d="M12 2l9 10-9 10-9-10z" {...stroke} />;
    case "square":
      return <rect x="4" y="4" width="16" height="16" rx="2" {...stroke} />;
    case "ring":
      return <circle cx="12" cy="12" r="4" fill={color} />;
  }
}

/** Slowly drifting outline shapes behind the auth card (and empty state). */
export function FloatingShapes({ density = 1 }: { density?: number }) {
  const shapes = SHAPES.slice(0, Math.round(SHAPES.length * density));
  return (
    <div className={styles.layer} aria-hidden>
      {shapes.map((s, i) => (
        <svg
          key={i}
          className={styles.shape}
          viewBox="0 0 24 24"
          style={{
            left: `${s.left}%`,
            top: `${s.top}%`,
            width: s.size,
            height: s.size,
            animationDuration: `${s.duration}s`,
            animationDelay: `${s.delay}s`,
            ["--drift" as string]: s.drift,
          }}
        >
          <Shape kind={s.kind} color={s.color} />
        </svg>
      ))}
    </div>
  );
}
