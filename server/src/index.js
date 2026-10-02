import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { createServer } from "node:http";

const port = Number(process.env.PORT || 8787);
const dataDir = process.env.LUMI_DATA_DIR || join(process.cwd(), "data");
const threadPath = join(dataDir, "threads.json");
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
const screenShareDir = join(dataDir, "screen-share");

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
  const raw = await callModel({
    messages: [
      {
        role: "system",
        content: `你是一个会主动关心用户的 AI。根据主动消息设定“${proactive.message}”自然地发起联系。允许的动作：主动消息=${actions.message ? "是" : "否"}，主动电话=${actions.phone ? "是" : "否"}，查看屏幕=${actions.screen ? "是" : "否"}。关闭的动作绝对不要执行。你还要自己决定下一次主动联系的间隔，单位是分钟，必须是 1 到 1440 的整数。只输出 JSON，不要 Markdown：{"message":"要发给用户的话","nextWakeMinutes":整数}`
      },
      { role: "user", content: recent || "还没有聊天记录。" }
    ],
    temperature: 0.8
  });
  const parsed = JSON.parse(raw.match(/\{[\s\S]*\}/)?.[0] || "{}");
  const message = typeof parsed.message === "string" && parsed.message.trim() ? parsed.message.trim() : raw.trim();
  const fallback = Math.max(1, Number(proactive.intervalMin) || 60);
  const nextWakeMinutes = Math.min(1440, Math.max(1, Math.round(Number(parsed.nextWakeMinutes) || fallback)));
  return {
    message: { id: randomUUID(), role: "assistant", content: message, contentType: "sentinel", createdAt: new Date().toISOString() },
    nextWakeMinutes
  };
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
        thread.messages.push(wake.message);
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

async function callModel({ messages, temperature = 0.8 }) {
  const apiURL = process.env.LUMI_MODEL_API_URL;
  const apiKey = process.env.LUMI_MODEL_API_KEY;
  const model = process.env.LUMI_MODEL_NAME;
  if (!apiURL || !apiKey || !model) {
    throw new Error("模型服务尚未配置：请在 Zeabur 设置 LUMI_MODEL_API_URL、LUMI_MODEL_API_KEY、LUMI_MODEL_NAME");
  }

  const response = await fetch(apiURL, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model, messages, temperature })
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data?.error?.message || data?.error || `模型服务返回 ${response.status}`);
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || !content.trim()) throw new Error("模型没有返回内容");
  return content.trim();
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

async function generateReply({ input, systemPrompt, thread }) {
  await compactThread(thread);
  const system = process.env.LUMI_SYSTEM_PROMPT || systemPrompt || "使用中文回复。";
  const summary = thread.contextSummary ? `\n\n<context_summary>\n${thread.contextSummary}\n</context_summary>` : "";
  const memories = await searchMemories(input);
  const retrieved = memories.length
    ? `\n\n<retrieved_memories>\n${memories.map((memory) => `- ${memory}`).join("\n")}\n</retrieved_memories>`
    : "";
  const history = (thread.messages || []).slice(-20).map((message) => ({ role: message.role, content: message.content }));
  const raw = await callModel({
    messages: [{ role: "system", content: `${system}${summary}${retrieved}\n\n如果这条对话包含值得长期保留的新事实、偏好或约定，你可以在回复末尾添加 <memory>要记住的内容</memory>；不值得记忆时不要添加。不要向用户解释这个标签。` }, ...history, { role: "user", content: input }]
  });
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

async function body(req) {
  let raw = "";
  for await (const chunk of req) raw += chunk;
  return raw ? JSON.parse(raw) : {};
}

const server = createServer(async (req, res) => {
  if (req.method === "OPTIONS") return send(res, 204, {});
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (req.method === "GET" && url.pathname === "/health") return send(res, 200, { ok: true });
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
    const match = url.pathname.match(/^\/v1\/chats\/([^/]+)(\/messages)?$/);
    if (!match && !activityMatch && !settingsPath) return send(res, 404, { error: "not_found" });
    const id = decodeURIComponent((match || activityMatch)?.[1] || "default");
    const threads = await readThreads();
    if (!threads[id]) threads[id] = { id, title: "新聊天", messages: [], proactive: { enabled: false, threadId: id, message: "有一段时间没聊了，结合我们的上下文自然地来找我说句话。", intervalMin: 60, intervalMax: 60, nextDueAt: null, scheduledForUserMessageId: null }, activity: { mode: "sentinel", lastUserActivityAt: new Date().toISOString(), nextWakeAt: null, sleepPendingAt: null, sleepStage: null } };
    ensureActivity(threads[id]);
    if (req.method === "GET" && url.pathname === "/v1/settings/proactive") return send(res, 200, threads.default?.proactive || threads[id].proactive);
    if (req.method === "PUT" && url.pathname === "/v1/settings/proactive") {
      const input = await body(req);
      const proactive = ensureProactive(threads.default || threads[id]);
      proactive.enabled = Boolean(input.enabled);
      proactive.threadId = input.threadId || "default";
      proactive.message = typeof input.message === "string" && input.message.trim() ? input.message.trim() : proactive.message;
      proactive.intervalMin = Math.max(1, Number(input.intervalMin) || 60);
      proactive.intervalMax = Math.max(proactive.intervalMin, Number(input.intervalMax) || proactive.intervalMin);
      if (input.actions && typeof input.actions === "object") proactive.actions = { message: input.actions.message !== false, phone: input.actions.phone !== false, screen: input.actions.screen === true };
      if (!proactive.enabled) proactive.nextDueAt = null;
      await saveThreads(threads);
      return send(res, 200, proactive);
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
      markUserActivity(threads[id], input.content);
      const userMessage = { id: randomUUID(), role: "user", content: input.content.trim(), createdAt: new Date().toISOString() };
      const generated = await generateReply({ input: userMessage.content, systemPrompt: input.systemPrompt, thread: threads[id] });
      const assistantMessage = {
        id: randomUUID(),
        role: "assistant",
        content: generated.content,
        createdAt: new Date().toISOString()
      };
      threads[id].messages.push(userMessage, assistantMessage);
      await saveThreads(threads);
      return send(res, 200, { userMessage, assistantMessage, memorySaved: generated.memorySaved });
    }
    return send(res, 405, { error: "method_not_allowed" });
  } catch (error) { return send(res, 500, { error: error.message }); }
});

server.listen(port, () => console.log(`Lumi server listening on :${port}`));
setInterval(() => { runBackgroundPulse().catch((error) => console.warn(`background pulse failed: ${error.message}`)); }, 15_000);
