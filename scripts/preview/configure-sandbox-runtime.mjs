#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const projectRoot = process.env.LOOP_PROJECT_ROOT && resolve(process.env.LOOP_PROJECT_ROOT);
if (!projectRoot) throw new Error('LOOP_PROJECT_ROOT is required.');

const profile = 'ivanry-sandbox';
const region = 'us-east-1';
const accountId = '109837541383';
const stackName = 'IvanrySandboxCoreStack';
const host = 'preview.ivanry.com';

function aws(args) {
  return JSON.parse(execFileSync('aws', [...args, '--profile', profile, '--region', region, '--output', 'json'], {
    encoding: 'utf8',
  }));
}

const identity = aws(['sts', 'get-caller-identity']);
if (identity.Account !== accountId) throw new Error(`Expected Sandbox account ${accountId}.`);
const stack = aws(['cloudformation', 'describe-stacks', '--stack-name', stackName]).Stacks?.[0];
const outputs = new Map((stack?.Outputs ?? []).map(value => [value.OutputKey, value.OutputValue]));
if (outputs.get('Environment') !== 'sandbox' || outputs.get('WebHost') !== host) {
  throw new Error('The configured stack is not the IVANRY sandbox.');
}
const required = key => {
  const value = outputs.get(key);
  if (!value) throw new Error(`Missing ${stackName}.${key}.`);
  return value;
};
const config = {
  userPoolId: required('UserPoolId'),
  userPoolClientId: required('UserPoolClientId'),
  identityPoolId: required('IdentityPoolId'),
  apiUrl: `https://${host}/api`,
  appUrl: `https://${host}`,
  googleAuthEnabled: false,
  environment: 'sandbox',
  passkeyRelyingPartyId: host,
  region,
};
const runtimePath = resolve(projectRoot, 'frontend/public/runtime-config.js');
const environmentPath = resolve(projectRoot, 'frontend/.env.production.local');
mkdirSync(dirname(runtimePath), { recursive: true });
writeFileSync(runtimePath, `// Generated from verified IVANRY Sandbox outputs. Public client values only.\nwindow.APP_CONFIG = Object.freeze(${JSON.stringify(config, null, 2)});\n`);
writeFileSync(environmentPath, [
  `NEXT_PUBLIC_USER_POOL_ID=${config.userPoolId}`,
  `NEXT_PUBLIC_USER_POOL_CLIENT_ID=${config.userPoolClientId}`,
  `NEXT_PUBLIC_IDENTITY_POOL_ID=${config.identityPoolId}`,
  `NEXT_PUBLIC_API_URL=${config.apiUrl}`,
  `NEXT_PUBLIC_APP_URL=${config.appUrl}`,
  'NEXT_PUBLIC_GOOGLE_AUTH_ENABLED=false',
  'NEXT_PUBLIC_IVANRY_ENVIRONMENT=sandbox',
  `NEXT_PUBLIC_PASSKEY_RP_ID=${host}`,
  `NEXT_PUBLIC_AWS_REGION=${region}`,
  '',
].join('\n'));
process.stdout.write(`${JSON.stringify({ environment: 'sandbox', origin: config.appUrl })}\n`);
