import { randomUUID } from "node:crypto";

export type LiveEventType = "chat" | "gift" | "member" | "follow" | "subscribe" | "roomUser" | "streamEnd" | "status";

export interface LiveEvent {
  id: string;
  type: LiveEventType;
  tiktokUserId: string;
  tiktokUsername: string;
  nickname: string;
  avatarUrl: string;
  comment?: string;
  giftName?: string;
  giftId?: number;
  diamondCount?: number;
  repeatCount?: number;
  repeatEnd?: boolean;
  giftType?: number;
  isFan?: boolean;
  viewerCount?: number;
  timestamp: number;
}

export interface QueuedEvent { seq: number; event: LiveEvent }

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}
function text(value: unknown, max = 200): string {
	return typeof value === "string" || typeof value === "number" ? String(value).slice(0, max) : "";
}
function integer(value: unknown, fallback = 0): number {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? Math.floor(n) : fallback;
}
function userFields(data: Record<string, unknown>): Pick<LiveEvent, "tiktokUserId" | "tiktokUsername" | "nickname" | "avatarUrl" | "isFan"> {
  const user = record(data.user ?? data);
  const picture = record(user.profilePicture);
  const fansClub = record(user.fansClub);
  const clubData = record(fansClub.data);
  const clubStatuses = Object.values(record(fansClub.preferData)).map(value => record(value).userFansClubStatus);
  const activeFanStatus = (value: unknown): boolean => value === 1 || String(value).toUpperCase() === "ACTIVE";
  const pictureUrls = picture.url;
  return {
    tiktokUserId: text(user.userId ?? user.id, 80),
    tiktokUsername: text(user.uniqueId ?? user.username ?? user.displayId, 80),
    nickname: text(user.nickname ?? user.displayId, 100),
		avatarUrl: text(Array.isArray(pictureUrls) ? pictureUrls[0] : user.avatarUrl ?? user.profilePictureUrl, 500),
    isFan: Boolean(user.isFansClub ?? user.isFan ?? fansClub.isFan) || activeFanStatus(clubData.userFansClubStatus) || clubStatuses.some(activeFanStatus),
  };
}

export class EventQueue {
  private sequence = 0;
  private readonly items: QueuedEvent[] = [];
  private readonly seen = new Map<string, number>();

  constructor(private readonly capacity: number) {}

  normalize(type: LiveEventType, payload: unknown): LiveEvent | undefined {
    const data = record(payload);
    const user = userFields(data);
    if (["chat", "gift", "member", "follow", "subscribe"].includes(type) && !user.tiktokUsername && !user.tiktokUserId) return undefined;

    const gift = record(data.giftDetails ?? data.extendedGiftInfo);
    const eventId = text(data.msgId ?? data.messageId ?? data.eventId, 100);
    const timestamp = integer(data.timestamp, Date.now());
    const stableSourceId = eventId || randomUUID();
    if (this.seen.has(stableSourceId)) return undefined;
    this.seen.set(stableSourceId, Date.now());
    if (this.seen.size > this.capacity * 4) {
      const cutoff = Date.now() - 5 * 60_000;
      for (const [id, seenAt] of this.seen) if (seenAt < cutoff) this.seen.delete(id);
    }

    const event: LiveEvent = { id: randomUUID(), type, ...user, timestamp };
    if (type === "chat") event.comment = text(data.comment ?? data.content, 500);
    if (type === "gift") {
      event.giftName = text(data.giftName ?? gift.name ?? gift.giftName, 100);
      event.giftId = integer(data.giftId, integer(gift.id));
      event.diamondCount = integer(data.diamondCount ?? gift.diamondCount ?? gift.coins);
      event.repeatCount = Math.max(1, integer(data.repeatCount, 1));
      event.repeatEnd = Boolean(data.repeatEnd);
      event.giftType = integer(data.giftType ?? gift.giftType);
    }
    if (type === "roomUser") event.viewerCount = integer(data.viewerCount);
    if (type === "status") event.comment = text(data.state, 100);
    return event;
  }

  push(event: LiveEvent): void {
    this.items.push({ seq: ++this.sequence, event });
    if (this.items.length > this.capacity) this.items.splice(0, this.items.length - this.capacity);
  }

  page(after: number, limit = 100): { events: LiveEvent[]; cursor: number; droppedBeforeCursor: boolean } {
    const oldest = this.items[0]?.seq ?? this.sequence + 1;
    const staleCursor = after > this.sequence;
    const effectiveAfter = staleCursor ? 0 : after;
    const selected = this.items.filter(item => item.seq > effectiveAfter).slice(0, Math.max(1, Math.min(100, limit)));
    return {
      events: selected.map(item => item.event),
      cursor: selected.at(-1)?.seq ?? this.sequence,
      droppedBeforeCursor: staleCursor || effectiveAfter < oldest - 1,
    };
  }

  latestCursor(): number { return this.sequence; }
}
