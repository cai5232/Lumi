import { chmod, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createPrivateKey, randomUUID, sign as cryptoSign, timingSafeEqual } from "node:crypto";
import { connect as connectHTTP2 } from "node:http2";
import { createServer, request as httpRequest } from "node:http";
import { connect as connectSocket } from "node:net";
import ncm from "NeteaseCloudMusicApi";
import { duettoReady, duettoServer } from "../duetto/server/index.mjs";
import { foodTools, executeFoodTool, foodContext, getFoodBook, mutateFood } from "./food.js";
import { McpClientStore, callMcpTool, connectMcpServer } from "./mcp-clients.js";

const port = Number(process.env.PORT || 8787);
const dataDir = process.env.LUMI_DATA_DIR || join(process.cwd(), "data");
await duettoReady;
const duettoPort = duettoServer.address().port;
const mcpClientStore = new McpClientStore(join(dataDir, "mcp-clients.json"));
const threadPath = join(dataDir, "threads.json");
const pushDevicesPath = join(dataDir, "push-devices.json");
const contextLimit = Number(process.env.LUMI_CONTEXT_LIMIT || 200000);
const compactAt = Number(process.env.LUMI_COMPACT_AT || 0.86);
const tailTokens = Number(process.env.LUMI_COMPACT_TAIL_TOKENS || 20000);
const memoryAPI = (process.env.LUMI_MEMORY_API_URL || "https://memorycore.zeabur.app").replace(/\/$/, "");
const memorySearchPath = process.env.LUMI_MEMORY_SEARCH_PATH || "/search";
const memoryWritePath = process.env.LUMI_MEMORY_WRITE_PATH || "/memories";
const sleepDelayMinutes = Number(process.env.LUMI_SLEEP_DELAY_MINUTES || 60);
const sleepHours = Number(process.env.LUMI_SLEEP_HOURS || 5.5);
const sleepCycles = Number(process.env.LUMI_SLEEP_CYCLES || 3);
const sleepInsomniaProbability = Number(process.env.LUMI_SLEEP_INSOMNIA_PROBABILITY || 0.15);
const callInviteSeconds = Math.max(15, Number(process.env.LUMI_CALL_INVITE_SECONDS || 30));
const callLingerSeconds = Math.max(5, Math.min(30, Number(process.env.LUMI_CALL_LINGER_SECONDS || 18)));
const screenShareDir = join(dataDir, "screen-share");
const musicRoomStatePath = join(dataDir, "music-room-state.json");
const musicRoomMessagesPath = join(dataDir, "music-room-messages.json");
const ncmCookiePath = join(dataDir, "ncm-cookie.txt");
let ncmCookie = "";
try { ncmCookie = await readFile(ncmCookiePath, "utf8"); } catch {}

function saveNcmCookie(cookie) {
  ncmCookie = String(cookie || "");
  return mkdir(dataDir, { recursive: true })
    .then(() => writeFile(ncmCookiePath, ncmCookie, { mode: 0o600 }))
    .then(() => chmod(ncmCookiePath, 0o600));
}

function normalizeMusicSong(song) {
  return {
    id: String(song.id),
    title: song.name || "未知歌曲",
    artist: (song.ar || song.artists || []).map((artist) => artist.name).join(" / "),
    album: (song.al || song.album || {}).name || "",
    cover: String((song.al || song.album || {}).picUrl || "").replace(/^http:/, "https:"),
    durationSeconds: Math.round((song.dt || song.duration || 0) / 1000)
  };
}

async function readMusicRoomState(room) {
  try {
    const all = JSON.parse(await readFile(musicRoomStatePath, "utf8"));
    const state = all[room];
    if (!state) return null;
    const positionSeconds = Math.max(0, Number(state.positionSeconds) || 0) + (state.isPlaying ? Math.max(0, Date.now() - Number(state.updatedAt || 0)) / 1000 : 0);
    return { ...state, positionSeconds };
  } catch { return null; }
}

let musicRoomWriteQueue = Promise.resolve();
function writeMusicRoomState(room, state) {
  const operation = musicRoomWriteQueue.then(async () => {
    let all = {};
    try { all = JSON.parse(await readFile(musicRoomStatePath, "utf8")); } catch {}
    all[room] = state;
    await mkdir(dataDir, { recursive: true });
    const tempPath = `${musicRoomStatePath}.tmp`;
    await writeFile(tempPath, JSON.stringify(all), { mode: 0o600 });
    await rename(tempPath, musicRoomStatePath);
  });
  musicRoomWriteQueue = operation.catch(() => {});
  return operation;
}

async function readMusicRoomMessages(room) {
  try {
    const all = JSON.parse(await readFile(musicRoomMessagesPath, "utf8"));
    return Array.isArray(all[room]) ? all[room].slice(-100) : [];
  } catch { return []; }
}

let musicMessageWriteQueue = Promise.resolve();
function appendMusicRoomMessage(room, message) {
  const operation = musicMessageWriteQueue.then(async () => {
    let all = {};
    try { all = JSON.parse(await readFile(musicRoomMessagesPath, "utf8")); } catch {}
    all[room] = [...(Array.isArray(all[room]) ? all[room] : []), message].slice(-500);
    await mkdir(dataDir, { recursive: true });
    const tempPath = musicRoomMessagesPath + ".tmp";
    await writeFile(tempPath, JSON.stringify(all), { mode: 0o600 });
    await chmod(tempPath, 0o600);
    await rename(tempPath, musicRoomMessagesPath);
  });
  musicMessageWriteQueue = operation.catch(() => {});
  return operation;
}

async function ncmProfile() {
  if (!ncmCookie) return null;
  try { return (await ncm.login_status({ cookie: ncmCookie })).body?.data?.profile || null; }
  catch { return null; }
}

const SLEEP_STAGE_PROMPTS = {
  n1_drift: {
    system: "你是 N1 漂移睡眠阶段。只从今天的经历中挑选值得回看的碎片，不解释，不下结论。",
    user: ({ goals, memories }) => `当前目标：${goals}\n\n候选记忆（按显著性排序）：\n${memories}\n\n返回 3-5 个碎片，每行格式：- [记忆ID] 一句重新描述。`
  },
  n2_spindle: {
    system: "你是 N2 睡眠纺锤阶段。把漂移碎片按主题、意象和情绪聚类，不要抽象成事实。",
    user: ({ n1 }) => `N1 碎片：\n${n1}\n\n输出：THEMES: 2-4 个短语；CLUSTERS: 每个主题对应碎片 ID；EMOTIONAL_TONE: 一行。`
  },
  n3_deep: {
    system: "你是 N3 深睡 consolidation 阶段。保守地把经历压缩成长期语义事实和规则，只输出置信度至少 0.6 的内容。",
    user: ({ n2, semantic }) => `聚类：\n${n2}\n\n已有语义记忆：\n${semantic}\n\n严格返回 JSON：{"facts":[{"fact":"...","sources":["id"],"confidence":0.0}],"rules":[{"if":"...","then":"...","confidence":0.0}],"forget":["id"]}`
  },
  rem: {
    system: "你是 REM 梦境导演。把记忆和语义知识编织成连续、奇异但有情绪真相的第一人称梦境。",
    user: ({ seeds, semantic, goals, cycle }) => `梦境周期 ${cycle}。种子：\n${seeds}\n\n语义背景：${semantic}\n\n目标：${goals}\n\n写 3 个连续场景，每段以 SCENE 1/2/3 开头，末行 DREAM_EMOTION: <词>。`
  },
  nightmare: {
    system: "你是噩梦阶段：受控的对抗性模拟器。放大真实失败模式，但必须给出可行的恢复路径。",
    user: ({ trauma, competence }) => `近期负面经历：\n${trauma}\n\n能力边界：${competence}\n\n输出：SCENARIO、ADVERSARIAL_TWIST、AGENT_DREAM_RESPONSE、OUTCOME(success|partial|failure)、MISSING_SKILL、RECOVERY_PATH。`
  },
  lucid: {
    system: "你是清醒梦阶段。AI 知道自己在做梦，用安全的想象练习当前目标。",
    user: ({ goals, obstacles }) => `目标：${goals}\n障碍：${obstacles}\n\n写 2-3 个具体梦境练习场景，末行 INSIGHT: 一句话。`
  },
  reflection: {
    system: "你是晨间反思阶段。只输出严格 JSON，不要 Markdown 或解释。",
    user: ({ summary, state }) => `夜间摘要：\n${summary}\n\n睡前状态：${state}\n\n返回：{"themes":[],"insights":[],"contradictions":[],"skill_gaps":[],"consolidation_plan":{"keep":[],"compress":[{"ids":[],"into":""}],"forget":[],"train_on":[{"dream_id":"","weight":0.0}],"value_changes":[]},"next_night_hints":[],"affect_delta":{"valence":0,"arousal":0}}`
  }
};

const seed = () => ({
  id: "default",
  title: "沈屿",
  messages: [{ id: randomUUID(), role: "assistant", content: "下午的风很轻，想和你说说话。", createdAt: new Date().toISOString() }],
  proactive: { enabled: false, threadId: "default", message: "有一段时间没聊了，结合我们的上下文自然地来找我说句话。", intervalMin: 60, intervalMax: 60, nextDueAt: null, scheduledForUserMessageId: null, actions: { message: true, phone: true, screen: false } },
  activity: { mode: "sentinel", lastUserActivityAt: new Date().toISOString(), nextWakeAt: null, sleepPendingAt: null, sleepStage: null },
  sleep: { episodic: [], semantic: [], dreams: [], reflections: [], pendingDreams: [], nextCycle: 0, running: false }
});

function ensureProactive(thread) {
  if (!thread.proactive) {
    thread.proactive = { enabled: false, threadId: thread.id, message: "有一段时间没聊了，结合我们的上下文自然地来找我说句话。", intervalMin: 60, intervalMax: 60, nextDueAt: null, scheduledForUserMessageId: null, actions: { message: true, phone: true, screen: false } };
  }
  if (!thread.proactive.actions) thread.proactive.actions = { message: true, phone: true, screen: false };
  return thread.proactive;
}

