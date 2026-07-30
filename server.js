'use strict';

const http = require('node:http');

const owner = process.env.GITHUB_OWNER || 'bezsildavno';
const repository = process.env.GITHUB_REPOSITORY || 'nikkigo';
const ref = process.env.GITHUB_REF || 'main';
const rawBaseUrl =
  process.env.RAW_BASE_URL ||
  `https://raw.githubusercontent.com/${owner}/${repository}/${ref}`;

function selectInstaller(requestUrl, userAgent) {
  const os = requestUrl.searchParams.get('os');
  if (requestUrl.pathname === '/install.ps1' || os === 'windows') return 'install.ps1';
  if (
    requestUrl.pathname === '/install.sh' ||
    os === 'unix' ||
    os === 'linux' ||
    os === 'macos'
  ) return 'install.sh';
  if (requestUrl.pathname !== '/install') return null;
  if (/powershell/i.test(userAgent)) return 'install.ps1';
  if (/curl|wget/i.test(userAgent)) return 'install.sh';
  return 'page';
}

function landingPage(host) {
  const safeHost = host.replace(/[^a-zA-Z0-9.:-]/g, '');
  const base = `https://${safeHost}`;
  return `<!doctype html>
<html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NikkiGo</title><body><h1>NikkiGo</h1>
<h2>Windows PowerShell</h2><pre>irm ${base}/install.ps1 | iex</pre>
<h2>Linux / macOS</h2><pre>curl -fsSL ${base}/install.sh | sh</pre>
</body></html>`;
}

function createServer({ fetchImpl = globalThis.fetch } = {}) {
  if (typeof fetchImpl !== 'function') throw new Error('A Fetch API implementation is required');
  return http.createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    const requestUrl = new URL(request.url, `http://${request.headers.host || 'localhost'}`);

    if (requestUrl.pathname === '/health') {
      response.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      response.end(JSON.stringify({ status: 'ok', ref }));
      return;
    }

    const installer = selectInstaller(requestUrl, request.headers['user-agent'] || '');
    if (!installer) {
      response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('Not found\n');
      return;
    }
    if (installer === 'page') {
      response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      response.end(landingPage(request.headers.host || 'localhost'));
      return;
    }

    try {
      const upstream = await fetchImpl(`${rawBaseUrl}/${installer}`, {
        headers: { 'User-Agent': 'NikkiGo-Railway/1.0' },
        signal: AbortSignal.timeout(15000)
      });
      if (!upstream.ok) throw new Error(`GitHub returned HTTP ${upstream.status}`);
      response.writeHead(200, {
        'Content-Type': 'text/plain; charset=utf-8',
        'X-NikkiGo-Installer': installer,
        'X-NikkiGo-Ref': ref
      });
      response.end(await upstream.text());
    } catch (error) {
      response.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end(`NikkiGo installer is temporarily unavailable: ${error.message}\n`);
    }
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  createServer().listen(port, '0.0.0.0', () => {
    process.stdout.write(`NikkiGo bootstrap listening on port ${port}\n`);
  });
}

module.exports = { createServer, selectInstaller };
