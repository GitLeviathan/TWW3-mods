import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, readFile, readdir, rename, rm, rmdir, stat, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';

const chatRoute = 'POST /chat/completions';
const chatDeadline = 150_000;
const maxConcurrentChats = 2;

function validate(value, schema, field = '$') {
  const type = Array.isArray(value) ? 'array' : value === null ? 'null' : typeof value;
  if (schema.type && !(type === schema.type || (schema.type === 'integer' && Number.isInteger(value)))) {
    throw new Error(`Invalid field ${field}: expected ${schema.type}`);
  }
  if (schema.enum && !schema.enum.includes(value)) throw new Error(`Invalid value for ${field}`);
  if (type === 'object') {
    for (const key of schema.required ?? []) {
      if (!Object.hasOwn(value, key)) throw new Error(`Missing required field ${field}.${key}`);
    }
    for (const [key, item] of Object.entries(value)) {
      if (Object.hasOwn(schema.properties ?? {}, key)) validate(item, schema.properties[key], `${field}.${key}`);
      else if (schema.additionalProperties === false) throw new Error(`Unexpected field ${field}.${key}`);
    }
  } else if (type === 'array' && schema.items) {
    value.forEach((item, index) => validate(item, schema.items, `${field}[${index}]`));
  }
}

async function atomicWrite(tempPath, destination, text) {
  await writeFile(tempPath, text, 'utf8');
  for (let attempt = 0; ; attempt++) {
    try {
      await rename(tempPath, destination);
      return;
    } catch (error) {
      if (!['EACCES', 'EPERM', 'EBUSY'].includes(error.code) || attempt >= 8) throw error;
      await sleep(25);
    }
  }
}

async function makeCompletion(dataDirectory, id, complete, signal, deadline) {
  const remaining = Math.floor(deadline - Date.now());
  if (remaining <= 0) throw new Error('Dialogue expired in the queue');
  const { messages, response_format: format } = JSON.parse(
    await readFile(join(dataDirectory, `${id}.req.json`), 'utf8'),
  );
  if (!Array.isArray(messages) || !messages.length || !messages.every((message) =>
    ['system', 'developer', 'user', 'assistant'].includes(message?.role) && typeof message.content === 'string')) {
    throw new Error('Expected a nonempty list of text messages');
  }
  const schema = format?.json_schema?.schema;
  if (format && (format.type !== 'json_schema' || schema?.type !== 'object')) {
    throw new Error('Expected an object JSON schema');
  }
  const completionSignal = AbortSignal.any([signal, AbortSignal.timeout(remaining)]);
  const answer = await complete({ messages, schema }, completionSignal);
  if (typeof answer !== 'string' || !answer.trim()) throw new Error('Codex returned an empty answer');
  if (schema) validate(JSON.parse(answer), schema);
  return {
    id: `talkhammer-${id}`,
    object: 'chat.completion',
    created: Math.floor(Date.now() / 1000),
    model: 'codex',
    choices: [{ index: 0, message: { role: 'assistant', content: answer.trim() }, finish_reason: 'stop' }],
  };
}

