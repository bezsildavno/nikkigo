'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createServer, selectInstaller } = require('../server');

test('selects installers by route, query, and user agent', () => {
  assert.equal(selectInstaller(new URL('http://x/install.ps1'), ''), 'install.ps1');
  assert.equal(selectInstaller(new URL('http://x/install.sh'), ''), 'install.sh');
  assert.equal(selectInstaller(new URL('http://x/install'), 'WindowsPowerShell/5.1'), 'install.ps1');
  assert.equal(selectInstaller(new URL('http://x/install'), 'curl/8.0'), 'install.sh');
  assert.equal(selectInstaller(new URL('http://x/install?os=windows'), 'curl/8.0'), 'install.ps1');
  assert.equal(selectInstaller(new URL('http://x/install'), 'Mozilla/5.0'), 'page');
  assert.equal(selectInstaller(new URL('http://x/install'), 'Mozilla/5.0 (Windows NT 10.0)'), 'page');
});

test('serves scripts without cache and exposes health', async (context) => {
  const fetchImpl = async (url) =>
    new Response(url.endsWith('install.ps1') ? 'Write-Host ok' : 'echo ok');
  const server = createServer({ fetchImpl });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(() => new Promise((resolve) => server.close(resolve)));
  const { port } = server.address();

  const script = await fetch(`http://127.0.0.1:${port}/install.ps1`);
  assert.equal(script.status, 200);
  assert.equal(script.headers.get('cache-control'), 'no-store, no-cache, must-revalidate');
  assert.equal(script.headers.get('x-nikkigo-installer'), 'install.ps1');
  assert.equal(await script.text(), 'Write-Host ok');

  const health = await fetch(`http://127.0.0.1:${port}/health`);
  assert.equal(health.status, 200);
  assert.equal((await health.json()).status, 'ok');
});

test('returns 502 when GitHub is unavailable', async (context) => {
  const server = createServer({ fetchImpl: async () => { throw new Error('offline'); } });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(() => new Promise((resolve) => server.close(resolve)));
  const { port } = server.address();
  const response = await fetch(`http://127.0.0.1:${port}/install.sh`);
  assert.equal(response.status, 502);
});