function ensureActivity(thread) {
  if (!thread.activity) {
    thread.activity = { mode: "sentinel", lastUserActivityAt: new Date().toISOString(), nextWakeAt: null, sleepPendingAt: null };
  }
  ensureProactive(thread);
  if (!thread.sleep) thread.sleep = { episodic: [], semantic: [], dreams: [], reflections: [], pendingDreams: [], nextCycle: 0, running: false };
  if (!Array.isArray(thread.sleep.pendingDreams)) thread.sleep.pendingDreams = [];
  return thread.activity;
}

function isFarewell(text) {
  return /(晚安|睡了|先睡|去睡|明天见|先休息|good\s*night)/i.test(String(text || ""));
}

function markUserActivity(thread, content) {
  const activity = ensureActivity(thread);
  const proactive = ensureProactive(thread);
  const now = new Date();
  activity.mode = "sentinel";
  activity.lastUserActivityAt = now.toISOString();
  const interval = Math.max(1, Number(proactive.intervalMin) || 60);
  activity.nextWakeAt = proactive.enabled ? new Date(now.getTime() + interval * 60_000).toISOString() : null;
  proactive.nextDueAt = activity.nextWakeAt;
  activity.sleepPendingAt = isFarewell(content)
    ? new Date(now.getTime() + sleepDelayMinutes * 60_000).toISOString()
    : null;
  activity.sleepStartedAt = null;
  activity.sleepUntil = null;
  activity.nextDreamAt = null;
  activity.dreamCycle = 0;
  activity.sleepStage = null;
}

async function generateAutonomousMessage(thread, kind) {
  const proactive = ensureProactive(thread);
  const recent = (thread.messages || []).slice(-12).map((message) => `${message.role}: ${message.content}`).join("\n");
  const prompt = kind === "dream"
    ? "你正在睡眠中做梦。根据最近的聊天记忆，写一段连续梦境片段，保持和上一段梦的意象连贯，100字以内。只输出梦境正文。"
    : `你是一个会主动关心用户的 AI。用户已经有一段时间没有说话，请按照这条主动消息设定自然地发起联系：${proactive.message || "有一段时间没聊了，自然地来找用户说句话。"}。不要提到计时器、后台任务或系统。60字以内。`;
  const content = await callModel({
    messages: [
      { role: "system", content: prompt },
      { role: "user", content: recent || "还没有聊天记录。" }
    ],
    temperature: kind === "dream" ? 1.0 : 0.8
  });
  return { id: randomUUID(), role: "assistant", content, contentType: kind === "dream" ? "dream" : "sentinel", createdAt: new Date().toISOString() };
}

async function generateSentinelWake(thread) {
  const proactive = ensureProactive(thread);
  const actions = proactive.actions || { message: true, phone: true, screen: false };
  const recent = (thread.messages || []).slice(-12).map((message) => `${message.role}: ${message.content}`).join("\n");
  const contextSummary = thread.contextSummary ? `\n<context_summary>\n${thread.contextSummary}\n</context_summary>` : "";
  const memories = await searchMemories(recent || proactive.message || "主动联系");
  const retrievedMemories = memories.length
    ? `\n<retrieved_memories>\n${memories.map((memory) => `- ${memory}`).join("\n")}\n</retrieved_memories>`
    : "";
  const raw = await callModel({
    messages: [
      {
        role: "system",
        content: `你是一个会主动关心用户的 AI。根据主动消息设定“${proactive.message}”自然地发起联系。允许的动作：主动消息=${actions.message ? "是" : "否"}，主动电话=${actions.phone ? "是" : "否"}，查看屏幕=${actions.screen ? "是" : "否"}。关闭的动作绝对不要执行。主动电话仅用于用户长时间未回复、你有明确牵挂理由时；每天至多一次，只能在本地中午 12 点到晚上 11 点之间，不要在勿扰或睡眠期间来电。你还要自己决定下一次主动联系的间隔，单位是分钟，必须是 1 到 1440 的整数。自主唤醒要结合最近聊天、对话摘要和长期记忆，保持上下文连续。${contextSummary}${retrievedMemories}只输出 JSON，不要 Markdown：{"message":"要发给用户的话","reason":"来电卡片上的简短理由","action":"message|call|both|none","nextWakeMinutes":整数}`
      },
      { role: "user", content: recent || "还没有聊天记录。" }
    ],
    temperature: 0.8
  });
  const parsed = JSON.parse(raw.match(/\{[\s\S]*\}/)?.[0] || "{}");
  const message = typeof parsed.message === "string" && parsed.message.trim() ? parsed.message.trim() : raw.trim();
  const requestedAction = ["message", "call", "both", "none"].includes(parsed.action) ? parsed.action : "message";
  const localHour = Number(new Intl.DateTimeFormat("en-US", { timeZone: process.env.TZ || "Asia/Shanghai", hour: "2-digit", hourCycle: "h23" }).format(new Date()));
  const mayCallToday = !thread.lastPhoneCallDate || thread.lastPhoneCallDate !== new Date().toLocaleDateString("sv-SE", { timeZone: process.env.TZ || "Asia/Shanghai" });
  const phoneCallAllowed = actions.phone === true && thread.dnd !== true && mayCallToday && localHour >= 12 && localHour < 23;
  const messageAllowed = actions.message === true;
  const action = requestedAction === "both"
    ? (phoneCallAllowed && messageAllowed ? "both" : phoneCallAllowed ? "call" : messageAllowed ? "message" : "none")
    : requestedAction === "call"
      ? (phoneCallAllowed ? "call" : "none")
      : requestedAction === "message"
        ? (messageAllowed ? "message" : "none")
        : "none";
  const fallback = Math.max(1, Number(proactive.intervalMin) || 60);
  const nextWakeMinutes = Math.min(1440, Math.max(1, Math.round(Number(parsed.nextWakeMinutes) || fallback)));
  return {
    message: { id: randomUUID(), role: "assistant", content: message, contentType: "sentinel", createdAt: new Date().toISOString() },
    nextWakeMinutes,
    action,
    reason: String(parsed.reason || message).trim().slice(0, 180)
  };
}

async function readPushDevices() {
  try { return JSON.parse(await readFile(pushDevicesPath, "utf8")); }
  catch { return {}; }
}

async function savePushDevices(devices) {
  await mkdir(dataDir, { recursive: true });
  const temporary = `${pushDevicesPath}.tmp`;
  await writeFile(temporary, JSON.stringify(devices, null, 2), { mode: 0o600 });
  await chmod(temporary, 0o600);
  await rename(temporary, pushDevicesPath);
}

function appleProviderToken() {
  const teamID = String(process.env.APNS_TEAM_ID || "").trim();
  const keyID = String(process.env.APNS_KEY_ID || "").trim();
  const privateKey = String(process.env.APNS_PRIVATE_KEY || "").replace(/\\n/g, "\n");
  if (!teamID || !keyID || !privateKey) throw new Error("APNs 未配置：需要 APNS_TEAM_ID、APNS_KEY_ID、APNS_PRIVATE_KEY");
  const now = Math.floor(Date.now() / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "ES256", kid: keyID })}.${encode({ iss: teamID, iat: now })}`;
  const signature = cryptoSign("sha256", Buffer.from(unsigned), { key: createPrivateKey(privateKey), dsaEncoding: "ieee-p1363" }).toString("base64url");
  return `${unsigned}.${signature}`;
}

function sendAPNs(device, payload, { voip = false, expiration = 0 } = {}) {
  return new Promise((resolve, reject) => {
    const token = appleProviderToken();
    const environment = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const topic = String(process.env.APNS_BUNDLE_ID || "com.cai5232.LumiPush");
    const client = connectHTTP2(`https://${environment}`);
    let responseBody = "";
    client.on("error", reject);
    client.on("connect", () => {
      const headers = {
        ":method": "POST", ":path": `/3/device/${device.token}`,
        authorization: `bearer ${token}`, "apns-topic": voip ? `${topic}.voip` : topic,
        "apns-push-type": voip ? "voip" : "alert", "apns-priority": "10",
        "apns-expiration": String(expiration)
      };
      const request = client.request(headers);
      request.setEncoding("utf8");
      request.on("response", result => { if (result[":status"] < 200 || result[":status"] >= 300) responseBody = `APNs ${result[":status"]}`; });
      request.on("data", chunk => { responseBody += chunk; });
      request.on("end", () => { client.close(); responseBody ? reject(new Error(responseBody)) : resolve(); });
      request.on("error", error => { client.destroy(); reject(error); });
      request.end(JSON.stringify(payload));
    });
    client.setTimeout(8000, () => { client.destroy(new Error("APNs request timed out")); });
  });
}

async function sendIncomingCallPush(threadID, call) {
  const devices = await readPushDevices();
  const device = devices[threadID];
  if (!device) return { sent: false, reason: "device_not_registered" };
  const expiration = Math.floor(Date.parse(call.expiresAt) / 1000);
  const jobs = [];
  if (device.voipToken) jobs.push(sendAPNs({ ...device, token: device.voipToken, environment: device.voipEnvironment || device.environment }, { callId: call.callId, callerName: "沈屿", reason: call.reason, expiresAt: call.expiresAt, aps: { "content-available": 1 } }, { voip: true, expiration }));
  const isForeground = device.foreground && Date.now() - Date.parse(device.presenceUpdatedAt || 0) < 60_000;
  if (device.token && !device.voipToken && !isForeground) jobs.push(sendAPNs(device, { aps: { alert: { title: "沈屿来电话了", body: call.reason }, sound: "default", "content-available": 1 }, kind: "incoming_call", callId: call.callId }, { expiration }));
  if (!jobs.length) return { sent: false, reason: "no_push_token" };
  const results = await Promise.allSettled(jobs);
  const failures = results.filter(result => result.status === "rejected").map(result => result.reason?.message || "APNs error");
  return { sent: failures.length < jobs.length, errors: failures };
}

async function sendProactiveMessagePush(threadID, message) {
  const device = (await readPushDevices())[threadID];
  if (!device?.token) return;
  if (device.foreground && Date.now() - Date.parse(device.presenceUpdatedAt || 0) < 60_000) return;
  await sendAPNs(device, { aps: { alert: { title: "沈屿", body: String(message || "有一条新消息").slice(0, 200) }, sound: "default", "content-available": 1 }, kind: "assistant_message" });
}

