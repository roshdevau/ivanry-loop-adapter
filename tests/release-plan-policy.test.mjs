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

test('the one reviewed Quick Scan backend path maps to its bounded deployment lane', () => {
  assert.deepEqual(classifyProductionFiles([
    'backend/functions/portfolios/insights/index.ts',
    'e2e/specs/sandbox-quick-scan-export.spec.ts'
  ]), {
    lanes: ['ivanry-research-backend'],
    deployable: ['backend/functions/portfolios/insights/index.ts'],
    ignored: ['e2e/specs/sandbox-quick-scan-export.spec.ts'],
    manualOnly: [],
    unknown: []
  });
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
    config.delivery.production.rollbackCommand,
    config.infrastructureRepair.validationCommand,
    config.infrastructureRepair.deployCommand,
    config.infrastructureRepair.verificationCommand,
    config.infrastructureRepair.rollbackCommand
  ];
  assert.equal(commands.every(command => command[0] === 'ivanry-loop-adapter'), true);
  assert.equal(config.delivery.preview.target.origin, 'https://preview.ivanry.com');
  assert.equal(config.delivery.preview.target.environment, 'sandbox');
  assert.equal(config.delivery.preview.target.verificationFacts.accountId, '109837541383');
  assert.equal(config.delivery.preview.syntheticFixture.runtime, 'e2e/.secrets/sandbox-preview-runtime.json');
  assert.deepEqual(config.delivery.production.target.resourceAllowlist, ['PortfolioMgmtStack']);
  assert.deepEqual(config.infrastructureRepair.allowedPaths, ['infrastructure/lib/stacks/ApiStack.ts']);
  assert.equal(config.infrastructureRepair.environment, 'sandbox');
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

test('platform repair owns its sandbox app and cleanup evidence is current-run bound', () => {
  const deploy = readFileSync(new URL('../scripts/platform-repair/deploy.sh', import.meta.url), 'utf8');
  const sandboxApp = readFileSync(new URL('../scripts/platform-repair/sandbox-app.cjs', import.meta.url), 'utf8');
  const cleanup = readFileSync(new URL('../scripts/preview/cleanup-connector-access.sh', import.meta.url), 'utf8');
  const e2e = readFileSync(new URL('../scripts/preview/e2e-connector-access.sh', import.meta.url), 'utf8');
  assert.match(deploy, /--app "node \$SANDBOX_APP"/);
  assert.match(sandboxApp, /IvanrySandboxCoreStack/);
  assert.match(sandboxApp, /ivanryBedrockEnabled', false/);
  assert.match(sandboxApp, /ivanryQuickInsightsEnabled', true/);
  assert.doesNotMatch(deploy, /infrastructure\/bin\/sandbox-preview\.ts/);
  assert.match(cleanup, /\$RUN_DIRECTORY\/preview-e2e\/connector-access-request-audit\.json/);
  assert.match(cleanup, /x\.sourceSha!==process\.argv\[2\]/);
  assert.doesNotMatch(cleanup, /sort \| tail/);
  assert.match(e2e, /-newer "\$MARKER"/);
});

test('backend deploy and every rollback reassert the exact target contract', () => {
  const previewDeploy = readFileSync(new URL('../scripts/preview/deploy-release.sh', import.meta.url), 'utf8');
  const previewRollback = readFileSync(new URL('../scripts/preview/rollback-preview.sh', import.meta.url), 'utf8');
  const productionRollback = readFileSync(new URL('../scripts/production/rollback-release.sh', import.meta.url), 'utf8');
  assert.match(previewDeploy, /git -C "\$ROOT_DIR" rev-parse HEAD/);
  assert.match(previewDeploy, /git -C "\$ROOT_DIR" status --porcelain/);
  assert.match(previewRollback, /LOOP_DELIVERY_TARGET:-\}" = 'ivanry-sandbox'/);
  assert.match(previewRollback, /LOOP_RESOURCE_ALLOWLIST:-\}" = '\["IvanrySandboxCoreStack"\]'/);
  assert.match(productionRollback, /production_require_contract/);
  assert.match(productionRollback, /production_verify_aws_target/);
});
