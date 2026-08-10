#!/usr/bin/env node

import { createHash, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { chmodSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const projectRoot = process.env.LOOP_PROJECT_ROOT && resolve(process.env.LOOP_PROJECT_ROOT);
if (!projectRoot) fail('LOOP_PROJECT_ROOT is required.');
if (process.env.LOOP_ALLOW_SANDBOX_IDENTITY_WRITE !== 'true') {
  fail('Set LOOP_ALLOW_SANDBOX_IDENTITY_WRITE=true only for the authorized sandbox synthetic identity.');
}
const profile = 'ivanry-sandbox';
const region = 'us-east-1';
const accountId = '109837541383';
const stackName = 'IvanrySandboxCoreStack';
const host = 'preview.ivanry.com';
const tableName = 'portfolio-users';
const email = 'loop.preview.e2e@portfolio.invalid';
const runtimePath = resolve(projectRoot, 'e2e/.secrets/sandbox-preview-runtime.json');

const identity = aws(['sts', 'get-caller-identity']);
if (identity.Account !== accountId) fail(`Expected Sandbox account ${accountId}.`);
const stack = aws(['cloudformation', 'describe-stacks', '--stack-name', stackName]).Stacks?.[0];
const outputs = new Map((stack?.Outputs ?? []).map(value => [value.OutputKey, value.OutputValue]));
if (outputs.get('Environment') !== 'sandbox' || outputs.get('WebHost') !== host) fail('Target is not the IVANRY sandbox.');
const poolId = outputs.get('UserPoolId');
const clientId = outputs.get('UserPoolClientId');
if (!poolId || !clientId) fail('Sandbox Cognito outputs are missing.');

const listed = aws(['cognito-idp', 'list-users', '--user-pool-id', poolId, '--filter', `email = "${email}"`]).Users ?? [];
if (listed.length > 1) fail('More than one reserved sandbox identity matched.');
let user = listed[0];
const password = `E2e!${randomBytes(24).toString('base64url')}9a`;
if (!user) {
  aws(['cognito-idp', 'admin-create-user', '--user-pool-id', poolId, '--username', email,
    '--temporary-password', password, '--user-attributes', `Name=email,Value=${email}`,
    'Name=email_verified,Value=true', '--message-action', 'SUPPRESS']);
  user = aws(['cognito-idp', 'list-users', '--user-pool-id', poolId, '--filter', `email = "${email}"`]).Users?.[0];
}
assertReservedIdentity(user);
assertExistingRecordIsSafe(user.Username);
aws(['cognito-idp', 'admin-set-user-password', '--user-pool-id', poolId, '--username', user.Username,
  '--password', password, '--permanent']);
const auth = aws(['cognito-idp', 'initiate-auth', '--client-id', clientId, '--auth-flow', 'USER_PASSWORD_AUTH',
  '--auth-parameters', `USERNAME=${email},PASSWORD=${password}`]).AuthenticationResult;
if (!auth?.IdToken) fail('Sandbox Cognito authentication did not return an ID token.');
const claims = JSON.parse(Buffer.from(auth.IdToken.split('.')[1], 'base64url').toString('utf8'));
if (claims.sub !== user.Username || claims.email !== email || claims.token_use !== 'id') fail('Sandbox token identity mismatch.');

await api('/users/me', auth.IdToken);
await api('/users/me', auth.IdToken, { method: 'PUT', body: {
  firstName: 'Loop', lastName: 'Verifier', dateOfBirth: '1985-06-15', country: 'Australia',
  city: 'Melbourne', heardAboutUs: 'SEARCH', primaryGoal: 'RESEARCH_INVESTMENTS',
  preferredCurrency: 'AUD', costBasisMethod: 'FIFO', acceptLegalTerms: true,
} });
const now = new Date().toISOString();
aws(['dynamodb', 'update-item', '--table-name', tableName,
  '--key', JSON.stringify({ userId: { S: claims.sub } }),
  '--update-expression', 'SET #email = :email, #plan = :paid, subscriptionStatus = :active, planSelectedAt = :now, onboardingCompletedAt = :now, onboardingRequired = :complete, updatedAt = :now, e2eSynthetic = :synthetic',
  '--expression-attribute-names', JSON.stringify({ '#email': 'email', '#plan': 'plan' }),
  '--expression-attribute-values', JSON.stringify({
    ':email': { S: email }, ':paid': { S: 'PAID' }, ':active': { S: 'ACTIVE' },
    ':now': { S: now }, ':complete': { BOOL: false }, ':synthetic': { BOOL: true },
  })]);
assertExistingRecordIsSafe(claims.sub, true);

mkdirSync(dirname(runtimePath), { recursive: true, mode: 0o700 });
writeFileSync(runtimePath, `${JSON.stringify({
  schemaVersion: 1, environment: 'sandbox', runId: process.env.LOOP_RELEASE_SHA ?? 'manual',
  email, password, idToken: auth.IdToken, e2eSynthetic: true,
  baseUrl: `https://${host}`, apiUrl: `https://${host}/api`, namespacePrefix: `Loop Preview E2E-${process.env.LOOP_RELEASE_SHA ?? 'manual'}`,
}, null, 2)}\n`, { mode: 0o600 });
chmodSync(runtimePath, 0o600);
process.stdout.write(`${JSON.stringify({ status: 'PREPARED', environment: 'sandbox', user: 'lo***@portfolio.invalid', userIdHash: createHash('sha256').update(claims.sub).digest('hex').slice(0, 12), entitlement: 'PAID/ACTIVE' })}\n`);

function assertReservedIdentity(value) {
  const attributes = new Map((value?.Attributes ?? []).map(attribute => [attribute.Name, attribute.Value]));
  if (!value?.Username || value.Enabled !== true || attributes.get('email') !== email || attributes.get('email_verified') !== 'true' || !email.endsWith('.invalid')) {
    fail('Existing Cognito identity is not the exact confirmed reserved sandbox identity.');
  }
}
function assertExistingRecordIsSafe(userId, mustExist = false) {
  const item = aws(['dynamodb', 'get-item', '--table-name', tableName,
    '--key', JSON.stringify({ userId: { S: userId } }), '--consistent-read']).Item;
  if (!item && !mustExist) return; // Authorized recovery of the exact orphaned reserved Cognito identity.
  if (!item || item.email?.S !== email || item.e2eSynthetic?.BOOL !== true) fail('Sandbox profile is not explicitly marked as the reserved synthetic tenant.');
}
function aws(args) {
  try {
    const value = execFileSync('aws', [...args, '--profile', profile, '--region', region, '--output', 'json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 10 * 1024 * 1024 }).trim();
    return value ? JSON.parse(value) : {};
  } catch { fail(`AWS CLI failed for ${args.slice(0, 2).join(' ')}.`); }
}
async function api(path, token, options = {}) {
  const response = await fetch(`https://${host}/api${path}`, { method: options.method ?? 'GET',
    headers: { Authorization: `Bearer ${token}`, ...(options.body ? { 'Content-Type': 'application/json' } : {}) },
    ...(options.body ? { body: JSON.stringify(options.body) } : {}), signal: AbortSignal.timeout(30_000) });
  const text = await response.text();
  const payload = text ? safeJson(text) : {};
  if (!response.ok || payload.success === false) fail(`${options.method ?? 'GET'} ${path} failed (${response.status}): ${payload.error ?? payload.message ?? 'unknown error'}`);
  return payload.data ?? payload;
}
function safeJson(value) { try { return JSON.parse(value); } catch { return { message: value }; } }
function fail(message) { throw new Error(message); }
