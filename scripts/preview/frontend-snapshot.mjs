#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const [command] = process.argv.slice(2);
const profile = 'ivanry-sandbox';
const region = 'us-east-1';
const accountId = '109837541383';
const stackName = 'IvanrySandboxCoreStack';
const host = 'preview.ivanry.com';
const runDirectory = process.env.LOOP_RUN_DIRECTORY && resolve(process.env.LOOP_RUN_DIRECTORY);
const sourceSha = process.env.LOOP_RELEASE_SHA;
if (!runDirectory || !sourceSha || !/^[a-f0-9]{40,64}$/.test(sourceSha)) fail('LOOP_RUN_DIRECTORY and a full LOOP_RELEASE_SHA are required.');
const snapshotPath = resolve(runDirectory, 'preview', 'sandbox-frontend-before.json');

const identity = awsJson(['sts', 'get-caller-identity']);
if (identity.Account !== accountId) fail(`Expected Sandbox account ${accountId}.`);
const stack = awsJson(['cloudformation', 'describe-stacks', '--stack-name', stackName]).Stacks?.[0];
const outputs = new Map((stack?.Outputs ?? []).map(value => [value.OutputKey, value.OutputValue]));
const bucket = outputs.get('FrontendBucketName');
if (!bucket || outputs.get('Environment') !== 'sandbox' || outputs.get('WebHost') !== host) fail('Frontend bucket is not bound to the IVANRY sandbox.');

if (command === 'capture') {
  const snapshot = { schemaVersion: 1, accountId, region, bucket, host, sourceSha, capturedAt: new Date().toISOString(), objects: activeObjects(bucket) };
  mkdirSync(dirname(snapshotPath), { recursive: true });
  writeFileSync(snapshotPath, `${JSON.stringify(snapshot, null, 2)}\n`, { mode: 0o600 });
  chmodSync(snapshotPath, 0o600);
  process.stdout.write(`${JSON.stringify({ status: 'CAPTURED', objects: snapshot.objects.length })}\n`);
} else if (command === 'restore') {
  const snapshot = JSON.parse(readFileSync(snapshotPath, 'utf8'));
  if (snapshot?.schemaVersion !== 1 || snapshot.accountId !== accountId || snapshot.region !== region || snapshot.bucket !== bucket || snapshot.host !== host || snapshot.sourceSha !== sourceSha || !Array.isArray(snapshot.objects)) {
    fail('Sandbox rollback snapshot is malformed or belongs to another release target.');
  }
  const target = new Map(snapshot.objects.map(object => [object.key, object.versionId]));
  for (const object of activeObjects(bucket)) {
    if (!target.has(object.key)) aws(['s3api', 'delete-object', '--bucket', bucket, '--key', object.key]);
  }
  for (const [key, versionId] of target) {
    // AWS CLI performs the URI encoding itself. Pre-encoding route names such
    // as `[portfolioId]` makes S3 look for the literal `%5B...%5D` key and
    // incorrectly report NoSuchVersion.
    aws(['s3api', 'copy-object', '--bucket', bucket, '--key', key,
      '--copy-source', `${bucket}/${key}?versionId=${versionId}`,
      '--metadata-directive', 'COPY']);
  }
  process.stdout.write(`${JSON.stringify({ status: 'RESTORED', objects: target.size })}\n`);
} else {
  fail('Usage: frontend-snapshot.mjs <capture|restore>.');
}

function activeObjects(bucketName) {
  const response = awsJson(['s3api', 'list-object-versions', '--bucket', bucketName]);
  const active = new Map();
  for (const version of response.Versions ?? []) if (version.IsLatest) active.set(version.Key, { key: version.Key, versionId: version.VersionId });
  for (const marker of response.DeleteMarkers ?? []) if (marker.IsLatest) active.delete(marker.Key);
  return [...active.values()].sort((left, right) => left.key.localeCompare(right.key));
}
function awsJson(args) { const value = aws(args).trim(); return value ? JSON.parse(value) : {}; }
function aws(args) {
  return execFileSync('aws', [...args, '--profile', profile, '--region', region, '--output', 'json'], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 50 * 1024 * 1024,
  });
}
function fail(message) { process.stderr.write(`${message}\n`); process.exit(1); }