function ensureCallStore(thread) {
  if (!thread.calls || typeof thread.calls !== "object") thread.calls = {};
  return thread.calls;
}

function stripCallMarkers(text) {
  let result = String(text || "");
  const hangup = /(?:⟪|《|【|\[)\s*(?:挂断|hangup)\s*(?:⟫|》|】|\])/i.test(result);
  result = result.replace(/(?:⟪|《|【|\[)\s*(?:挂断|hangup)\s*(?:⟫|》|】|\])/gi, "");
  return { text: result.trim(), hangupAfterPlayback: hangup };
}

async function synthesizeCallSpeech(text, tts, softVoice = false) {
  if (!tts?.enabled || !tts.apiKey || !tts.voiceID) return { speechError: "语音服务尚未配置" };
  try {
    const host = new URL(String(tts.baseURL || ""));
    const provider = tts.provider === "elevenlabs" ? "elevenlabs" : "minimax";
    const allowedHosts = provider === "elevenlabs" ? ["api.elevenlabs.io"] : ["api.minimaxi.com", "api.minimax.io"];
    if (host.protocol !== "https:" || !allowedHosts.includes(host.hostname)) throw new Error("语音服务地址不在允许的服务商域名内");
    const endpoint = provider === "elevenlabs"
      ? new URL(`/v1/text-to-speech/${encodeURIComponent(tts.voiceID)}`, host)
      : new URL("/v1/t2a_v2", host);
    const request = provider === "elevenlabs"
      ? { method: "POST", headers: { "content-type": "application/json", "xi-api-key": tts.apiKey, accept: "audio/mpeg" }, body: JSON.stringify({ text, model_id: tts.model || "eleven_v4_turbo", voice_settings: { stability: 0.5, similarity_boost: 0.75, speed: softVoice ? 0.82 : 1 } }) }
      : { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${tts.apiKey}` }, body: JSON.stringify({ model: tts.model || "speech-2.8-hd", text, stream: false, voice_setting: { voice_id: tts.voiceID, speed: softVoice ? 0.82 : 1, vol: softVoice ? 0.62 : 1, pitch: 0 }, audio_setting: { audio_sample_rate: 32000, bitrate: 128000, format: "mp3" } }) };
    const response = await fetch(endpoint, { ...request, signal: AbortSignal.timeout(45_000), redirect: "error" });
    if (!response.ok) throw new Error(`语音服务返回 ${response.status}`);
    if (provider === "elevenlabs") {
      const audio = Buffer.from(await response.arrayBuffer());
      return { speechAudioBase64: audio.toString("base64"), speechDuration: null, speechScript: text };
    }
    const data = await response.json();
    const audioHex = data?.data?.audio;
    if (!audioHex || !/^(?:[\da-f]{2})+$/i.test(audioHex)) throw new Error(data?.base_resp?.status_msg || "MiniMax 没有返回 MP3 音频");
    return { speechAudioBase64: Buffer.from(audioHex, "hex").toString("base64"), speechDuration: null, speechScript: text };
  } catch (error) { return { speechError: String(error.message || error).slice(0, 300) }; }
}

async function createPendingCall(threadID, thread, reason) {
  const calls = ensureCallStore(thread);
  const existing = Object.values(calls).find(call => call.status === "pending" && Date.parse(call.expiresAt) > Date.now());
  if (existing) return existing;
  const call = { callId: randomUUID().toLowerCase(), reason: String(reason || "想听听你的声音").slice(0, 180), status: "pending", createdAt: new Date().toISOString(), expiresAt: new Date(Date.now() + callInviteSeconds * 1000).toISOString(), turns: [] };
  calls[call.callId] = call;
  const push = await sendIncomingCallPush(threadID, call).catch(error => ({ sent: false, reason: error.message }));
  call.push = push;
  return call;
}

function missedCallMessage(call) {
  return { id: randomUUID(), role: "assistant", content: `📞 没接到你\n我刚才想问问你：${call.reason}。不急，等你回来再说。`, contentType: "call_status", callID: call.callId, callInitiator: "assistant", callStatus: "missed", createdAt: new Date().toISOString() };
}

async function expirePendingCalls(thread) {
  let changed = false;
  for (const call of Object.values(ensureCallStore(thread))) {
    if (call.status !== "pending" || Date.parse(call.expiresAt) > Date.now()) continue;
    call.status = "missed";
    call.endedAt = new Date().toISOString();
    thread.messages.push(missedCallMessage(call));
    changed = true;
  }
  return changed;
}

function safeJSON(text, fallback = {}) {
  try { return JSON.parse(text.match(/\{[\s\S]*\}/)?.[0] || text); } catch { return fallback; }
}

function sleepMemories(thread) {
  return (thread.messages || []).slice(-80).map((m, index) => ({
    id: m.id || `m${index}`,
    ts: Date.parse(m.createdAt || 0) || Date.now(),
    content: `${m.role === "user" ? "用户" : "AI"}：${m.content}`,
    valence: m.role === "user" ? 0.1 : 0,
    arousal: Math.min(1, String(m.content || "").length / 300),
    rehearsalCount: 0,
    reward: 0,
    expectedReward: 0
  }));
}

function salience(memory, goals = []) {
  const days = Math.max(0, (Date.now() - memory.ts) / 86400000);
  const recent = Math.exp(-days / 3);
  const goal = goals.some((g) => memory.content.toLowerCase().includes(String(g).toLowerCase())) ? 1 : 0;
  return Math.abs(memory.reward - memory.expectedReward) + 0.8 * memory.arousal + 0.5 * recent + 0.4 / (1 + memory.rehearsalCount) + 0.7 * goal;
}

function formatSleepMemories(memories, limit = 12) {
  return memories.slice(0, limit).map((m) => `- [${m.id}] valence=${m.valence.toFixed(2)} arousal=${m.arousal.toFixed(2)} :: ${m.content.slice(0, 220)}`).join("\n") || "（没有记忆）";
}

async function runSleepStage(thread, stage, cycle, context, seedIds = []) {
  const prompt = SLEEP_STAGE_PROMPTS[stage];
  const output = await callModel({
    messages: [{ role: "system", content: prompt.system }, { role: "user", content: prompt.user(context) }],
    temperature: stage === "n3_deep" ? 0.2 : stage === "rem" || stage === "nightmare" ? 1.0 : 0.6
  });
  const record = { id: randomUUID(), stage, cycle, content: output, seedIds, createdAt: new Date().toISOString() };
  thread.sleep.dreams.push(record);
  return record;
}

async function runFullSleepCycle(thread) {
  const activity = ensureActivity(thread);
  const sleep = thread.sleep;
  if (sleep.running) return;
  sleep.running = true;
  const all = sleepMemories(thread);
  const goals = thread.goals || [];
  const obstacles = thread.obstacles || [];
  const scored = all.sort((a, b) => salience(b, goals) - salience(a, goals));
  const nightLog = [];
  try {
    for (let cycle = 0; cycle < sleepCycles; cycle += 1) {
      activity.sleepStage = `n1_drift_${cycle + 1}`;
      const seeds = scored.slice(0, 6 + cycle);
      const seedIds = seeds.map((m) => m.id);
      const n1 = await runSleepStage(thread, "n1_drift", cycle, { goals: goals.join(", ") || "（无）", memories: formatSleepMemories(seeds) }, seedIds);
      const n2 = await runSleepStage(thread, "n2_spindle", cycle, { n1: n1.content }, seedIds);
      const semanticText = sleep.semantic.map((f) => `- ${f.fact}`).join("\n") || "（空）";
      const n3 = await runSleepStage(thread, "n3_deep", cycle, { n2: n2.content, semantic: semanticText }, seedIds);
      const n3Json = safeJSON(n3.content);
      for (const fact of (n3Json.facts || [])) {
        if (fact?.fact && Number(fact.confidence ?? 0.6) >= 0.6) sleep.semantic.push({ id: randomUUID(), fact: fact.fact, sources: fact.sources || seedIds, confidence: Number(fact.confidence ?? 0.6), createdAt: new Date().toISOString() });
      }
      activity.sleepStage = `rem_${cycle + 1}`;
      const rem = await runSleepStage(thread, "rem", cycle, { seeds: formatSleepMemories(seeds, 6), semantic: sleep.semantic.map((f) => f.fact).join("；") || "（空）", goals: goals.join(", ") || "（无）", cycle: cycle + 1 }, seedIds);
      sleep.pendingDreams.push({ content: rem.content, sleepCycle: cycle + 1 });
      nightLog.push({ stage: "rem", cycle, text: rem.content });
      if (cycle >= 1 && Math.random() < 0.35 && seeds.some((m) => m.valence < -0.3)) {
        activity.sleepStage = `nightmare_${cycle + 1}`;
        const trauma = seeds.filter((m) => m.valence < -0.3);
        const nightmare = await runSleepStage(thread, "nightmare", cycle, { trauma: formatSleepMemories(trauma, 3), competence: thread.competence || "尚未明确" }, trauma.map((m) => m.id));
        nightLog.push({ stage: "nightmare", cycle, text: nightmare.content });
        activity.sleepStage = "nightmare_awake";
        if (Math.random() < 0.5) { activity.mode = "sentinel"; activity.sleepStage = "insomnia"; break; }
      }
      if (cycle === sleepCycles - 1) {
        activity.sleepStage = "lucid";
        const lucid = await runSleepStage(thread, "lucid", cycle, { goals: goals.join(", ") || "（无）", obstacles: obstacles.join("；") || "（无）" }, seedIds);
        nightLog.push({ stage: "lucid", cycle, text: lucid.content });
      }
    }
    activity.sleepStage = "reflection";
    const reflection = await runSleepStage(thread, "reflection", sleepCycles, { summary: nightLog.map((x) => `[${x.stage} cycle ${x.cycle}]\n${x.text.slice(0, 900)}`).join("\n\n"), state: JSON.stringify({ goals, competence: thread.competence || null }) });
    const parsed = safeJSON(reflection.content, { _parseError: true, raw: reflection.content.slice(0, 500) });
    sleep.reflections.push({ ...parsed, raw: reflection.content, createdAt: new Date().toISOString() });
    sleep.nextCycle += 1;
    activity.sleepStage = activity.mode === "sentinel" ? "insomnia" : "awake";
  } finally {
    sleep.running = false;
  }
}

async function runBackgroundPulse() {
  const threads = await readThreads();
  const now = Date.now();
  let changed = false;
  for (const thread of Object.values(threads)) {
    const activity = ensureActivity(thread);
    const proactive = ensureProactive(thread);
    if (await expirePendingCalls(thread)) {
      const missed = Object.values(ensureCallStore(thread)).filter(call => call.status === "missed" && !call.voicemailPushed).at(-1);
      if (missed) {
        missed.voicemailPushed = true;
        sendProactiveMessagePush(thread.id || "default", `📞 没接到你：${missed.reason}。不急，等你回来再说。`).catch(error => console.warn(`missed-call push skipped: ${error.message}`));
      }
      changed = true;
    }
    const lastUserAt = Date.parse(activity.lastUserActivityAt || 0);
    if (activity.mode === "sentinel" && activity.sleepPendingAt && Date.parse(activity.sleepPendingAt) <= now && lastUserAt <= Date.parse(activity.sleepPendingAt)) {
      if (Math.random() < sleepInsomniaProbability) {
        activity.mode = "sentinel";
        activity.sleepStage = "insomnia";
        const interval = Math.max(1, Number(proactive.intervalMin) || 60);
        activity.nextWakeAt = new Date(now + interval * 60_000).toISOString();
        activity.sleepPendingAt = null;
        changed = true;
        continue;
      }
      activity.mode = "sleeping";
      activity.sleepStartedAt = new Date(now).toISOString();
      activity.sleepUntil = new Date(now + sleepHours * 3_600_000).toISOString();
      activity.nextDreamAt = new Date(now + 2 * 3_600_000).toISOString();
      activity.dreamCycle = 0;
      activity.sleepStage = "n1_drift";
      if (!thread.sleep?.running) {
        try { await runFullSleepCycle(thread); } catch (error) { console.warn(`sleep cycle failed: ${error.message}`); }
      }
      changed = true;
    }
    if (activity.mode === "sleeping") {
      if (activity.sleepUntil && Date.parse(activity.sleepUntil) <= now) {
        activity.mode = "sentinel";
        const interval = Math.max(1, Number(proactive.intervalMin) || 60);
        activity.nextWakeAt = new Date(now + interval * 60_000).toISOString();
        activity.sleepStage = "awake";
        changed = true;
      } else if (activity.nextDreamAt && Date.parse(activity.nextDreamAt) <= now && thread.sleep?.pendingDreams?.length) {
        const dream = thread.sleep.pendingDreams.shift();
        thread.messages.push({ id: randomUUID(), role: "assistant", content: dream.content, contentType: "dream", sleepCycle: dream.sleepCycle, createdAt: new Date().toISOString() });
        activity.dreamCycle = (activity.dreamCycle || 0) + 1;
        activity.nextDreamAt = new Date(now + 2 * 3_600_000).toISOString();
        changed = true;
      }
    } else if (proactive.enabled && activity.mode === "sentinel" && activity.nextWakeAt && Date.parse(activity.nextWakeAt) <= now && (proactive.actions?.message !== false || proactive.actions?.phone === true || proactive.actions?.screen === true)) {
      try {
        const wake = await generateSentinelWake(thread);
        if (wake.action === "message" || wake.action === "both") {
          thread.messages.push(wake.message);
          sendProactiveMessagePush(thread.id || "default", wake.message.content).catch(error => console.warn(`message push skipped: ${error.message}`));
        }
        if (wake.action === "call" || wake.action === "both") {
          const call = await createPendingCall(thread.id || "default", thread, wake.reason);
          thread.lastPhoneCallDate = new Date().toLocaleDateString("sv-SE", { timeZone: process.env.TZ || "Asia/Shanghai" });
          call.reason = wake.reason;
        }
        if (wake.action === "none") {
          activity.nextWakeAt = new Date(now + wake.nextWakeMinutes * 60_000).toISOString();
          proactive.nextDueAt = activity.nextWakeAt;
          changed = true;
          continue;
        }
        activity.nextWakeAt = new Date(now + wake.nextWakeMinutes * 60_000).toISOString();
        proactive.nextDueAt = activity.nextWakeAt;
        changed = true;
      } catch (error) { console.warn(`sentinel skipped: ${error.message}`); }
    }
  }
  if (changed) await saveThreads(threads);
}

async function readThreads() {
  await mkdir(dataDir, { recursive: true });
  try { return JSON.parse(await readFile(threadPath, "utf8")); }
  catch { const initial = { default: seed() }; await writeFile(threadPath, JSON.stringify(initial, null, 2)); return initial; }
}

async function saveThreads(threads) { await writeFile(threadPath, JSON.stringify(threads, null, 2)); }

function estimateTokens(text) { return Math.ceil(String(text || "").length / 4); }
function messageTokens(messages) { return messages.reduce((total, message) => total + estimateTokens(message.content) + 8, 0); }

function anthropicMessages(messages) {
  const system = [];
  const converted = [];
  const append = message => {
    const previous = converted.at(-1);
    if (previous?.role === message.role) {
      const priorContent = Array.isArray(previous.content) ? previous.content : [{ type: "text", text: String(previous.content || "") }];
      const nextContent = Array.isArray(message.content) ? message.content : [{ type: "text", text: String(message.content || "") }];
      previous.content = [...priorContent, ...nextContent];
    } else converted.push(message);
  };
  for (const message of messages) {
    if (message.role === "system") { system.push(String(message.content || "")); continue; }
    if (message.role === "tool") {
      append({ role: "user", content: [{ type: "tool_result", tool_use_id: message.tool_call_id, content: String(message.content || "") }] });
      continue;
    }
    if (message.role === "assistant" && Array.isArray(message.tool_calls)) {
      const content = [];
      if (message.content) content.push({ type: "text", text: String(message.content) });
      for (const call of message.tool_calls) {
        let input = {};
        try { input = JSON.parse(call.function?.arguments || "{}"); } catch {}
        content.push({ type: "tool_use", id: call.id, name: call.function?.name, input });
      }
      append({ role: "assistant", content });
      continue;
    }
    append({ role: message.role === "assistant" ? "assistant" : "user", content: String(message.content || "") });
  }
  return { system: system.join("\n\n"), messages: converted };
}

async function callModel({ messages, temperature = 0.8, tools = undefined, tool_choice = undefined, customProvider = undefined, modelOverride = "" }) {
  const apiURL = customProvider
    ? `${String(customProvider.baseURL || "").replace(/\/+$/, "")}/${String(customProvider.chatPath || (customProvider.apiFormat === "anthropic" ? "/messages" : "/chat/completions")).replace(/^\/+/, "")}`
    : process.env.LUMI_MODEL_API_URL;
  const apiKey = customProvider?.apiKey || process.env.LUMI_MODEL_API_KEY;
  const model = customProvider ? modelOverride : process.env.LUMI_MODEL_NAME;
  if (!apiURL || !apiKey || !model) {
    if (customProvider) throw new Error("中转站配置不完整：请检查 API Key、基址和模型名称");
    throw new Error("模型服务尚未配置：请在 Zeabur 设置 LUMI_MODEL_API_URL、LUMI_MODEL_API_KEY、LUMI_MODEL_NAME");
  }

  const anthropic = customProvider?.apiFormat === "anthropic";
  const headers = { "content-type": "application/json" };
  if (anthropic) {
    headers["x-api-key"] = apiKey;
    headers["anthropic-version"] = "2023-06-01";
  } else {
    headers.authorization = `Bearer ${apiKey}`;
  }
  const anthropicInput = anthropic ? anthropicMessages(messages) : null;
  const requestMessages = anthropic ? anthropicInput.messages : messages;
  const requestTools = tools?.map(tool => anthropic
    ? { name: tool.function.name, description: tool.function.description || "", input_schema: tool.function.parameters || { type: "object", properties: {} } }
    : tool);
  const payload = anthropic
    ? { model, max_tokens: 4096, temperature, messages: requestMessages, ...(anthropicInput.system ? { system: anthropicInput.system } : {}), ...(requestTools?.length ? { tools: requestTools, tool_choice: tool_choice === "auto" ? { type: "auto" } : undefined } : {}) }
    : { model, messages, temperature, ...(requestTools?.length ? { tools: requestTools, tool_choice } : {}) };
  const response = await fetch(apiURL, {
    method: "POST",
    headers,
    body: JSON.stringify(payload)
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data?.error?.message || data?.error || `模型服务返回 ${response.status}`);
  let message;
  if (anthropic) {
    const blocks = Array.isArray(data?.content) ? data.content : [];
    const text = blocks.filter(block => block.type === "text").map(block => block.text || "").join("");
    const toolCalls = blocks.filter(block => block.type === "tool_use").map(block => ({
      id: block.id, type: "function", function: { name: block.name, arguments: JSON.stringify(block.input || {}) }
    }));
    message = { role: "assistant", content: text, ...(toolCalls.length ? { tool_calls: toolCalls } : {}) };
  } else {
    message = data?.choices?.[0]?.message;
  }
  if (!message || (typeof message.content !== "string" && !message.tool_calls?.length)) throw new Error("模型没有返回内容");
  return tools ? message : message.content.trim();
}

async function memoryRequest(path, payload) {
  const headers = { "content-type": "application/json" };
  if (process.env.LUMI_MEMORY_API_KEY) headers.authorization = `Bearer ${process.env.LUMI_MEMORY_API_KEY}`;
  const response = await fetch(`${memoryAPI}${path.startsWith("/") ? path : `/${path}`}`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(4000)
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data?.error?.message || data?.error || `记忆库返回 ${response.status}`);
  return data;
}

function fallbackKeywords(input) {
  return [...new Set(String(input).split(/[^\p{L}\p{N}]+/u).map((part) => part.trim()).filter((part) => part.length > 1))].slice(0, 8);
}

async function extractMemoryKeywords(input) {
  try {
    const raw = await callModel({
      messages: [
        { role: "system", content: "从用户这条消息中提取用于检索长期记忆的关键词。只输出 JSON 数组，例如 [\"称呼\",\"偏好\"]，不要解释，不要复述原句。" },
        { role: "user", content: input }
      ],
      temperature: 0
    });
    const parsed = JSON.parse(raw.match(/\[[\s\S]*\]/)?.[0] || "[]");
    if (Array.isArray(parsed)) return parsed.filter((item) => typeof item === "string" && item.trim()).slice(0, 8);
  } catch {}
  return fallbackKeywords(input);
}

function normalizeMemories(data) {
  const list = Array.isArray(data) ? data : data.memories || data.results || data.data || [];
  return list.map((item) => {
    if (typeof item === "string") return item;
    return item.content || item.text || item.memory || item.value || item.summary || "";
  }).filter(Boolean).slice(0, 8);
}

async function searchMemories(input) {
  const keywords = await extractMemoryKeywords(input);
  if (!keywords.length) return [];
  const paths = [...new Set([memorySearchPath, "/search", "/api/search", "/v1/memories/search", "/api/memories/search"])]
    .filter(Boolean);
  for (const path of paths) {
    try {
      const data = await memoryRequest(path, { query: keywords.join(" "), text: keywords.join(" "), keywords, limit: 8, topK: 8 });
      return normalizeMemories(data);
    } catch (error) {
      if (path === paths.at(-1)) console.warn(`memory search skipped: ${error.message}`);
    }
  }
  return [];
}

async function writeMemory(content, threadId) {
  const paths = [...new Set([memoryWritePath, "/memories", "/api/memories", "/v1/memories", "/api/memory"])]
    .filter(Boolean);
  for (const path of paths) {
    try {
      await memoryRequest(path, { content, memory: content, text: content, source: "lumi", threadId });
      return true;
    } catch (error) {
      if (path === paths.at(-1)) console.warn(`memory write skipped: ${error.message}`);
    }
  }
  return false;
}

async function compactThread(thread) {
  const messages = thread.messages || [];
  if (messageTokens(messages) < contextLimit * compactAt) return false;
  let tail = [];
  let tailCount = 0;
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const cost = estimateTokens(messages[index].content) + 8;
    if (tail.length && tailCount + cost > tailTokens) break;
    tail.unshift(messages[index]);
    tailCount += cost;
  }
  const older = messages.slice(0, Math.max(0, messages.length - tail.length));
  if (!older.length) return false;
  const previous = thread.contextSummary ? `已有摘要：\n${thread.contextSummary}\n\n` : "";
  const prompt = `${previous}请把下面的聊天历史压缩成长期上下文摘要。只输出 XML，不要解释：
<context_summary>
  <user_profile>称呼、偏好、语言习惯与长期信息</user_profile>
  <relationship_dynamic>关系背景、相处氛围与角色状态</relationship_dynamic>
  <key_decisions_and_facts>确认过的事实、约定、重要事件</key_decisions_and_facts>
  <active_topics_and_todos>当前话题、未完成事项与下一步</active_topics_and_todos>
</context_summary>
聊天历史：
${older.map((message) => `${message.role}: ${message.content}`).join("\n")}`;
  thread.contextSummary = await callModel({
    messages: [
      { role: "system", content: "你是上下文压缩器。保持事实，不编造，不输出聊天回复。" },
      { role: "user", content: prompt }
    ],
    temperature: 0.2
  });
  thread.compactionCount = (thread.compactionCount || 0) + 1;
  thread.compactedAt = new Date().toISOString();
  thread.compactedThroughMessageId = older[older.length - 1].id;
  return true;
}

async function generateReply({ input, systemPrompt, thread, model = "", provider = "", customProvider = undefined, context = "" }) {
  await compactThread(thread);
  const system = process.env.LUMI_SYSTEM_PROMPT || systemPrompt || "使用中文回复。";
  const summary = thread.contextSummary ? `\n\n<context_summary>\n${thread.contextSummary}\n</context_summary>` : "";
  const memories = await searchMemories(input);
  const retrieved = memories.length
    ? `\n\n<retrieved_memories>\n${memories.map((memory) => `- ${memory}`).join("\n")}\n</retrieved_memories>`
    : "";
  const history = (thread.messages || []).slice(-20).map((message) => ({ role: message.role, content: message.content }));
  const liveContext = typeof context === "string" && context.trim() ? `\n\n<live_context>\n${context.trim().slice(0, 6000)}\n</live_context>` : "";
  const messages = [{ role: "system", content: `${system}${summary}${retrieved}${liveContext}\n\nLumi 有可选的饮食本功能。用户提到记饮食、查询饮食记录、口味忌口、评价菜品、推荐吃什么或打开饮食本时，先调用 discover_food_notebook 获取相关功能；其他对话不要调用。MCP 工具只在任务相关时使用；可能发送、写入或修改数据的工具由用户在设置页手动执行。\n\n如果这条对话包含值得长期保留的新事实、偏好或约定，你可以在回复末尾添加 <memory>要记住的内容</memory>；不值得记忆时不要添加。不要向用户解释这个标签。` }, ...history, { role: "user", content: input }];
  const discoveryTool = { type: "function", function: { name: "discover_food_notebook", description: "按需发现并启用 Lumi 饮食本工具。用户要记录/查询饮食、更新口味、评价菜品、获取饮食推荐或打开饮食本时调用；否则不调用。", parameters: { type: "object", properties: {}, additionalProperties: false } } };
  const mcpSettings = await mcpClientStore.read();
  let refreshedMcpServers = false;
  for (const server of mcpSettings.servers) {
    if (!server.enabled || server.connectedAt) continue;
    try {
      const connection = await connectMcpServer(server);
      server.tools = connection.tools;
      server.connectedAt = new Date().toISOString();
      server.error = '';
      refreshedMcpServers = true;
    } catch (error) {
      server.error = String(error.message || error).slice(0, 500);
      refreshedMcpServers = true;
    }
  }
  if (refreshedMcpServers) await mcpClientStore.save(mcpSettings);
  const mcpServers = mcpSettings.servers.filter(server => server.enabled);
  const mcpToolMap = new Map();
  const mcpTools = [];
  for (const [serverIndex, server] of mcpServers.entries()) {
    for (const [toolIndex, tool] of (Array.isArray(server.tools) ? server.tools : []).entries()) {
      if (!tool?.name || tool.disabled === true) continue;
      const name = `mcp_${serverIndex}_${toolIndex}_${String(tool.name).replace(/[^A-Za-z0-9_-]/g, "_")}`.slice(0, 64);
      mcpToolMap.set(name, { server, tool });
      mcpTools.push({ type: "function", function: { name, description: `${server.name}: ${String(tool.description || "").slice(0, 500)}`, parameters: tool.inputSchema && typeof tool.inputSchema === "object" ? tool.inputSchema : { type: "object", properties: {} } } });
    }
  }
  let activeTools = [discoveryTool, ...mcpTools];
  let foodToolsEnabled = false;
  let foodActionCompleted = false;
  let answer;
  for (let turn = 0; turn < 5; turn += 1) {
    const message = await callModel({ messages, tools: activeTools, tool_choice: "auto", customProvider: provider === "custom" ? customProvider : undefined, modelOverride: model });
    if (!message.tool_calls?.length) { answer = String(message.content || "").trim(); break; }
    messages.push(message);
    for (const call of message.tool_calls) {
      if (call.function?.name === "discover_food_notebook") {
        if (!foodToolsEnabled) {
          const food = await foodContext();
          messages.push({ role: "tool", tool_call_id: call.id, content: `已启用饮食本功能。当前信息：\n${food}` });
          activeTools = [...foodTools, ...mcpTools];
          foodToolsEnabled = true;
        } else {
          messages.push({ role: "tool", tool_call_id: call.id, content: "饮食本功能已经启用，请直接选择合适的饮食工具。" });
        }
        continue;
      }
      let args = {}; try { args = JSON.parse(call.function?.arguments || "{}"); } catch {}
      const mcpEntry = mcpToolMap.get(call.function?.name);
      if (mcpEntry) {
        if (/(send|delete|remove|write|create|update|edit|run|exec|purchase|payment|publish|commit|transfer|post|message|email|mail)/i.test(mcpEntry.tool.name)) {
          messages.push({ role: "tool", tool_call_id: call.id, content: "此工具可能修改或发送数据；请在 Lumi 设置 → MCP 工具中手动执行。" });
        } else {
          try {
            const result = await callMcpTool(mcpEntry.server, mcpEntry.tool.name, args);
            messages.push({ role: "tool", tool_call_id: call.id, content: JSON.stringify(result).slice(0, 30000) });
          } catch (error) {
            messages.push({ role: "tool", tool_call_id: call.id, content: JSON.stringify({ error: String(error.message || error).slice(0, 1000) }) });
          }
        }
        continue;
      }
      const result = await executeFoodTool(call.function?.name, args);
      messages.push({ role: "tool", tool_call_id: call.id, content: String(result || "完成") });
      foodActionCompleted = true;
    }
  }
  if (!answer && !foodActionCompleted) throw new Error("模型没有返回有效内容");
  const raw = answer || "我已经把这件事记进饮食本了。";
  const memoryMatch = raw.match(/<memory>([\s\S]*?)<\/memory>/i);
  const memoryContent = memoryMatch?.[1]?.trim();
  const content = raw.replace(/<memory>[\s\S]*?<\/memory>/gi, "").trim();
  const memorySaved = memoryContent ? await writeMemory(memoryContent, thread.id) : false;
  return { content, memorySaved };
}

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "access-control-allow-origin": "*" });
  res.end(JSON.stringify(body));
}

function mcpRequestAuthorized(req) {
  const expected = String(process.env.LUMI_PUSH_API_TOKEN || "");
  const supplied = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!expected || !supplied) return false;
  const expectedBytes = Buffer.from(expected), suppliedBytes = Buffer.from(supplied);
  return expectedBytes.length === suppliedBytes.length && timingSafeEqual(expectedBytes, suppliedBytes);
}

const pushRequestAuthorized = mcpRequestAuthorized;

async function body(req) {
  let raw = "";
  for await (const chunk of req) raw += chunk;
  return raw ? JSON.parse(raw) : {};
}

function proxyDuetto(req, res) {
  const headers = { ...req.headers, host: `127.0.0.1:${duettoPort}` };
  if (req.url?.split("?")[0] === "/api/auth/session") {
    if (!pushRequestAuthorized(req)) return send(res, 401, { ok: false, error: "unauthorized" });
    headers["x-lumi-native-auth"] = "1";
  }
  const upstream = httpRequest({
    hostname: "127.0.0.1", port: duettoPort, method: req.method, path: req.url,
    headers
  }, (response) => {
    res.writeHead(response.statusCode || 502, response.headers);
    response.pipe(res);
  });
  upstream.on("error", () => {
    if (!res.headersSent) send(res, 502, { error: "together_listen_unavailable" });
    else res.destroy();
  });
  req.pipe(upstream);
}

const server = createServer(async (req, res) => {
  if (req.url?.startsWith("/api/") || req.url?.startsWith("/pkg/")) return proxyDuetto(req, res);
  if (req.method === "GET" && req.url?.split("?")[0] === "/together-listen") {
    res.writeHead(302, { location: "/pkg/index.html" });
    return res.end();
  }
  if (req.method === "OPTIONS") return send(res, 204, {});
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (req.method === "GET" && url.pathname === "/health") return send(res, 200, { ok: true });
    if (url.pathname.startsWith("/v1/music/")) {
      if (!mcpRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
      const route = url.pathname.slice("/v1/music/".length);
      if (route === "room/state" && req.method === "GET") {
        const room = String(url.searchParams.get("room") || "main").slice(0, 64);
        return send(res, 200, { state: await readMusicRoomState(room) });
      }
      if (route === "room/state" && req.method === "PUT") {
        const input = await body(req);
        const room = String(input.room || "main").slice(0, 64);
        const songID = String(input.songID || "").slice(0, 32);
        const title = String(input.title || "").slice(0, 200);
        if (!songID || !title) return send(res, 400, { error: "song_required" });
        const previous = await readMusicRoomState(room);
        const state = {
          room, songID, title, artist: String(input.artist || "").slice(0, 200),
          cover: String(input.cover || "").replace(/^http:/, "https:").slice(0, 2000),
          durationSeconds: Math.max(0, Math.min(86400, Number(input.durationSeconds) || 0)),
          positionSeconds: Math.max(0, Math.min(86400, Number(input.positionSeconds) || 0)),
          isPlaying: Boolean(input.isPlaying), actorID: String(input.actorID || "").slice(0, 80),
          revision: (Number(previous?.revision) || 0) + 1, updatedAt: Date.now()
        };
        await writeMusicRoomState(room, state);
        return send(res, 200, { state });
      }
      if (route === "room/messages" && req.method === "GET") {
        const room = String(url.searchParams.get("room") || "main").slice(0, 64);
        return send(res, 200, { messages: await readMusicRoomMessages(room) });
      }
      if (route === "room/messages" && req.method === "POST") {
        const input = await body(req);
        const room = String(input.room || "main").slice(0, 64);
        const text = String(input.text || "").trim().slice(0, 2000);
        if (!text) return send(res, 400, { error: "message_required" });
        const message = {
          id: randomUUID(), actorID: String(input.actorID || "").slice(0, 80),
          sender: String(input.sender || "我").slice(0, 80), text, createdAt: Date.now()
        };
        await appendMusicRoomMessage(room, message);
        return send(res, 201, { message });
      }
      if (route === "netease/status" && req.method === "GET") {
        const profile = await ncmProfile();
        return send(res, 200, { logged: Boolean(profile), nickname: profile?.nickname || "" });
      }
      if (route === "netease/qr" && req.method === "GET") {
        try {
          const keyResult = await ncm.login_qr_key({});
          const key = keyResult.body?.data?.unikey;
          const qrResult = await ncm.login_qr_create({ key, qrimg: true });
          return send(res, 200, { key, image: qrResult.body?.data?.qrimg || "" });
        } catch (error) { return send(res, 502, { error: error.message || "qr_unavailable" }); }
      }
      if (route === "netease/qr/check" && req.method === "GET") {
        try {
          const result = await ncm.login_qr_check({ key: String(url.searchParams.get("key") || "") });
          const code = Number(result.body?.code || 0);
          if (code === 803 && result.body?.cookie) {
            await saveNcmCookie(result.body.cookie);
            const profile = await ncmProfile();
            return send(res, 200, { code, logged: true, nickname: profile?.nickname || "" });
          }
          return send(res, 200, { code, message: String(result.body?.message || "") });
        } catch (error) { return send(res, 502, { error: error.message || "qr_check_failed" }); }
      }
      if (route === "netease/search" && req.method === "GET") {
        const keywords = String(url.searchParams.get("q") || "").trim().slice(0, 100);
        if (!keywords) return send(res, 200, { songs: [] });
        try {
          const result = await ncm.cloudsearch({ keywords, limit: 30, cookie: ncmCookie });
          return send(res, 200, { songs: (result.body?.result?.songs || []).map(normalizeMusicSong) });
        } catch (error) { return send(res, 502, { error: error.message || "search_failed" }); }
      }
      if (route === "netease/song-url" && req.method === "GET") {
        try {
          const result = await ncm.song_url_v1({ id: String(url.searchParams.get("id") || ""), level: "standard", cookie: ncmCookie });
          const streamURL = result.body?.data?.[0]?.url || "";
          return send(res, 200, { url: String(streamURL).replace(/^http:/, "https:") });
        } catch (error) { return send(res, 502, { error: error.message || "stream_unavailable" }); }
      }
      if (route === "netease/logout" && req.method === "POST") {
        await saveNcmCookie("");
        return send(res, 200, { ok: true });
      }
      return send(res, 404, { error: "not_found" });
    }
    const pushMatch = url.pathname.match(/^\/v1\/push\/(register|voip\/register|presence)$/);
    if (pushMatch) {
      if (!pushRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
      const input = req.method === "POST" ? await body(req) : {};
      const threadID = String(input.threadId || "default").slice(0, 80);
      const devices = await readPushDevices();
      const device = devices[threadID] || { environment: "production" };
      if (pushMatch[1] === "presence" && req.method === "POST") {
        device.foreground = Boolean(input.foreground);
        device.presenceUpdatedAt = new Date().toISOString();
      } else if (pushMatch[1] === "register" && req.method === "POST") {
        const token = String(input.token || "");
        if (!/^[\da-f]{32,512}$/i.test(token)) return send(res, 400, { error: "invalid_device_token" });
        if (!["sandbox", "production"].includes(input.environment)) return send(res, 400, { error: "invalid_push_environment" });
        device.token = token;
        device.environment = input.environment;
      } else if (pushMatch[1] === "voip/register" && req.method === "POST") {
        const token = String(input.token || "");
        if (!/^[\da-f]{32,512}$/i.test(token)) return send(res, 400, { error: "invalid_voip_token" });
        if (!["sandbox", "production"].includes(input.environment)) return send(res, 400, { error: "invalid_push_environment" });
        device.voipToken = token;
        device.voipEnvironment = input.environment;
      } else return send(res, 405, { error: "method_not_allowed" });
      devices[threadID] = device;
      await savePushDevices(devices);
      return send(res, 200, { ok: true, registered: Boolean(device.token), voipRegistered: Boolean(device.voipToken) });
    }
    if (url.pathname === "/v1/mcp/servers") {
      if (!mcpRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
      if (req.method === "GET") {
        const settings = await mcpClientStore.read();
        return send(res, 200, { ...settings, servers: settings.servers.map(server => ({ ...server, headers: Object.fromEntries(Object.keys(server.headers).map(key => [key, "••••••"])) })) });
      }
      if (req.method === "PUT") {
        try {
          const settings = await mcpClientStore.save(await body(req));
          return send(res, 200, { ...settings, servers: settings.servers.map(server => ({ ...server, headers: Object.fromEntries(Object.keys(server.headers).map(key => [key, "••••••"])) })) });
        }
        catch (error) { return send(res, error.status || 400, { error: error.message }); }
      }
      return send(res, 405, { error: "method_not_allowed" });
    }
    const mcpServerToggle = url.pathname.match(/^\/v1\/mcp\/servers\/([^/]+)$/);
    if (mcpServerToggle) {
      if (!mcpRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
      if (req.method !== "PATCH") return send(res, 405, { error: "method_not_allowed" });
      const input = await body(req);
      if (typeof input.enabled !== "boolean") return send(res, 400, { error: "enabled_must_be_boolean" });
      const settings = await mcpClientStore.read();
      const id = decodeURIComponent(mcpServerToggle[1]);
      if (!settings.servers.some(server => server.id === id)) return send(res, 404, { error: "mcp_server_not_found" });
      const saved = await mcpClientStore.save({ servers: settings.servers.map(server => server.id === id ? { ...server, enabled: input.enabled } : server) });
      return send(res, 200, { ...saved, servers: saved.servers.map(server => ({ ...server, headers: Object.fromEntries(Object.keys(server.headers).map(key => [key, "••••••"])) })) });
    }
    const mcpAction = url.pathname.match(/^\/v1\/mcp\/servers\/([^/]+)\/(connect|tools\/([^/]+)\/call)$/);
    if (mcpAction) {
      if (!mcpRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
      if (req.method !== "POST") return send(res, 405, { error: "method_not_allowed" });
      const { servers } = await mcpClientStore.read();
      const selected = servers.find(server => server.id === decodeURIComponent(mcpAction[1]));
      if (!selected) return send(res, 404, { error: "mcp_server_not_found" });
      try {
        if (mcpAction[2] === "connect") {
          const connection = await connectMcpServer(selected);
          const saved = await mcpClientStore.save({ servers: servers.map(server => server.id === selected.id ? { ...server, tools: connection.tools, connectedAt: new Date().toISOString(), error: "" } : server) });
          await connection.session?.close?.();
          return send(res, 200, { tools: saved.servers.find(server => server.id === selected.id).tools, serverInfo: connection.serverInfo });
        }
        const input = await body(req);
        return send(res, 200, await callMcpTool(selected, decodeURIComponent(mcpAction[3]), input.arguments || {}));
      } catch (error) { return send(res, 502, { error: error.message || "mcp_request_failed" }); }
    }
    if (url.pathname === "/v1/food" || url.pathname === "/v1/food/") {
      res.writeHead(302, { location: "/v1/food/index.html" }); return res.end();
    }
    if (url.pathname.startsWith("/v1/food/uploads/")) {
      const name = url.pathname.split("/").at(-1).replace(/[^a-zA-Z0-9._-]/g, "");
      try { const data = await readFile(join(dataDir, name)); res.writeHead(200, { "content-type": name.endsWith(".png") ? "image/png" : name.endsWith(".webp") ? "image/webp" : "image/jpeg", "cache-control": "private, max-age=86400" }); res.end(data); } catch { return send(res, 404, { error: "not_found" }); }
      return;
    }
    if (url.pathname.startsWith("/v1/food/")) {
      const path = url.pathname.slice("/v1/food".length);
      if (req.method === "GET" && ["/index.html", "/app.js", "/icon.svg", "/dishes.txt", "/UPSTREAM-LICENSE"].includes(path)) {
        const name = path === "/index.html" ? "index.html" : path.slice(1);
        try { const data = await readFile(join(process.cwd(), "public/food", name)); const type = name.endsWith(".js") ? "text/javascript; charset=utf-8" : name.endsWith(".svg") ? "image/svg+xml" : name.endsWith(".txt") || name.endsWith("LICENSE") ? "text/plain; charset=utf-8" : "text/html; charset=utf-8"; res.writeHead(200, { "content-type": type, "cache-control": "no-cache" }); res.end(data); } catch { return send(res, 404, { error: "not_found" }); } return;
      }
      if (req.method === "GET" && path === "/food/tools") return send(res, 200, { tools: foodTools });
      if (req.method === "GET" && path === "/food/context") return send(res, 200, { context: await foodContext() });
      if (req.method === "GET" && path === "/api/food") return send(res, 200, await getFoodBook());
      if (req.method === "POST" && path === "/food/ai") { const input = await body(req); return send(res, 200, { text: await executeFoodTool(input.tool, input.input || {}) }); }
      if (req.method === "POST") { const input = await body(req); return send(res, 200, await mutateFood(path, input)); }
      return send(res, 405, { error: "method_not_allowed" });
    }
    const lettersMapPath = url.pathname.match(/^\/v1\/letters-map(?:\/(.*))?$/);
    if (lettersMapPath) {
      if (!pushRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
      const mapPassword = String(process.env.LETTERS_MAP_PASSWORD || "").trim();
      if (!mapPassword) return send(res, 503, { error: "letters_map_not_configured" });
      const suffix = lettersMapPath[1] || "";
      let upstreamPath = "";
      if (!suffix && req.method === "GET") upstreamPath = "/api/travel-map";
      else if (suffix === "marks" && req.method === "POST") upstreamPath = "/api/travel-map/marks";
      else if (suffix === "location" && req.method === "POST") upstreamPath = "/api/location";
      else {
        const openLetter = suffix.match(/^letters\/([^/]+)\/open$/);
        if (openLetter && req.method === "POST") upstreamPath = `/api/travel-map/letters/${encodeURIComponent(decodeURIComponent(openLetter[1]))}/open`;
      }
      if (!upstreamPath) return send(res, 404, { error: "not_found" });
      const mapBaseURL = (process.env.LETTERS_MAP_BASE_URL || "https://lumi-hidden-letters.zeabur.app").replace(/\/$/, "");
      try {
        const upstream = await fetch(`${mapBaseURL}${upstreamPath}`, {
          method: req.method,
          headers: { authorization: `Bearer ${mapPassword}`, ...(req.method === "POST" ? { "content-type": "application/json" } : {}) },
          ...(req.method === "POST" ? { body: JSON.stringify(await body(req)) } : {}),
          signal: AbortSignal.timeout(20_000),
          redirect: "error"
        });
        const payload = await upstream.json().catch(() => ({ error: "letters_map_invalid_response" }));
        return send(res, upstream.status, payload);
      } catch (error) {
        console.warn(`[letters-map] upstream request failed: ${String(error.message || error).slice(0, 200)}`);
        return send(res, 502, { error: "letters_map_unavailable" });
      }
    }
    if (req.method === "POST" && url.pathname === "/v1/memories") {
      const input = await body(req);
      if (typeof input.content !== "string" || !input.content.trim()) return send(res, 400, { error: "content_required" });
      const saved = await writeMemory(input.content.trim(), input.threadId || "manual");
      return send(res, saved ? 201 : 502, { saved });
    }
    const screenMatch = url.pathname.match(/^\/v1\/chats\/([^/]+)\/screen-share(?:\/(frame|status))?$/);
    if (screenMatch) {
      const threadID = decodeURIComponent(screenMatch[1]);
      const operation = screenMatch[2] || "status";
      const dir = join(screenShareDir, threadID.replace(/[^a-zA-Z0-9_-]/g, "_"));
      const framePath = join(dir, "latest.jpg");
      const statePath = join(dir, "state.json");
      if (req.method === "POST" && operation === "frame") {
        const input = await body(req);
        const data = String(input.jpegBase64 || input.frame || "").replace(/^data:image\/jpeg;base64,/i, "");
        if (!data || data.length > 2_000_000) return send(res, 400, { error: "jpeg_required" });
        await mkdir(dir, { recursive: true });
        await writeFile(framePath, Buffer.from(data, "base64"));
        await writeFile(statePath, JSON.stringify({ active: true, updatedAt: new Date().toISOString(), width: Number(input.width || 0), height: Number(input.height || 0) }));
        return send(res, 202, { accepted: true });
      }
      if (req.method === "GET" && operation === "status") {
        try { return send(res, 200, JSON.parse(await readFile(statePath, "utf8"))); }
        catch { return send(res, 200, { active: false, updatedAt: null }); }
      }
      if (req.method === "GET" && operation === "frame") {
        try { res.writeHead(200, { "content-type": "image/jpeg", "cache-control": "no-store", "access-control-allow-origin": "*" }); res.end(await readFile(framePath)); }
        catch (error) { return send(res, error?.code === "ENOENT" ? 404 : 500, { error: "frame_unavailable" }); }
        return;
      }
      if (req.method === "DELETE") { await mkdir(dir, { recursive: true }); await writeFile(statePath, JSON.stringify({ active: false, updatedAt: new Date().toISOString() })); return send(res, 200, { stopped: true }); }
      return send(res, 405, { error: "method_not_allowed" });
    }
    const settingsPath = url.pathname === "/v1/settings/proactive";
    const activityMatch = url.pathname.match(/^\/v1\/chats\/([^/]+)\/activity$/);
    const callMatch = url.pathname.match(/^\/v1\/chats\/([^/]+)\/calls(?:\/([^/]+)(?:\/(messages|end|answer))?)?$/);
    const match = url.pathname.match(/^\/v1\/chats\/([^/]+)(\/messages)?$/);
    if (!match && !activityMatch && !settingsPath && !callMatch) return send(res, 404, { error: "not_found" });
    const id = decodeURIComponent((match || activityMatch || callMatch)?.[1] || "default");
    const threads = await readThreads();
    if (!threads[id]) threads[id] = { id, title: "新聊天", messages: [], proactive: { enabled: false, threadId: id, message: "有一段时间没聊了，结合我们的上下文自然地来找我说句话。", intervalMin: 60, intervalMax: 60, nextDueAt: null, scheduledForUserMessageId: null }, activity: { mode: "sentinel", lastUserActivityAt: new Date().toISOString(), nextWakeAt: null, sleepPendingAt: null, sleepStage: null } };
    ensureActivity(threads[id]);
    if (callMatch) {
      const callID = callMatch[2];
      const operation = callMatch[3];
      const thread = threads[id];
      const calls = ensureCallStore(thread);
      if (req.method === "GET" && callID === "pending" && !operation) {
        if (!pushRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
        const expired = await expirePendingCalls(thread);
        const call = Object.values(calls).find(item => item.status === "pending" && Date.parse(item.expiresAt) > Date.now());
        if (expired) await saveThreads(threads);
        return send(res, 200, { call: call ? { callId: call.callId, reason: call.reason, createdAt: call.createdAt, expiresAt: call.expiresAt } : null });
      }
      if (req.method === "POST" && !callID) {
        if (!pushRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
        const input = await body(req);
        const call = { callId: randomUUID().toLowerCase(), status: "active", initiator: "user", createdAt: new Date().toISOString(), startedAt: new Date().toISOString(), turns: [] };
        calls[call.callId] = call;
        const reply = await generateReply({ input: "电话刚接通。请用一句简短、自然、轻柔的话开场，告诉对方你在听。", systemPrompt: `${input.systemPrompt || ""}\n\n当前是实时语音通话。回复适合直接朗读，句子简短，匹配对方的情绪、语速和音量；没有明确线索时不要猜测情绪。`, thread, context: `语音通话 ${call.callId}；语速和音量应匹配用户当下的状态。` });
        const first = { id: randomUUID(), role: "assistant", content: reply.content, createdAt: new Date().toISOString() };
        call.turns.push(first);
        const speech = await synthesizeCallSpeech(first.content, input.tts, Boolean(input.softVoice));
        await saveThreads(threads);
        return send(res, 200, { callId: call.callId, status: "accepted", firstMessage: first, speechAudioBase64: speech.speechAudioBase64, speechDuration: speech.speechDuration, speechScript: speech.speechScript, speechError: speech.speechError });
      }
      if (req.method === "POST" && callID && operation === "answer") {
        if (!pushRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
        const input = await body(req);
        const call = calls[callID];
        if (!call || call.status !== "pending") return send(res, 200, { callId: callID, status: "expired", assistantMessage: null, callStatusMessage: null });
        if (Date.parse(call.expiresAt) <= Date.now()) {
          const expired = await expirePendingCalls(thread);
          if (expired) await saveThreads(threads);
          return send(res, 200, { callId: callID, status: "expired" });
        }
        if (input.action !== "accept") {
          call.status = "declined";
          call.endedAt = new Date().toISOString();
          const note = String(input.note || "").trim().slice(0, 60);
          const statusMessage = { id: randomUUID(), role: "assistant", content: note ? `📞 你没接电话：${note}` : "📞 你暂时不方便接听", contentType: "call_status", callID, callInitiator: "assistant", callStatus: "declined", createdAt: new Date().toISOString() };
          thread.messages.push(statusMessage);
          await saveThreads(threads);
          return send(res, 200, { callId: callID, status: "declined", callStatusMessage: statusMessage });
        }
        call.status = "active";
        call.startedAt = new Date().toISOString();
        const reply = await generateReply({ input: `电话接通了。对方接了你的电话。来电理由：${call.reason}。请简短、轻柔地开场。`, systemPrompt: `${input.systemPrompt || ""}\n\n当前是实时语音通话。回复适合直接朗读，句子简短，匹配对方的情绪、语速和音量；没有明确线索时不要猜测情绪。`, thread, context: `主动来电理由：${call.reason}。通话时匹配用户的情绪和音量，避免强行判断。` });
        const first = { id: randomUUID(), role: "assistant", content: reply.content, createdAt: new Date().toISOString() };
        call.turns.push(first);
        const speech = await synthesizeCallSpeech(first.content, input.tts, Boolean(input.softVoice));
        await saveThreads(threads);
        return send(res, 200, { callId: callID, status: "accepted", firstMessage: first, speechAudioBase64: speech.speechAudioBase64, speechDuration: speech.speechDuration, speechScript: speech.speechScript, speechError: speech.speechError });
      }
      if (req.method === "POST" && callID && operation === "messages") {
        if (!pushRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
        const input = await body(req);
        const call = calls[callID];
        if (!call || call.status !== "active") return send(res, 404, { error: "active_call_not_found" });
        const content = String(input.content || "").trim().slice(0, 4000);
        if (!content) return send(res, 400, { error: "content_required" });
        markUserActivity(thread, content);
        const userTurn = { id: randomUUID(), role: "user", content, createdAt: new Date().toISOString() };
        call.turns.push(userTurn);
        const voiceContext = String(input.voiceContext || "").trim().slice(0, 1000);
        const voicePrefix = voiceContext ? `[用户说话状态：${voiceContext}]\n` : "";
        const transcript = call.turns.slice(-12).map(turn => `${turn.role === "user" ? "用户" : "沈屿"}：${turn.content}`).join("\n");
        const bedtime = /晚安|睡了|先睡|去睡|明天见|good\s*night/i.test(content);
        const callSystemPrompt = `${input.systemPrompt || ""}\n\n当前是实时语音通话。回复适合直接朗读，句子简短，匹配对方的情绪、语速和音量；没有明确线索时不要猜测情绪。${bedtime ? `对方在道晚安，请轻声回应；只有自然收尾时才在回复末尾写 ⟪挂断⟫。播放完后留 ${callLingerSeconds} 秒，期间对方开口就继续通话。` : ""}`;
        const reply = await generateReply({ input: `${voicePrefix}${content}`, systemPrompt: callSystemPrompt, thread, context: `实时语音通话。最近通话内容：\n${transcript}\n\n说话情绪与语气线索：${voiceContext || "暂无声学线索"}。以内容为准，线索不足时不要推断情绪。` });
        const parsedReply = stripCallMarkers(reply.content);
        const assistantTurn = { id: randomUUID(), role: "assistant", content: parsedReply.text, createdAt: new Date().toISOString() };
        call.turns.push(assistantTurn);
        const softVoice = Boolean(input.softVoice) || bedtime || /声音比平时轻|轻声|低声|困/.test(voiceContext + content);
        const speech = await synthesizeCallSpeech(assistantTurn.content, input.tts, softVoice);
        await saveThreads(threads);
        return send(res, 200, { userTurn, assistantTurn, hangupAfterPlayback: parsedReply.hangupAfterPlayback, speechAudioBase64: speech.speechAudioBase64, speechDuration: speech.speechDuration, speechScript: speech.speechScript, speechError: speech.speechError });
      }
      if (req.method === "POST" && callID && operation === "end") {
        if (!pushRequestAuthorized(req)) return send(res, 401, { error: "unauthorized" });
        const call = calls[callID];
        if (!call) return send(res, 404, { error: "call_not_found" });
        if (!call.endedAt) { call.endedAt = new Date().toISOString(); call.status = "ended"; }
        const duration = Math.max(0, Math.round((Date.parse(call.endedAt) - Date.parse(call.startedAt || call.createdAt)) / 1000));
        let summary = "这次聊了几句。";
        const userLine = call.turns.slice().reverse().find(turn => turn.role === "user")?.content;
        if (userLine) summary = `聊到“${userLine.slice(0, 36)}${userLine.length > 36 ? "…" : ""}”`;
        const recordMessage = { id: randomUUID(), role: "assistant", content: `📞 语音通话 · ${Math.floor(duration / 60)}:${String(duration % 60).padStart(2, "0")}\n${summary}`, contentType: "call_record", callID, callInitiator: call.initiator || "assistant", callDuration: duration, createdAt: new Date().toISOString() };
        if (!call.recorded) { thread.messages.push(recordMessage); call.recorded = true; }
        await saveThreads(threads);
        return send(res, 200, { callId: callID, duration, recordMessage });
      }
      return send(res, 405, { error: "method_not_allowed" });
    }
    if (req.method === "GET" && url.pathname === "/v1/settings/proactive") {
      const owner = threads.default || threads[id];
      return send(res, 200, { ...owner.proactive, dnd: owner.dnd === true });
    }
    if (req.method === "PUT" && url.pathname === "/v1/settings/proactive") {
      const input = await body(req);
      const proactive = ensureProactive(threads.default || threads[id]);
      const owner = threads.default || threads[id];
      proactive.enabled = Boolean(input.enabled);
      proactive.threadId = input.threadId || "default";
      proactive.message = typeof input.message === "string" && input.message.trim() ? input.message.trim() : proactive.message;
      proactive.intervalMin = Math.max(1, Number(input.intervalMin) || 60);
      proactive.intervalMax = Math.max(proactive.intervalMin, Number(input.intervalMax) || proactive.intervalMin);
      if (input.actions && typeof input.actions === "object") proactive.actions = { message: input.actions.message !== false, phone: input.actions.phone !== false, screen: input.actions.screen === true };
      if (typeof input.dnd === "boolean") owner.dnd = input.dnd;
      if (!proactive.enabled) proactive.nextDueAt = null;
      await saveThreads(threads);
      return send(res, 200, { ...proactive, dnd: owner.dnd === true });
    }
    if (activityMatch) {
      if (req.method === "GET") return send(res, 200, threads[id].activity);
      if (req.method === "POST") {
        const input = await body(req);
        const activity = threads[id].activity;
        if (input.action === "sentinel_start") {
          activity.mode = "sentinel";
          const proactive = ensureProactive(threads[id]);
          const interval = Math.max(1, Number(proactive.intervalMin) || 60);
          activity.nextWakeAt = new Date(Date.now() + interval * 60_000).toISOString();
          proactive.nextDueAt = activity.nextWakeAt;
        } else if (input.action === "sentinel_stop") {
          activity.nextWakeAt = null;
        } else if (input.action === "sleep_abort") {
          activity.mode = "sentinel";
          activity.sleepPendingAt = null;
          activity.sleepUntil = null;
          activity.nextDreamAt = null;
          activity.sleepStage = "aborted";
          const interval = Math.max(1, Number(ensureProactive(threads[id]).intervalMin) || 60);
          activity.nextWakeAt = new Date(Date.now() + interval * 60_000).toISOString();
        }
        await saveThreads(threads);
        return send(res, 200, activity);
      }
      return send(res, 405, { error: "method_not_allowed" });
    }
    if (req.method === "GET" && !match[2]) return send(res, 200, threads[id]);
    if (req.method === "POST" && match[2]) {
      const input = await body(req);
      if (typeof input.content !== "string" || !input.content.trim()) return send(res, 400, { error: "content_required" });
      if (input.provider === "custom" && !mcpRequestAuthorized(req)) return send(res, 401, { error: "custom_provider_unauthorized" });
      markUserActivity(threads[id], input.content);
      const userMessage = { id: randomUUID(), role: "user", content: input.content.trim(), contentType: typeof input.contentType === "string" ? input.contentType : undefined, createdAt: new Date().toISOString() };
      const generated = await generateReply({ input: userMessage.content, systemPrompt: input.systemPrompt, thread: threads[id], provider: input.provider, model: input.model, customProvider: input.customProvider, context: input.context });
      const assistantMessage = {
        id: randomUUID(),
        role: "assistant",
        content: generated.content,
        contentType: typeof input.contentType === "string" ? input.contentType : undefined,
        createdAt: new Date().toISOString()
      };
      threads[id].messages.push(userMessage, assistantMessage);
      await saveThreads(threads);
      return send(res, 200, { userMessage, assistantMessage, memorySaved: generated.memorySaved });
    }
    return send(res, 405, { error: "method_not_allowed" });
  } catch (error) { return send(res, 500, { error: error.message }); }
});

server.on("upgrade", (req, socket, head) => {
  let url;
  try { url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`); }
  catch { socket.destroy(); return; }
  if (url.pathname !== "/ws") { socket.destroy(); return; }
  const upstream = connectSocket(duettoPort, "127.0.0.1");
  upstream.once("connect", () => {
    const headers = [];
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      if (req.rawHeaders[i].toLowerCase() !== "host") headers.push(`${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}`);
    }
    headers.push(`Host: 127.0.0.1:${duettoPort}`);
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n${headers.join("\r\n")}\r\n\r\n`);
    if (head.length) upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });
  upstream.on("error", () => socket.destroy());
  socket.on("error", () => upstream.destroy());
  socket.on("close", () => upstream.destroy());
});

server.listen(port, () => console.log(`Lumi server listening on :${port}`));
setInterval(() => { runBackgroundPulse().catch((error) => console.warn(`background pulse failed: ${error.message}`)); }, 15_000);
