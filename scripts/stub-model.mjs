#!/usr/bin/env node
// Free, loopback-only OpenAI-compatible model for Nod's real tool/approval pipeline.
import http from 'node:http';

const port = Number(process.env.NODCH_STUB_PORT || 14311);
const model = 'nodch-contract';
http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/v1/models') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ object: 'list', data: [{ id: model, object: 'model', owned_by: 'nodch-local' }] }));
  }
  if (req.method !== 'POST' || req.url !== '/v1/chat/completions') {
    res.writeHead(404); return res.end();
  }
  try {
    let body = '';
    for await (const chunk of req) body += chunk;
    const input = JSON.parse(body);
    const names = (input.tools || []).map(t => t.function.name);
    const last = input.messages.at(-1);
    let data;
    try { data = JSON.parse(typeof last.content === 'string' ? last.content : ''); } catch {}
    let content = JSON.stringify({ text: 'Contract action completed.' });
    let call;
    if (names.includes('manage_personal_context')) {
      const alreadyCalled = input.messages.some(m => m.role === 'assistant' && m.tool_calls?.some(t => t.function.name === 'manage_personal_context'));
      call = alreadyCalled
        ? { name: 'send_message', arguments: JSON.stringify({ text: 'Proactive notifications are paused.', intent: 'final' }) }
        : { name: 'manage_personal_context', arguments: JSON.stringify({ action: 'notification_preferences_update', args: { proactivePaused: true } }) };
    } else if (data?.purpose === 'confirmation') {
      content = JSON.stringify({ text: 'Pause proactive notifications? Nod will stop proactive notifications until you resume them.' });
    } else if (data?.purpose === 'confirmation_review') {
      content = JSON.stringify({ valid: true });
    } else if (input.messages.some(m => typeof m.content === 'string' && m.content.includes('You decide whether an AI assistant may run one action'))) {
      content = JSON.stringify({ run: false });
    }
    console.log(JSON.stringify({ path: req.url, tools: names, purpose: data?.purpose, call: call?.name, content: call ? undefined : content }));
    const id = 'chatcmpl-nodch';
    const tool_calls = call ? [{ index: 0, id: 'call_nodch', type: 'function', function: call }] : undefined;
    const finish = call ? 'tool_calls' : 'stop';
    if (input.stream) {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      const chunk = (delta, finish_reason = null) => `data: ${JSON.stringify({ id, object: 'chat.completion.chunk', created: Math.floor(Date.now()/1000), model, choices: [{ index: 0, delta, finish_reason }] })}\n\n`;
      res.write(chunk({ role: 'assistant', ...(call ? { tool_calls } : { content }) }));
      res.write(chunk({}, finish));
      res.end('data: [DONE]\n\n');
    } else {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ id, object: 'chat.completion', created: Math.floor(Date.now()/1000), model, choices: [{ index: 0, message: { role: 'assistant', content: call ? null : content, tool_calls }, finish_reason: finish }], usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 } }));
    }
  } catch (error) { console.error(error); res.writeHead(500); res.end(); }
}).listen(port, '127.0.0.1', () => console.log(`Stub model ready on ${port}`));
