export interface RelayConfig {
  username: string;
  secret: string;
  port: number;
  mockMode: boolean;
  maxQueue: number;
  maxRequestsPerMinute: number;
}

function positiveInt(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): RelayConfig {
  const secret = env.RELAY_SECRET?.trim() ?? "";
  if (env.MOCK_MODE !== "true" && secret.length < 32) {
    throw new Error("RELAY_SECRET must contain at least 32 characters.");
  }
  const username = (env.TIKTOK_USERNAME ?? "").replace(/^@/, "").trim();
  if (env.MOCK_MODE !== "true" && !username) throw new Error("TIKTOK_USERNAME is required.");

  return {
    username,
    secret: secret || "mock-only-secret",
    port: positiveInt(env.PORT, 8787),
    mockMode: env.MOCK_MODE === "true",
    maxQueue: positiveInt(env.MAX_QUEUE, 2000),
    maxRequestsPerMinute: positiveInt(env.MAX_REQUESTS_PER_MINUTE, 240),
  };
}
