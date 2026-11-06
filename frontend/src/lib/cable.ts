// Minimal ActionCable-protocol client for Saci Cable. One subscription
// (ChatChannel) per tab; auth is the session cookie sent with the upgrade.
export type CableEvent = { type: string } & Record<string, unknown>;

export interface CableHandlers {
  onEvent: (event: CableEvent) => void;
  onStatus: (connected: boolean, reconnected: boolean) => void;
  onLatency: (ms: number) => void;
}

const IDENTIFIER = JSON.stringify({ channel: "ChatChannel" });
const PING_EVERY = 10_000;
const HEARTBEAT_EVERY = 30_000;

export class Cable {
  private ws: WebSocket | null = null;
  private closed = false;
  private attempts = 0;
  private everConnected = false;
  private timers: number[] = [];
  private handlers: CableHandlers;

  constructor(handlers: CableHandlers) {
    this.handlers = handlers;
    this.open();
  }

  send(data: Record<string, unknown>): void {
    if (this.ws?.readyState !== WebSocket.OPEN) return;
    this.ws.send(JSON.stringify({ command: "message", identifier: IDENTIFIER, data: JSON.stringify(data) }));
  }

  close(): void {
    this.closed = true;
    this.clearTimers();
    this.ws?.close();
  }

  private open(): void {
    if (this.closed) return;
    const url = `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/cable`;
    const ws = new WebSocket(url);
    this.ws = ws;

    ws.onmessage = (ev) => {
      let frame: { type?: string; message?: unknown; identifier?: string };
      try {
        frame = JSON.parse(ev.data as string);
      } catch {
        return;
      }
      if (frame.type === "welcome") {
        ws.send(JSON.stringify({ command: "subscribe", identifier: IDENTIFIER }));
        return;
      }
      if (frame.type === "confirm_subscription") {
        const reconnected = this.everConnected;
        this.everConnected = true;
        this.attempts = 0;
        this.handlers.onStatus(true, reconnected);
        this.startTimers();
        return;
      }
      if (frame.type === "ping" || frame.type === "reject_subscription") return;
      const msg = frame.message as CableEvent | undefined;
      if (!msg || typeof msg !== "object" || typeof msg.type !== "string") return;
      if (msg.type === "pong") {
        const ts = Number(msg.ts);
        if (ts) this.handlers.onLatency(Math.max(1, Math.round(performance.now() - ts)));
        return;
      }
      this.handlers.onEvent(msg);
    };

    ws.onclose = () => {
      this.clearTimers();
      if (this.closed) return;
      this.handlers.onStatus(false, false);
      const delay = Math.min(15_000, 500 * 2 ** this.attempts) + Math.random() * 400;
      this.attempts += 1;
      window.setTimeout(() => this.open(), delay);
    };
  }

  private startTimers(): void {
    this.clearTimers();
    const ping = () => this.send({ action: "ping", ts: performance.now() });
    ping();
    this.timers.push(window.setInterval(ping, PING_EVERY));
    this.timers.push(window.setInterval(() => this.send({ action: "heartbeat" }), HEARTBEAT_EVERY));
  }

  private clearTimers(): void {
    this.timers.forEach((t) => window.clearInterval(t));
    this.timers = [];
  }
}
