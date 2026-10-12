import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';

const MAX_SERVERS = 30;
const privateHost = host => host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal') || host === 'metadata.google.internal' || /^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(host) || host === '::1' || /^(fc|fd|fe80:)/i.test(host);

export function validateMcpURL(value) {
  let url;
  try { url = new URL(String(value || '').trim()); } catch { throw new Error('MCP URL 无效'); }
  if (url.protocol !== 'https:' || url.username || url.password || privateHost(url.hostname.toLowerCase())) throw new Error('MCP 服务器必须使用公开 HTTPS 地址');
  return url.toString();
}

export function normalizeMcpServers(input) {
  if (!Array.isArray(input) || input.length > MAX_SERVERS) throw new Error(`MCP 服务器最多 ${MAX_SERVERS} 个`);
  const ids = new Set();
  return input.map(item => {
    if (!item || typeof item !== 'object') throw new Error('MCP 服务器格式无效');
    const id = String(item.id || randomUUID());
    if (ids.has(id)) throw new Error('MCP 服务器 ID 重复');
    ids.add(id);
    const headers = {};
    for (const [key, value] of Object.entries(item.headers || {})) {
      if (!/^[!#$%&'*+.^_`|~0-9A-Za-z-]{1,80}$/.test(key) || /^(host|content-length|connection|transfer-encoding)$/i.test(key)) throw new Error('MCP 请求头名称无效');
      headers[key] = String(value).slice(0, 4000);
    }
    const transport = item.transport === 'sse' ? 'sse' : 'streamable-http';
    return { id, name: String(item.name || 'MCP 服务器').trim().slice(0, 100) || 'MCP 服务器', enabled: item.enabled !== false, url: validateMcpURL(item.url), transport, headers, tools: Array.isArray(item.tools) ? item.tools.slice(0, 300) : [], connectedAt: item.connectedAt || null, error: '' };
  });
}

export class McpClientStore {
  constructor(path) { this.path = path; this.queue = Promise.resolve(); }
  async read() {
    let settings;
    try { settings = JSON.parse(await readFile(this.path, 'utf8')); }
    catch (error) { if (error.code === 'ENOENT') settings = { servers: [], revision: 0 }; else throw error; }
    const mapURL = process.env.LUMI_LETTERS_MCP_URL;
    const mapPassword = process.env.LUMI_LETTERS_MCP_TOKEN || process.env.LETTERS_MAP_PASSWORD;
    if (mapURL && mapPassword && !settings.servers.some(server => server.id === 'letters-map')) {
      settings.servers.push(normalizeMcpServers([{
        id: 'letters-map', name: '藏宝地图', enabled: true, url: mapURL,
        transport: 'streamable-http', headers: { Authorization: `Bearer ${mapPassword}` }, tools: [], connectedAt: null
      }])[0]);
    }
    return settings;
  }
  async save(input) {
    const action = this.queue.then(async () => {
      const current = await this.read();
      const previousById = new Map(current.servers.map(server => [server.id, server]));
      const servers = normalizeMcpServers(input.servers).map(server => {
        const previous = previousById.get(server.id);
        if (!previous) return server;
        const headers = { ...server.headers };
        for (const [key, value] of Object.entries(headers)) if (value === "••••••" && previous.headers?.[key] != null) headers[key] = previous.headers[key];
        return { ...server, headers };
      });
      const next = { servers, revision: current.revision + 1 };
      await mkdir(dirname(this.path), { recursive: true });
      const temporary = `${this.path}.${randomUUID()}.tmp`;
      await writeFile(temporary, JSON.stringify(next, null, 2), { mode: 0o600 }); await rename(temporary, this.path);
      return next;
    });
    this.queue = action.catch(() => {}); return action;
  }
}

function readMcpPayload(text, contentType = '') {
  if (contentType.includes('text/event-stream')) {
    const events = text.split(/\r?\n\r?\n/).map(event => event.split(/\r?\n/).filter(line => line.startsWith('data:')).map(line => line.slice(5).trim()).join('\n')).filter(Boolean);
    const json = events.reverse().find(value => { try { return JSON.parse(value)?.jsonrpc === '2.0'; } catch { return false; } });
    return json ? JSON.parse(json) : {};
  }
  try { return JSON.parse(text); } catch { return {}; }
}

export async function mcpRequest(server, method, params = {}, session = null) {
  const id = randomUUID();
  const response = await fetch(server.url, {
    method: 'POST',
    headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', ...server.headers, ...(session ? { 'mcp-session-id': session } : {}) },
    body: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
    signal: AbortSignal.timeout(20_000), redirect: 'error'
  });
  const sessionId = response.headers.get('mcp-session-id') || session;
  const payload = readMcpPayload(await response.text(), response.headers.get('content-type') || '');
  if (!response.ok) throw new Error(payload?.error?.message || `MCP 服务器返回 ${response.status}`);
  if (payload.error) throw new Error(String(payload.error.message || 'MCP 请求失败'));
  return { result: payload.result || {}, sessionId };
}

export async function connectMcpServer(server) {
  if (server.transport === 'sse') return connectSseMcpServer(server);
  const protocolVersion = '2025-03-26';
  const initialized = await mcpRequest(server, 'initialize', { protocolVersion, capabilities: {}, clientInfo: { name: 'Lumi', version: '1.0' } });
  if (initialized.sessionId) {
    await fetch(server.url, { method: 'POST', headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', ...server.headers, 'mcp-session-id': initialized.sessionId }, body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }), signal: AbortSignal.timeout(10_000), redirect: 'error' });
  }
  const listed = await mcpRequest(server, 'tools/list', {}, initialized.sessionId);
  return { tools: Array.isArray(listed.result.tools) ? listed.result.tools : [], sessionId: listed.sessionId, serverInfo: initialized.result.serverInfo || null };
}

export async function callMcpTool(server, name, args) {
  if (server.transport === 'sse') {
    const connection = await connectSseMcpServer(server);
    if (!connection.tools.some(tool => tool.name === name)) throw new Error('MCP 工具不存在或尚未启用');
    return sseMcpRequest(connection.session, 'tools/call', { name, arguments: args });
  }
  const connection = await connectMcpServer(server);
  if (!connection.tools.some(tool => tool.name === name)) throw new Error('MCP 工具不存在或尚未启用');
  const called = await mcpRequest(server, 'tools/call', { name, arguments: args }, connection.sessionId);
  return called.result;
}

async function openSseMcpSession(server) {
  const response = await fetch(server.url, { method: 'GET', headers: { accept: 'text/event-stream', ...server.headers }, signal: AbortSignal.timeout(20_000), redirect: 'error' });
  if (!response.ok || !response.body) throw new Error(`MCP SSE 连接失败 (${response.status})`);
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let endpointResolve, messageResolve, messageReject;
  const endpointReady = new Promise(resolve => { endpointResolve = resolve; });
  let pending = new Map();
  const streamClosed = new Promise((_, reject) => { messageReject = reject; });
  const parseEvent = raw => {
    const lines = raw.split(/\r?\n/);
    const event = lines.find(line => line.startsWith('event:'))?.slice(6).trim();
    const data = lines.filter(line => line.startsWith('data:')).map(line => line.slice(5).trim()).join('\n');
    if (event === 'endpoint') {
      try { endpointResolve(new URL(data, server.url).toString()); } catch { endpointResolve(null); }
    } else if (data) {
      try {
        const payload = JSON.parse(data);
        if (payload?.id != null && pending.has(String(payload.id))) { const settle = pending.get(String(payload.id)); pending.delete(String(payload.id)); settle(payload); }
      } catch {}
    }
  };
  (async () => {
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) { messageReject(new Error('MCP SSE stream 已關閉')); break; }
        buffer += decoder.decode(value, { stream: true });
        const events = buffer.split(/\r?\n\r?\n/); buffer = events.pop() || '';
        events.forEach(parseEvent);
      }
    } catch (error) { messageReject(error); }
  })();
  const endpoint = await Promise.race([endpointReady, new Promise((_, reject) => setTimeout(() => reject(new Error('MCP SSE 未提供 message endpoint')), 10_000)), streamClosed]);
  if (!endpoint) throw new Error('MCP SSE endpoint 無效');
  return {
    endpoint,
    async request(method, params = {}) {
      const id = randomUUID();
      const result = new Promise((resolve, reject) => {
        const timeout = setTimeout(() => { pending.delete(id); reject(new Error('MCP SSE 请求超时')); }, 20_000);
        pending.set(id, payload => { clearTimeout(timeout); if (payload.error) reject(new Error(payload.error.message || 'MCP 请求失败')); else resolve(payload.result || {}); });
      });
      const post = await fetch(endpoint, { method: 'POST', headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', ...server.headers }, body: JSON.stringify({ jsonrpc: '2.0', id, method, params }), signal: AbortSignal.timeout(20_000), redirect: 'error' });
      if (!post.ok && post.status !== 202) throw new Error(`MCP SSE 请求失败 (${post.status})`);
      if (post.status !== 202) {
        const payload = readMcpPayload(await post.text(), post.headers.get('content-type') || '');
        if (payload?.error) throw new Error(payload.error.message || 'MCP 请求失败');
        return payload.result || {};
      }
      return result;
    },
    async close() { await reader.cancel().catch(() => {}); }
  };
}

async function connectSseMcpServer(server) {
  const session = await openSseMcpSession(server);
  try {
    const initialized = await session.request('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'Lumi', version: '1.0' } });
    const notification = await fetch(session.endpoint, { method: 'POST', headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', ...server.headers }, body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }), signal: AbortSignal.timeout(10_000), redirect: 'error' });
    if (!notification.ok && notification.status !== 202) throw new Error(`MCP SSE 初始化失败 (${notification.status})`);
    const listed = await session.request('tools/list');
    return { tools: Array.isArray(listed.tools) ? listed.tools : [], serverInfo: initialized.serverInfo || null, session };
  } catch (error) { await session.close(); throw error; }
}

async function sseMcpRequest(session, method, params) {
  try { return await session.request(method, params); } finally { await session.close(); }
}