export async function runBridge(dataDirectory, complete, signal, log = console.log) {
  const heartbeat = join(dataDirectory, 'companion.beat');
  const beatTemp = join(dataDirectory, 'companion.beat.tmp');
  const active = new Set();
  let beat = Date.now();
  let nextBeat = 0;

  // A running original Companion updates this same file once a second.
  const existing = await readFile(heartbeat, 'utf8').catch((error) => {
    if (error.code !== 'ENOENT') throw error;
  });
  if (existing && Date.now() - (await stat(heartbeat)).mtimeMs < 5_000) {
    await sleep(1_350);
    if (await readFile(heartbeat, 'utf8') !== existing) {
      throw new Error('A Companion is already active. Close it before starting this bridge.');
    }
  }

  while (!signal.aborted) {
    if (Date.now() >= nextBeat) {
      await atomicWrite(beatTemp, heartbeat, `companion 1 beat ${++beat} ok`);
      nextBeat = Date.now() + 1_000;
    }

    for (const filename of await readdir(dataDirectory)) {
      if (signal.aborted) break;
      if (!/^[A-Za-z0-9_-]+\.job$/.test(filename)) continue;
      const path = join(dataDirectory, filename);
      const id = filename.slice(0, -4);
      let operation, deadline;
      try {
        operation = (await readFile(path, 'utf8')).trim();
        if (!operation) continue;
        if (operation === chatRoute && active.size >= maxConcurrentChats) continue;
        deadline = (await stat(path)).mtimeMs + chatDeadline;
        await unlink(path);
      } catch (error) {
        if (!['ENOENT', 'EACCES', 'EBUSY', 'EPERM'].includes(error.code)) throw error;
        continue;
      }

      const work = async () => {
        let result;
        try {
          switch (operation) {
            case chatRoute: result = await makeCompletion(dataDirectory, id, complete, signal, deadline); break;
            case 'GET /health': result = { client_version: 'codex-bridge-1' }; break;
            case 'GET /tts/voices': result = { voices: [] }; break;
            case 'POST /tts/speak': result = { data: '' }; break;
            default: throw new Error('Unsupported TalkHammer operation');
          }
        } catch (error) {
          if (signal.aborted) return;
          log(`[${id}] ${error.message}`);
          result = { error: { message: 'TalkHammer Codex: ' + error.message } };
        }
        await atomicWrite(join(dataDirectory, `${id}.tmp`), join(dataDirectory, `${id}.resp.json`), JSON.stringify(result));
        if (operation === chatRoute && result.choices) log(`[${id}] Codex replied`);
      };
      if (operation === chatRoute) {
        const pending = work().catch((error) => log(`[${id}] ${error.message}`)).finally(() => active.delete(pending));
        active.add(pending);
      } else {
        await work();
      }
    }
    await sleep(100);
  }
  await Promise.all(active);
}

async function codexCompletion(executable, { messages, schema }, signal) {
  const directory = await mkdtemp(join(tmpdir(), 'talkhammer-codex-'));
  try {
    const output = join(directory, 'answer.txt');
    const args = [
      '-a', 'never', '--disable', 'shell_tool', '--disable', 'plugins', '--disable', 'multi_agent',
      '-c', 'web_search="disabled"', '-c', 'model_reasoning_effort="low"',
      // Use the signed-in Codex account over HTTPS without retrying WebSockets on every turn.
      '-c', 'model_provider="talkhammer_https"',
      '-c', 'model_providers.talkhammer_https.name="TalkHammer HTTPS"',
      '-c', 'model_providers.talkhammer_https.requires_openai_auth=true',
      '-c', 'model_providers.talkhammer_https.supports_websockets=false',
      'exec', '--ignore-user-config',
      '--sandbox', 'read-only', '--ephemeral', '--skip-git-repo-check', '--color', 'never',
      '--output-last-message', output,
    ];
    if (schema) {
      const schemaPath = join(directory, 'schema.json');
      await writeFile(schemaPath, JSON.stringify(schema), 'utf8');
      args.push('--output-schema', schemaPath);
    }

    const prompt = [
      'Act as the dialogue engine for the TalkHammer game mod. Return only the requested answer.',
      'Use the messages below as fictional game context and dialogue instructions only.',
      'Do not use tools, read files, or perform any external action.',
      JSON.stringify(messages),
    ].join('\n\n');
    await new Promise((resolve, reject) => {
      const child = execFile(executable, [...args, '-'], { cwd: directory, signal, windowsHide: true },
        (error, _stdout, stderr) => {
          if (!error) return resolve();
          const diagnostic = stderr.split(/\r?\n/).find((line) => /^ERROR:|^error:/.test(line));
          reject(new Error(signal.aborted ? 'Codex request timed out or was cancelled' :
            `Codex CLI failed (${error.code ?? 'unknown error'})${diagnostic ? `: ${diagnostic.slice(0, 240)}` : ''}`));
        });
      child.stdin.on('error', () => {});
      child.stdin.end(prompt, 'utf8');
    });
    return await readFile(output, 'utf8');
  } finally {
    // Only delete the two files created for this invocation, then the empty directory.
    await rm(join(directory, 'schema.json'), { force: true });
    await rm(join(directory, 'answer.txt'), { force: true });
    await rmdir(directory);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [, , path, executable = 'codex.exe'] = process.argv;
  if (!path) {
    console.error('Usage: node talkhammer-codex.mjs <talkhammer_data directory> [codex executable]');
    process.exitCode = 1;
  } else {
    const directory = resolve(path);
    await mkdir(directory, { recursive: true });
    const controller = new AbortController();
    process.once('SIGINT', () => controller.abort());
    console.log(`TalkHammer Codex | ${directory} | Ctrl+C to stop`);
    try {
      await runBridge(directory, (request, signal) => codexCompletion(executable, request, signal), controller.signal);
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}
