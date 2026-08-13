#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const [action] = process.argv.slice(2);
const root = process.env.LOOP_PROJECT_ROOT ? resolve(process.env.LOOP_PROJECT_ROOT) : null;
const runDirectory = process.env.LOOP_RUN_DIRECTORY ? resolve(process.env.LOOP_RUN_DIRECTORY) : null;
const sourceSha = process.env.LOOP_RELEASE_SHA;
const stackName = process.env.IVANRY_RELEASE_STACK;
const profile = process.env.AWS_PROFILE;
const region = process.env.AWS_REGION;
const accountId = process.env.IVANRY_RELEASE_ACCOUNT;
if (!root || !runDirectory || !sourceSha || !stackName || !profile || !region || !accountId) fail('Release snapshot contract is incomplete.');
if (!/^[a-f0-9]{40}$/.test(sourceSha)) fail('Release snapshot requires a full exact source SHA.');
const directory = resolve(runDirectory, 'release', 'stack-backup');
const snapshotPath = resolve(directory, `${stackName}.json`);

function aws(args) {
  return JSON.parse(execFileSync('aws', [...args, '--profile', profile, '--region', region, '--output', 'json'], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 50 * 1024 * 1024
  }));
}
function assertIdentity() {
  if (aws(['sts', 'get-caller-identity']).Account !== accountId) fail('Release snapshot AWS account mismatch.');
}
function describe() {
  const stack = aws(['cloudformation', 'describe-stacks', '--stack-name', stackName]).Stacks?.[0];
  if (!stack || !/_(?:CREATE|UPDATE)_COMPLETE$/.test(stack.StackStatus)) fail('Release stack is not in a stable deployed state.');
  return stack;
}

assertIdentity();
if (action === 'capture') {
  if (existsSync(snapshotPath)) fail('A release stack snapshot already exists for this run.');
  const stack = describe();
  const parameters = (stack.Parameters ?? []).map(({ ParameterKey, ParameterValue, UsePreviousValue }) => ({ ParameterKey, ParameterValue, UsePreviousValue }));
  if (parameters.some(parameter => parameter.ParameterValue === '****')) fail('Refusing to snapshot redacted CloudFormation parameter values.');
  const templateValue = aws(['cloudformation', 'get-template', '--stack-name', stackName, '--template-stage', 'Original']).TemplateBody;
  const template = typeof templateValue === 'string' ? templateValue : JSON.stringify(templateValue);
  if (!template || template === '{}') fail('CloudFormation did not return the original deployed template.');
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  writeFileSync(snapshotPath, `${JSON.stringify({ schemaVersion: 1, sourceSha, accountId, region, profile, stackName, capturedAt: new Date().toISOString(), parameters, template }, null, 2)}\n`, { mode: 0o600 });
  chmodSync(snapshotPath, 0o600);
  process.stdout.write(`${JSON.stringify({ status: 'CAPTURED', stackName })}\n`);
} else if (action === 'restore') {
  if (!existsSync(snapshotPath)) fail('No exact-run release stack snapshot is available for rollback.');
  const snapshot = JSON.parse(readFileSync(snapshotPath, 'utf8'));
  if (snapshot?.schemaVersion !== 1 || snapshot.sourceSha !== sourceSha || snapshot.accountId !== accountId || snapshot.region !== region || snapshot.profile !== profile || snapshot.stackName !== stackName || typeof snapshot.template !== 'string' || !Array.isArray(snapshot.parameters)) {
    fail('Release stack snapshot does not belong to this exact target and SHA.');
  }
  const templatePath = resolve(directory, `${stackName}.template.json`);
  writeFileSync(templatePath, snapshot.template, { mode: 0o600 });
  chmodSync(templatePath, 0o600);
  const parameterArgs = snapshot.parameters.flatMap(parameter => parameter.UsePreviousValue
    ? [`ParameterKey=${parameter.ParameterKey},UsePreviousValue=true`]
    : [`ParameterKey=${parameter.ParameterKey},ParameterValue=${parameter.ParameterValue}`]);
  aws(['cloudformation', 'update-stack', '--stack-name', stackName, '--template-body', `file://${templatePath}`, '--capabilities', 'CAPABILITY_NAMED_IAM', 'CAPABILITY_AUTO_EXPAND', ...(parameterArgs.length ? ['--parameters', ...parameterArgs] : [])]);
  execFileSync('aws', ['cloudformation', 'wait', 'stack-update-complete', '--stack-name', stackName, '--profile', profile, '--region', region], { stdio: 'inherit' });
  describe();
  process.stdout.write(`${JSON.stringify({ status: 'RESTORED', stackName })}\n`);
} else {
  fail('Usage: stack-snapshot.mjs <capture|restore>.');
}

function fail(message) { process.stderr.write(`${message}\n`); process.exit(1); }
