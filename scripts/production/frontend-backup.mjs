#!/usr/bin/env node

import { execFile, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { promisify } from 'node:util';

const [command, manifestPath, candidatePath, candidateSourceDirectory] = process.argv.slice(2);
const bucket = process.env.PRODUCTION_BUCKET;
const profile = process.env.PRODUCTION_AWS_PROFILE;
const region = process.env.PRODUCTION_AWS_REGION;
if (!['capture', 'verify', 'candidate', 'restore'].includes(command) || !manifestPath || !bucket || !profile || !region || ((command === 'candidate' || command === 'restore') && !candidatePath) || (command === 'candidate' && !candidateSourceDirectory)) {
  throw new Error('Usage: frontend-backup.mjs <capture|verify|candidate|restore> <manifest-path> [candidate-path] with production target environment.');
}

const aws = (...args) => execFileSync('aws', [...args, '--profile', profile, '--region', region], { encoding: 'utf8' });
const awsJson = (...args) => JSON.parse(aws(...args, '--output', 'json'));
const execFileAsync = promisify(execFile);
const awsJsonAsync = async (...args) => JSON.parse((await execFileAsync('aws', [...args, '--profile', profile, '--region', region, '--output', 'json'], { maxBuffer: 10 * 1024 * 1024 })).stdout);
const writeJson = (path, value) => {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.tmp-${process.pid}`;
  writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
  renameSync(temporary, path);
};
const currentObjects = () => {
  const response = awsJson('s3api', 'list-objects-v2', '--bucket', bucket);
  return (response.Contents ?? [])
    .filter(value => !value.Key.startsWith('downloads/'))
    .sort((left, right) => left.Key.localeCompare(right.Key));
};
const objectRecord = async value => {
  const head = await awsJsonAsync('s3api', 'head-object', '--bucket', bucket, '--key', value.Key);
  return {
    key: value.Key,
    eTag: head.ETag,
    contentLength: head.ContentLength,
    contentType: head.ContentType ?? null,
    cacheControl: head.CacheControl ?? null,
    contentEncoding: head.ContentEncoding ?? null,
    contentDisposition: head.ContentDisposition ?? null,
    contentLanguage: head.ContentLanguage ?? null,
    expires: head.Expires ? new Date(head.Expires).toISOString() : null,
    websiteRedirectLocation: head.WebsiteRedirectLocation ?? null,
    metadata: head.Metadata ?? {}
  };
};
const mapConcurrent = async (values, limit, operation) => {
  const results = new Array(values.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, async () => {
    while (next < values.length) {
      const index = next++;
      results[index] = await operation(values[index]);
    }
  }));
  return results;
};
const archiveDirectory = `${manifestPath}.objects`;
const archivePath = key => `${archiveDirectory}/${createHash('sha256').update(key).digest('hex')}.bin`;
const sameObjectSet = (left, right) => left.length === right.length && left.every((value, index) => value.Key === right[index].key && value.ETag === right[index].eTag && value.Size === right[index].contentLength);
const option = (name, value, args) => { if (value !== null && value !== undefined) args.push(name, String(value)); };
const normalized = value => ({
  key: value.key,
  eTag: value.eTag,
  contentLength: value.contentLength,
  contentType: value.contentType,
  cacheControl: value.cacheControl,
  contentEncoding: value.contentEncoding,
  contentDisposition: value.contentDisposition,
  contentLanguage: value.contentLanguage,
  expires: value.expires,
  websiteRedirectLocation: value.websiteRedirectLocation,
  metadata: value.metadata
});
const sameMetadata = (left, right) => Boolean(left && right) && JSON.stringify(normalized(left)) === JSON.stringify(normalized(right));
const sameMetadataExceptETag = (left, right) => Boolean(left && right) && JSON.stringify({ ...normalized(left), eTag: null }) === JSON.stringify({ ...normalized(right), eTag: null });
const fullyDescribeCurrent = () => mapConcurrent(currentObjects(), 12, objectRecord);
const matchesArchivedObject = async (currentObject, archivedObject) => {
  if (!sameMetadataExceptETag(currentObject, archivedObject)) return false;
  const temporary = `${archivePath(archivedObject.key)}.verify-${process.pid}`;
  try {
    await execFileAsync('aws', ['s3api', 'get-object', '--bucket', bucket, '--key', archivedObject.key, temporary, '--profile', profile, '--region', region], { maxBuffer: 10 * 1024 * 1024 });
    return createHash('sha256').update(readFileSync(temporary)).digest('hex') === archivedObject.sha256;
  } finally {
    if (existsSync(temporary)) unlinkSync(temporary);
  }
};
const routeAliases = ['admin', 'about', 'circle', 'connections', 'dashboard', 'downloads', 'help', 'insights', 'intelligence', 'insider-trading', 'login', 'mailroom', 'mobile/oauth/callback', 'mobile/logout/callback', 'news', 'outlook', 'performance', 'portfolio', 'portfolios', 'properties', 'privacy', 'reports', 'research', 'settings', 'stocks', 'terms', 'updates'];
const outputKeys = sourceDirectory => {
  const root = resolve(sourceDirectory);
  const keys = new Set();
  const visit = directory => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const absolute = `${directory}/${entry.name}`;
      if (entry.isDirectory()) visit(absolute);
      else if (entry.isFile()) {
        const key = relative(root, absolute).split('\\').join('/');
        if (!key.startsWith('downloads/')) keys.add(key);
      }
    }
  };
  visit(root);
  for (const route of routeAliases) {
    if (statSync(`${root}/${route}.html`, { throwIfNoEntry: false })?.isFile()) keys.add(route);
  }
  return [...keys].sort();
};

if (command === 'capture') {
  mkdirSync(archiveDirectory, { recursive: true, mode: 0o700 });
  const objects = await mapConcurrent(currentObjects(), 12, async value => {
    const object = await objectRecord(value);
    const output = archivePath(object.key);
    await execFileAsync('aws', ['s3api', 'get-object', '--bucket', bucket, '--key', object.key, output, '--profile', profile, '--region', region], { maxBuffer: 10 * 1024 * 1024 });
    object.sha256 = createHash('sha256').update(readFileSync(output)).digest('hex');
    return object;
  });
  if (!objects.some(object => object.key === 'index.html')) throw new Error('Production frontend backup is missing index.html.');
  writeJson(manifestPath, { schemaVersion: 3, bucket, capturedAt: new Date().toISOString(), archiveDirectory, objects });
  process.stdout.write(`${JSON.stringify({ status: 'PASS', objects: objects.length })}\n`);
  process.exit(0);
}

const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
if (manifest.schemaVersion !== 3 || manifest.bucket !== bucket || !Array.isArray(manifest.objects) || !manifest.objects.length || manifest.archiveDirectory !== archiveDirectory) {
  throw new Error('Frontend backup manifest is malformed or targets a different bucket.');
}
const expected = new Map(manifest.objects.map(object => [object.key, object]));

if (command === 'verify') {
  const listed = currentObjects();
  if (!sameObjectSet(listed, manifest.objects)) {
    throw new Error('Production frontend changed after backup capture; refusing to overwrite concurrent production changes.');
  }
  const current = await fullyDescribeCurrent();
  if (current.some(object => !sameMetadata(object, expected.get(object.key)))) throw new Error('Production frontend metadata changed after backup capture; refusing to overwrite concurrent production changes.');
  process.stdout.write('{"status":"PASS"}\n');
  process.exit(0);
}

if (command === 'candidate') {
  const sourceSha = process.env.LOOP_RELEASE_SHA;
  if (!sourceSha) throw new Error('Frontend candidate manifest requires the exact release SHA.');
  const keys = outputKeys(candidateSourceDirectory);
  if (!keys.includes('index.html')) throw new Error('Frontend candidate manifest is missing index.html.');
  writeJson(candidatePath, { schemaVersion: 2, bucket, sourceBackupSha256: createHash('sha256').update(readFileSync(manifestPath)).digest('hex'), sourceSha, createdAt: new Date().toISOString(), keys });
  process.stdout.write(`${JSON.stringify({ status: 'PASS', objects: keys.length })}\n`);
  process.exit(0);
}

const candidate = JSON.parse(readFileSync(candidatePath, 'utf8'));
if (candidate.schemaVersion !== 2 || candidate.bucket !== bucket || candidate.sourceBackupSha256 !== createHash('sha256').update(readFileSync(manifestPath)).digest('hex') || candidate.sourceSha !== process.env.LOOP_RELEASE_SHA || !Array.isArray(candidate.keys)) {
  throw new Error('Frontend candidate manifest is malformed or does not belong to this backup.');
}
const current = await fullyDescribeCurrent();
const currentObjectsByKey = new Map(current.map(object => [object.key, object]));
const candidateKeys = new Set(candidate.keys);
const releaseState = object => object?.metadata?.['ivanry-release-sha'] === candidate.sourceSha;
for (const key of currentObjectsByKey.keys()) {
  if (!expected.has(key) && !candidateKeys.has(key)) throw new Error(`Frontend rollback found an unexpected post-deployment object: ${key}.`);
}

for (const object of manifest.objects) {
  const currentObject = currentObjectsByKey.get(object.key);
  if (sameMetadata(currentObject, object)) continue;
  // S3 can issue a different ETag for identical restored bytes.  Treat that
  // state as already restored only after proving the archived content and all
  // non-ETag metadata match; never use it to accept an unknown writer.
  if (currentObject && await matchesArchivedObject(currentObject, object)) continue;
  if (candidateKeys.has(object.key) && releaseState(currentObject)) {
    // The conditional write closes the concurrent-writer window after the state check.
  } else if (!candidateKeys.has(object.key) && !currentObject) {
    // This key was deleted by this release; restore only if it remains absent.
  } else {
    throw new Error(`Frontend rollback found an unknown post-deployment state for ${object.key}.`);
  }
  const body = archivePath(object.key);
  if (!existsSync(body) || createHash('sha256').update(readFileSync(body)).digest('hex') !== object.sha256) throw new Error(`Frontend rollback archive mismatch for ${object.key}.`);
  const metadata = Object.entries(object.metadata).map(([key, value]) => {
    if (!/^[A-Za-z0-9-]+$/.test(key) || /[=,\n\r]/.test(value)) throw new Error(`Unsupported protected metadata value for ${object.key}.`);
    return `${key}=${value}`;
  });
  const args = ['s3api', 'put-object', '--bucket', bucket, '--key', object.key, '--body', body];
  option('--content-type', object.contentType, args);
  option('--cache-control', object.cacheControl, args);
  option('--content-encoding', object.contentEncoding, args);
  option('--content-disposition', object.contentDisposition, args);
  option('--content-language', object.contentLanguage, args);
  option('--expires', object.expires, args);
  option('--website-redirect-location', object.websiteRedirectLocation, args);
  if (metadata.length) args.push('--metadata', metadata.join(','));
  if (currentObject) args.push('--if-match', currentObject.eTag);
  else args.push('--if-none-match', '*');
  aws(...args);
}
for (const key of candidate.keys) {
  if (expected.has(key)) continue;
  const currentObject = currentObjectsByKey.get(key);
  if (!currentObject) continue;
  if (!releaseState(currentObject)) throw new Error(`Frontend rollback found an unknown post-deployment object: ${key}.`);
  aws('s3api', 'delete-object', '--bucket', bucket, '--key', key, '--if-match', currentObject.eTag);
}
for (const object of manifest.objects) {
  const restored = awsJson('s3api', 'head-object', '--bucket', bucket, '--key', object.key);
  const restoredRecord = { key: object.key, eTag: restored.ETag, contentLength: restored.ContentLength, contentType: restored.ContentType ?? null, cacheControl: restored.CacheControl ?? null, contentEncoding: restored.ContentEncoding ?? null, contentDisposition: restored.ContentDisposition ?? null, contentLanguage: restored.ContentLanguage ?? null, expires: restored.Expires ? new Date(restored.Expires).toISOString() : null, websiteRedirectLocation: restored.WebsiteRedirectLocation ?? null, metadata: restored.Metadata ?? {} };
  if (!await matchesArchivedObject(restoredRecord, object)) {
    throw new Error(`Frontend rollback metadata mismatch for ${object.key}.`);
  }
}
process.stdout.write(`${JSON.stringify({ status: 'PASS', objects: manifest.objects.length })}\n`);
