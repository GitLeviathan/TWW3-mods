import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import test from 'node:test';
import { runBridge } from './talkhammer-codex.mjs';

async function gameQueue(t, complete) {
  const directory = await mkdtemp(join(tmpdir(), 'talkhammer-test-'));
  const controller = new AbortController();
  const running = runBridge(directory, complete, controller.signal, () => {});
  t.after(async () => {
    controller.abort();
    await running;
    await rm(directory, { recursive: true, force: true });
  });

  async function read(name) {
    for (let attempt = 0; attempt < 100; attempt++) {
      try {
        return await readFile(join(directory, name), 'utf8');
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        await sleep(25);
      }
    }
    assert.fail(`Missing ${name}`);
  }

  async function send(id, job, body) {
    if (body !== undefined) {
      await writeFile(join(directory, `${id}.req.json`), JSON.stringify(body));
    }
    await writeFile(join(directory, `${id}.job`), job);
    return JSON.parse(await read(`${id}.resp.json`));
  }

  return { directory, read, send };
}

const request = {
  messages: [{ role: 'user', content: 'Условия мира?' }],
  response_format: {
    type: 'json_schema',
    json_schema: {
      schema: {
        type: 'object',
        properties: { line: { type: 'string' }, action: { enum: ['counter_offer'] } },
        required: ['line', 'action'],
        additionalProperties: false,
      },
    },
  },
};

test('hands the game a completed JSON decision and keeps health responsive during generation', async (t) => {
  let finish;
  const answer = new Promise((resolve) => { finish = resolve; });
  const game = await gameQueue(t, async ({ messages, schema }, signal) => {
    assert.deepEqual(messages, [{ role: 'user', content: 'Условия мира?' }]);
    assert.deepEqual(schema.required, ['line', 'action']);
    return Promise.race([answer, new Promise((_, reject) => {
      signal.addEventListener('abort', () => reject(signal.reason), { once: true });
    })]);
  });
  const before = await game.read('companion.beat');
  const dialogue = game.send('r001', 'POST /chat/completions', request);
  try {
    assert.match(before, /^companion 1 beat \d+ ok$/);
    assert.ok((await game.send('r002', 'GET /health')).client_version);
    await sleep(1050);
    assert.notEqual(await game.read('companion.beat'), before);
  } finally {
    finish('{"line":"Согласен на мир за золото.","action":"counter_offer"}');
  }
  const response = await dialogue;
  assert.equal(response.error, undefined, response.error?.message);
  assert.deepEqual(JSON.parse(response.choices[0].message.content), {
    line: 'Согласен на мир за золото.', action: 'counter_offer',
  });
  const files = await readdir(game.directory);
  assert.ok(!files.includes('r001.job') && !files.includes('r001.tmp'));
});

test('rejects an incomplete decision instead of passing it to the game', async (t) => {
  const game = await gameQueue(t, async () => '{"line":"Согласен."}');
  const result = await game.send('r001', 'POST /chat/completions', request);
  assert.match(result.error?.message ?? '', /Missing required field.*action/);
  assert.equal(result.choices, undefined);
});

test('leaves voice requests silent and rejects other routes without invoking Codex', async (t) => {
  let calls = 0;
  const game = await gameQueue(t, async () => { calls++; return 'unused'; });
  assert.deepEqual(await game.send('r001', 'GET /tts/voices'), { voices: [] });
  assert.deepEqual(await game.send('r002', 'POST /tts/speak', { text: 'Привет' }), { data: '' });
  assert.ok((await game.send('r003', 'GET https://example.test/')).error?.message);
  assert.equal(calls, 0);
});
