// Throwaway desktop design lab. Node core only; no package installation.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const root = new URL('../', import.meta.url);
export async function prototypeHtml() {
  const source = await readFile(new URL('windows/prototype/index.html', root), 'utf8');
  const jobs = ['CLERIC', 'ASSASSIN', 'GLADIATOR', 'CHANTER'];
  const portraits = await Promise.all(jobs.map(async (job) => [
    job, 'data:image/png;base64,' + (await readFile(new URL('overlay/icons/' + job + '.png', root))).toString('base64')
  ]));
  return source.replace('/* EMBED_CLASS_ASSETS */', 'Object.assign(assets,' + JSON.stringify(Object.fromEntries(portraits)) + ');');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const port = Number(process.env.DAEVALOG_PREVIEW_PORT || 4173);
  const server = createServer(async (req, res) => {
    if (req.url === '/favicon.ico') { res.writeHead(204); res.end(); return; }
    if (new URL(req.url, 'http://localhost').pathname !== '/') { res.writeHead(404); res.end('Not found'); return; }
    try {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(await prototypeHtml());
    } catch (error) {
      res.writeHead(500); res.end(String(error));
    }
  });
  server.listen(port, '127.0.0.1', () => console.log('Desktop prototypes: http://localhost:' + port + '/?variant=A\nCtrl+C to stop. Sample data only.'));
}
