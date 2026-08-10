import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { classifyProductionFiles } from '../scripts/production/release-plan-policy.mjs';
import { configurePreviewRuntime } from '../scripts/preview/configure-runtime.mjs';

test('a bounded UI copy change maps to the static frontend lane', () => {
  assert.deepEqual(classifyProductionFiles([
    'frontend/src/app/settings/page.tsx',
    'frontend/src/app/help/page.tsx',
    'e2e/specs/connector-access-settings.spec.ts',
    'shift-handover.md'
  ]), {
    lanes: ['ivanry-frontend-static'],
    deployable: ['frontend/src/app/help/page.tsx', 'frontend/src/app/settings/page.tsx'],
    ignored: ['e2e/specs/connector-access-settings.spec.ts', 'shift-handover.md'],
    manualOnly: [],
    unknown: []
  });
});

test('backend, infrastructure, release scripts and sensitive frontend paths fail closed', () => {
  const result = classifyProductionFiles([
    'backend/functions/mcp/portfolio/index.ts',
    'infrastructure/lib/stacks/PortfolioMcpStack.ts',
    'scripts/deploy-production.sh',
    'frontend/src/app/login/page.tsx',
    'frontend/src/lib/api/chatgpt.ts'
  ]);
  assert.deepEqual(result.lanes, []);
  assert.deepEqual(result.manualOnly, [
    'backend/functions/mcp/portfolio/index.ts',
    'frontend/src/app/login/page.tsx',
    'frontend/src/lib/api/chatgpt.ts',
    'infrastructure/lib/stacks/PortfolioMcpStack.ts',
    'scripts/deploy-production.sh'
  ]);
});

test('the external config invokes only the adapter executable for validation and delivery', () => {
  const config = JSON.parse(readFileSync(new URL('../loop.config.json', import.meta.url), 'utf8'));
  const commands = [
    config.validation.command,
    ...Object.values(config.changeControl.classes).map(value => value.validationCommand),
    config.delivery.preview.target.verificationCommand,
    config.delivery.preview.target.deployCommand,
    config.delivery.preview.target.rollbackCommand,
    config.delivery.preview.e2eCommand,
    config.delivery.preview.cleanupCommand,
    config.delivery.production.target.verificationCommand,
    config.delivery.production.deployCommand,
    config.delivery.production.smokeCommand,
    config.delivery.production.rollbackCommand
  ];
  assert.equal(commands.every(command => command[0] === 'ivanry-loop-adapter'), true);
  assert.deepEqual(config.delivery.production.target.resourceAllowlist, ['ivanry-frontend-static']);
});

test('preview runtime rewriting stays in generated product artifacts', () => {
  const root = mkdtempSync(join(tmpdir(), 'ivanry-preview-runtime-'));
  mkdirSync(join(root, 'frontend/public'), { recursive: true });
  writeFileSync(join(root, 'frontend/public/runtime-config.js'), 'window.APP_CONFIG = Object.freeze({"apiUrl":"https://api.example.invalid","mcpApiUrl":"https://mcp.example.invalid","appUrl":"https://www.example.invalid","googleAuthEnabled":true});\n');
  writeFileSync(join(root, 'frontend/.env.production.local'), 'NEXT_PUBLIC_API_URL=https://api.example.invalid\nNEXT_PUBLIC_MCP_API_URL=https://mcp.example.invalid\nNEXT_PUBLIC_APP_URL=https://www.example.invalid\nNEXT_PUBLIC_GOOGLE_AUTH_ENABLED=true\n');
  configurePreviewRuntime(root, 'https://preview.example.invalid');
  const runtime = readFileSync(join(root, 'frontend/public/runtime-config.js'), 'utf8');
  const environment = readFileSync(join(root, 'frontend/.env.production.local'), 'utf8');
  assert.match(runtime, /https:\/\/preview\.example\.invalid\/api/);
  assert.match(runtime, /"googleAuthEnabled": false/);
  assert.match(environment, /NEXT_PUBLIC_MCP_API_URL=https:\/\/preview\.example\.invalid\/connector/);
  assert.doesNotMatch(environment, /www\.example\.invalid/);
});
