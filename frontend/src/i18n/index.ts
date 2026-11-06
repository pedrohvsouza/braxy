import { ptBR, type MessageKey } from "./pt-BR";

const dictionaries: Record<string, Record<string, string>> = { "pt-BR": ptBR };
let locale = "pt-BR";

export function setLocale(next: string): void {
  if (dictionaries[next]) locale = next;
}

export function currentLocale(): string {
  return locale;
}

/** Translate `key`, interpolating `{name}` placeholders. */
export function t(key: MessageKey, vars: Record<string, string | number> = {}): string {
  const template = dictionaries[locale]?.[key] ?? ptBR[key] ?? key;
  return template.replace(/\{(\w+)\}/g, (_, name: string) => (name in vars ? String(vars[name]) : `{${name}}`));
}
