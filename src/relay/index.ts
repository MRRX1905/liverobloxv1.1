import "dotenv/config";
import express, { type Request, type Response, type NextFunction } from "express";
import { TikTokLiveConnection, WebcastEvent } from "tiktok-live-connector";
import { loadConfig } from "./config.js";
import { EventQueue, type LiveEventType } from "./events.js";

const config = loadConfig();
const queue = new EventQueue(config.maxQueue);
const app = express();
let connected = false;
app.disable("x-powered-by");
app.use(express.json({ limit: "16kb", strict: true }));

const requestTimes = new Map<string, number[]>();
app.use((req: Request, res: Response, next: NextFunction) => {
  const key = req.ip ?? "unknown";
  const now = Date.now();
  const recent = (requestTimes.get(key) ?? []).filter(time => now - time < 60_000);
  if (recent.length >= config.maxRequestsPerMinute) return res.status(429).json({ error: "rate_limited" });
  recent.push(now);
  requestTimes.set(key, recent);
  next();
});
function authorized(req: Request, res: Response, next: NextFunction): void {
  if (req.header("x-stage-secret") !== config.secret) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }
  next();
}

app.get("/health", (_req, res) => res.json({ ok: true, mockMode: config.mockMode, connected, cursor: queue.latestCursor() }));
app.get("/events", authorized, (req, res) => {
  const raw = Number(req.query.since ?? 0);
  if (!Number.isSafeInteger(raw) || raw < 0) return res.status(400).json({ error: "invalid_cursor" });
  res.setHeader("Cache-Control", "no-store");
  res.json(queue.page(raw, Number(req.query.limit ?? 100)));
});
app.get("/stream", authorized, (req, res) => {
  const parsed = Number(req.query.since ?? 0);
  if (!Number.isSafeInteger(parsed) || parsed < 0) return res.status(400).end();
  let cursor = parsed;
  res.status(200);
  res.setHeader("Content-Type", "application/x-ndjson; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders();
  const interval = setInterval(() => {
    if (res.destroyed) { clearInterval(interval); return; }
    const page = queue.page(cursor, 100);
    cursor = page.cursor;
    res.write(`${JSON.stringify(page)}\n`);
  }, 1000);
  req.on("close", () => clearInterval(interval));
});
app.post("/mock", authorized, (req, res) => {
  if (!config.mockMode) return res.status(404).json({ error: "mock_mode_disabled" });
  const body = req.body as { type?: LiveEventType; username?: string; comment?: string; giftName?: string };
  const type = body.type;
  if (!type || !["chat", "gift", "member", "follow", "subscribe", "roomUser", "streamEnd"].includes(type)) {
    return res.status(400).json({ error: "invalid_event_type" });
  }
  const normalized = queue.normalize(type, {
    user: { userId: `mock-${body.username ?? "viewer"}`, uniqueId: body.username ?? "mock_viewer", nickname: "Mock Viewer", isFansClub: true },
    comment: body.comment ?? "!dance", giftName: body.giftName ?? "Rose", giftId: 5655,
    diamondCount: 1, repeatCount: 1, repeatEnd: true, giftType: 1, msgId: `mock-${Date.now()}-${Math.random()}`,
  });
  if (normalized) queue.push(normalized);
  res.status(202).json({ accepted: Boolean(normalized) });
});

let retryMs = 2_000;
let reconnectTimer: NodeJS.Timeout | undefined;
let connection: TikTokLiveConnection | undefined;
let stopping = false;
type EventEmitterConnection = TikTokLiveConnection & {
  on(event: string, listener: (data: unknown) => void): unknown;
};
function publish(type: LiveEventType, data: unknown): void {
  const event = queue.normalize(type, data);
  if (event) queue.push(event);
}
function stateEvent(state: string): void {
  publish("status", { state, timestamp: Date.now() });
  console.info(`[relay] ${state}`);
}

async function connect(): Promise<void> {
  if (config.mockMode || stopping || connection) return;
  connection = new TikTokLiveConnection(config.username, {
    fetchRoomInfoOnConnect: false,
    enableExtendedGiftInfo: false,
  });
  const current = connection as EventEmitterConnection;
  current.on("connected", () => { connected = true; retryMs = 2_000; stateEvent("connected"); });
  current.on("disconnected", () => { connected = false; stateEvent("disconnected"); scheduleReconnect(); });
  current.on("error", (error: unknown) => { console.error("[relay] connector error", error); connected = false; void Promise.resolve(current.disconnect()).catch(() => undefined); connection = undefined; scheduleReconnect(); });
  current.on(WebcastEvent.CHAT, (data: unknown) => publish("chat", data));
  current.on(WebcastEvent.GIFT, (data: unknown) => {
    const gift = data as unknown as Record<string, unknown>;
    const details = (gift.giftDetails ?? gift.extendedGiftInfo) as Record<string, unknown> | undefined;
    const giftType = Number(gift.giftType ?? details?.giftType ?? 0);
    if (giftType === 1 && !gift.repeatEnd) return;
    publish("gift", data);
  });
  current.on(WebcastEvent.MEMBER, (data: unknown) => publish("member", data));
  current.on(WebcastEvent.ROOM_USER, (data: unknown) => publish("roomUser", data));
  current.on(WebcastEvent.SOCIAL, (data: unknown) => {
    const value = data as unknown as Record<string, unknown>;
		const label = [value.label, value.socialAction, value.action, value.displayType, value.eventType].map(String).join(" ").toLowerCase();
		if (label.includes("sub")) publish("subscribe", data);
		else if (label.includes("follow")) publish("follow", data);
  });
	current.on("subscribe", (data: unknown) => publish("subscribe", data));
	current.on("streamEnd", (data: unknown) => { publish("streamEnd", data); connected = false; void Promise.resolve(current.disconnect()).catch(() => undefined); connection = undefined; scheduleReconnect(); });
  try {
    await current.connect();
    connected = true;
    retryMs = 2_000;
    stateEvent("connected");
  } catch (error) {
    console.error("[relay] connect failed", error);
    connection = undefined;
    connected = false;
    scheduleReconnect();
  }
}
function scheduleReconnect(): void {
  if (stopping || config.mockMode || reconnectTimer) return;
  const wait = retryMs + Math.floor(Math.random() * Math.min(1000, retryMs / 5));
  retryMs = Math.min(retryMs * 2, 60_000);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = undefined;
    connection = undefined;
    void connect();
  }, wait);
  console.info(`[relay] reconnecting in ${Math.ceil(wait / 1000)}s`);
}

