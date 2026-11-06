import { currentLocale } from "../i18n";

const pad = (n: number) => String(n).padStart(2, "0");

/** "20/09/2020 13:32:46" — the reference UI's message timestamp. */
export function fullTimestamp(iso: string): string {
  const d = new Date(iso);
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

/** Short sidebar time: HH:MM today, DD/MM otherwise. */
export function shortTime(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`;
}

export function longDate(iso: string): string {
  return new Date(iso).toLocaleDateString(currentLocale(), { day: "2-digit", month: "long", year: "numeric" });
}

/** Birthday stored as YYYY-MM-DD (no timezone shift). */
export function birthdayLabel(ymd: string): string {
  const [y, m, d] = ymd.split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString(currentLocale(), { day: "2-digit", month: "long" });
}

/** 6600 -> "6,6 mil" (the reference empty-state counters). */
export function compactNumber(n: number): string {
  return new Intl.NumberFormat(currentLocale(), { notation: "compact", maximumFractionDigits: 1 }).format(n);
}

export function thousands(n: number): string {
  return new Intl.NumberFormat(currentLocale()).format(n);
}
