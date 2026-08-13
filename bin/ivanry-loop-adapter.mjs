#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const adapterRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const projectRoot = process.env.LOOP_PROJECT_ROOT ? resolve(process.env.LOOP_PROJECT_ROOT) : null;
if (!projectRoot) fail('LOOP_PROJECT_ROOT is required; invoke this adapter through loopctl.');

const [area, action] = process.argv.slice(2);
const environment = { ...process.env, LOOP_PROJECT_ROOT: projectRoot, IVANRY_LOOP_ADAPTER_ROOT: adapterRoot };

if (area === 'validate') {
  const scope = action ?? 'application';
  const commands = scope === 'frontend'
    ? [['npm', ['run', 'build', '--workspace', 'frontend']]]
    : [
        ['npm', ['run', 'build', '--workspace', 'frontend']],
        ['npm', ['run', 'build', '--workspace', 'backend']],
        ['npm', ['run', 'build', '--workspace', 'infrastructure']]
      ];
  for (const [command, args] of commands) run(command, args, projectRoot);
  process.exit(0);
}

const allowed = {
  preview: new Set(['verify', 'deploy', 'rollback', 'e2e', 'cleanup']),
  production: new Set(['verify', 'deploy', 'smoke', 'rollback']),
  'platform-repair': new Set(['validate', 'deploy', 'verify', 'rollback'])
};
if (!allowed[area]?.has(action)) fail('Usage: ivanry-loop-adapter <validate [frontend|application]|preview ACTION|production ACTION|platform-repair ACTION>');

const scripts = {
  preview: {
    verify: 'verify-target.sh',
    deploy: 'deploy-release.sh',
    rollback: 'rollback-preview.sh',
    e2e: 'e2e-connector-access.sh',
    cleanup: 'cleanup-connector-access.sh'
  },
  production: {
    verify: 'verify-target.sh',
    deploy: 'deploy-release.sh',
    smoke: 'smoke-release.sh',
    rollback: 'rollback-release.sh'
  },
  'platform-repair': {
    validate: 'validate.sh',
    deploy: 'deploy.sh',
    verify: 'verify.sh',
    rollback: 'rollback.sh'
  }
};
run('bash', [join(adapterRoot, 'scripts', area, scripts[area][action])], projectRoot);

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, env: environment, stdio: 'inherit', shell: false });
  if (result.error) fail(result.error.message);
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function fail(message) {
  console.error(message);
  process.exit(2);
}