const server = app.listen(config.port, () => {
  console.info(`[relay] polling API listening on :${config.port}${config.mockMode ? " (mock mode)" : ""}`);
  if (config.mockMode) {
    stateEvent("mock-ready");
    const user = { userId: "mock-001", uniqueId: "mock_viewer", nickname: "Mock Viewer", isFansClub: true };
    const emit = (type: LiveEventType, payload: Record<string, unknown>) => publish(type, { user, ...payload, timestamp: Date.now() });
    let roseStreak = 0;
    setInterval(() => emit("chat", { comment: "!dance", msgId: `mock-chat-${Date.now()}` }), 12_000);
    setInterval(() => {
      roseStreak += 1;
      emit("gift", { giftName: "Rose", giftId: 5655, diamondCount: 1, repeatCount: roseStreak, repeatEnd: true, giftType: 1, msgId: `mock-rose-${Date.now()}` });
      if (roseStreak >= 10) roseStreak = 0;
    }, 20_000);
    setTimeout(() => emit("gift", { giftName: "Donut", giftId: 5879, diamondCount: 30, repeatCount: 1, repeatEnd: true, giftType: 0, msgId: `mock-donut-${Date.now()}` }), 45_000);
  } else void connect();
});

function shutdown(): void {
  stopping = true;
  if (reconnectTimer) clearTimeout(reconnectTimer);
  server.close();
  void connection?.disconnect();
  setTimeout(() => process.exit(0), 100).unref();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
