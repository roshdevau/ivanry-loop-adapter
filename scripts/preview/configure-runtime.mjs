#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function configurePreviewRuntime(projectRoot, originValue) {
  const origin = new URL(originValue);
  if (origin.protocol !== 'https:' || origin.pathname !== '/' || origin.search || origin.hash) {
    throw new Error('Preview origin must be an HTTPS origin without a path, query, or fragment.');
  }
  const runtimePath = resolve(projectRoot, 'frontend/public/runtime-config.js');
  const environmentPath = resolve(projectRoot, 'frontend/.env.production.local');
  const raw = readFileSync(runtimePath, 'utf8');
  const match = raw.match(/Object\.freeze\((\{[\s\S]*\})\);/);
  if (!match) throw new Error('Generated frontend runtime configuration cannot be parsed.');
  const config = JSON.parse(match[1]);
  config.apiUrl = new URL('/api', origin).toString().replace(/\/$/, '');
  config.mcpApiUrl = new URL('/connector', origin).toString().replace(/\/$/, '');
  config.appUrl = origin.toString().replace(/\/$/, '');
  config.googleAuthEnabled = false;
  writeFileSync(runtimePath, `// Generated preview configuration; public client values only.\nwindow.APP_CONFIG = Object.freeze(${JSON.stringify(config, null, 2)});\n`);

  const replacements = new Map([
    ['NEXT_PUBLIC_API_URL', config.apiUrl],
    ['NEXT_PUBLIC_MCP_API_URL', config.mcpApiUrl],
    ['NEXT_PUBLIC_APP_URL', config.appUrl],
    ['NEXT_PUBLIC_GOOGLE_AUTH_ENABLED', 'false']
  ]);
  const lines = readFileSync(environmentPath, 'utf8').trimEnd().split('\n').map(line => {
    const key = line.slice(0, line.indexOf('='));
    return replacements.has(key) ? `${key}=${replacements.get(key)}` : line;
  });
  for (const [key, value] of replacements) if (!lines.some(line => line.startsWith(`${key}=`))) lines.push(`${key}=${value}`);
  writeFileSync(environmentPath, `${lines.join('\n')}\n`);
  return { runtimePath, environmentPath, origin: config.appUrl };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const projectRoot = process.env.LOOP_PROJECT_ROOT;
  const origin = process.argv[2];
  if (!projectRoot || !origin) throw new Error('Usage: configure-runtime.mjs <preview-origin> with LOOP_PROJECT_ROOT.');
  process.stdout.write(`${JSON.stringify(configurePreviewRuntime(projectRoot, origin))}\n`);
}
