#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { classifyReleaseFiles } from './release-plan-policy.mjs';

const root = process.env.LOOP_PROJECT_ROOT ? resolve(process.env.LOOP_PROJECT_ROOT) : null;
const runDirectory = process.env.LOOP_RUN_DIRECTORY ? resolve(process.env.LOOP_RUN_DIRECTORY) : null;
if (!root || !runDirectory) throw new Error('LOOP_PROJECT_ROOT and LOOP_RUN_DIRECTORY are required.');
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const candidateSha = git('rev-parse', 'HEAD');
const baseSha = process.env.LOOP_BASE_SHA;
if (process.env.LOOP_RELEASE_SHA !== candidateSha) throw new Error('Release plan requires the exact loop release SHA.');
if (!/^[a-f0-9]{40}$/.test(baseSha ?? '')) throw new Error('Release plan requires GitHub’s exact PR base SHA.');
git('cat-file', '-e', `${baseSha}^{commit}`);
const manifestPath = process.env.LOOP_RELEASE_MANIFEST;
if (!manifestPath || !existsSync(manifestPath)) throw new Error('Release plan requires its exact release manifest.');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
if (manifest?.kind !== 'loop-release-manifest' || manifest?.source?.sha !== candidateSha) throw new Error('Release manifest is not bound to the exact candidate SHA.');
const status = JSON.parse(readFileSync(resolve(runDirectory, 'status.json'), 'utf8'));
if (status?.change?.manualReviewRequired === true || status?.change?.name === 'high-risk') {
  throw new Error('The reviewed research-backend lane is unavailable for a high-risk or manual-review change class.');
}
const files = git('diff', '--name-only', `${baseSha}...${candidateSha}`).split('\n').filter(Boolean);
const classification = classifyReleaseFiles(files);
if (classification.manualOnly.length) throw new Error(`Release contains manual-only paths:\n- ${classification.manualOnly.join('\n- ')}`);
if (classification.unknown.length) throw new Error(`Release mapping is missing for:\n- ${classification.unknown.join('\n- ')}`);
if (!classification.lanes.length) throw new Error('Release has no mapped delivery change.');
process.stdout.write(`${JSON.stringify({
  schemaVersion: 2,
  candidateSha,
  baseSha,
  mergeBaseSha: git('merge-base', baseSha, candidateSha),
  files,
  ...classification,
  releaseManifestSha256: createHash('sha256').update(readFileSync(manifestPath)).digest('hex')
}, null, 2)}\n`);
