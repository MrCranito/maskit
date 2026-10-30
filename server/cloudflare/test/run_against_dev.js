'use strict';
// Lance le Worker en local (`wrangler dev`, délais de grâce à 300 ms) puis rejoue les tests du
// relais Node (../../test/relay.test.js) contre lui : même protocole, mêmes réponses attendues.
// Usage : npm test (dans server/cloudflare/, après npm ci). Code de sortie = celui des tests.
const { spawn, spawnSync } = require('node:child_process');
const path = require('node:path');

const PORT = Number(process.env.RELAY_DEV_PORT || 8799);
const here = path.join(__dirname, '..');

async function waitHealth(ms) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/health`);
      if (r.ok) return true;
    } catch (e) { /* pas encore prêt */ }
    await new Promise((r) => setTimeout(r, 500));
  }
  return false;
}

(async () => {
  const dev = spawn(process.execPath, [path.join(here, 'node_modules', 'wrangler', 'bin', 'wrangler.js'), 'dev', '--port', String(PORT),
    '--ip', '127.0.0.1', '--var', 'HOST_GRACE_MS:300', '--var', 'GUEST_GRACE_MS:300', '--show-interactive-dev-session=false'],
  { cwd: here, stdio: ['ignore', 'pipe', 'pipe'], env: Object.assign({}, process.env, { WRANGLER_SEND_METRICS: 'false' }) });
  let out = '';
  dev.stdout.on('data', (d) => { out += d; });
  dev.stderr.on('data', (d) => { out += d; });
  let code = 1;
  try {
    if (!(await waitHealth(60000))) {
      console.error('wrangler dev ne répond pas :\n' + out.slice(-3000));
    } else {
      const r = spawnSync(process.execPath, ['--test', path.join(here, '..', 'test', 'relay.test.js')],
        { stdio: 'inherit', env: Object.assign({}, process.env, { RELAY_URL: `ws://127.0.0.1:${PORT}` }) });
      code = r.status;
    }
  } finally {
    dev.kill('SIGTERM');
  }
  process.exit(code);
})();
