#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = process.env.LOOP_PROJECT_ROOT ? resolve(process.env.LOOP_PROJECT_ROOT) : null;
const runDirectory = process.env.LOOP_RUN_DIRECTORY ? resolve(process.env.LOOP_RUN_DIRECTORY) : null;
if (!root || !runDirectory) throw new Error('LOOP_PROJECT_ROOT and LOOP_RUN_DIRECTORY are required.');
const head = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
const requestedSha = process.env.LOOP_RELEASE_SHA;
if (!requestedSha || requestedSha !== head) throw new Error('The loop release SHA must match the target repository HEAD.');
const manifestPath = resolve(runDirectory, 'release', 'manifest.json');
if (!existsSync(manifestPath)) throw new Error(`Release manifest is unavailable: ${manifestPath}`);
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
if (manifest?.kind !== 'loop-release-manifest' || manifest?.source?.sha !== head) {
  throw new Error(`Release manifest does not bind current HEAD ${head}.`);
}

const field = process.argv[2] ?? 'json';
if (field === '--sha') process.stdout.write(`${head}\n`);
else if (field === '--path') process.stdout.write(`${manifestPath}\n`);
else if (field === '--run-directory') process.stdout.write(`${runDirectory}\n`);
else process.stdout.write(`${JSON.stringify({ sha: head, manifestPath, runDirectory, releaseId: manifest.releaseId })}\n`);
