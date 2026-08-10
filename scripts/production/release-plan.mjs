#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { classifyProductionFiles } from './release-plan-policy.mjs';

const root = process.env.LOOP_PROJECT_ROOT ? resolve(process.env.LOOP_PROJECT_ROOT) : null;
if (!root) throw new Error('LOOP_PROJECT_ROOT is required.');
const run = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const candidateSha = run('rev-parse', 'HEAD');
if (process.env.LOOP_RELEASE_SHA !== candidateSha) throw new Error('Release plan requires the exact loop release SHA.');
const baseSha = process.env.LOOP_BASE_SHA;
if (!/^[a-f0-9]{40}$/.test(baseSha ?? '')) throw new Error('Release plan requires GitHub’s exact PR base SHA.');
run('cat-file', '-e', `${baseSha}^{commit}`);
const releaseManifest = process.env.LOOP_RELEASE_MANIFEST;
if (!releaseManifest) throw new Error('Release plan requires its exact release manifest.');
const status = JSON.parse(readFileSync(resolve(process.env.LOOP_RUN_DIRECTORY, 'status.json'), 'utf8'));
if (status?.change?.manualReviewRequired === true || status?.change?.name === 'high-risk') {
  throw new Error('Automatic production promotion is unavailable for a high-risk or manual-review change class.');
}
const files = run('diff', '--name-only', `${baseSha}...${candidateSha}`).split('\n').filter(Boolean);
const classification = classifyProductionFiles(files);
if (classification.manualOnly.length) throw new Error(`Production release contains manual-only paths:\n- ${classification.manualOnly.join('\n- ')}`);
if (classification.unknown.length) throw new Error(`Production release mapping is missing for:\n- ${classification.unknown.join('\n- ')}`);
if (!classification.lanes.length) throw new Error('Production release has no mapped static-frontend change.');

process.stdout.write(`${JSON.stringify({
  schemaVersion: 1,
  candidateSha,
  baseSha,
  mergeBaseSha: run('merge-base', baseSha, candidateSha),
  files,
  ...classification,
  resourceAllowlist: ['ivanry-frontend-static'],
  releaseManifestSha256: createHash('sha256').update(readFileSync(releaseManifest)).digest('hex')
}, null, 2)}\n`);
