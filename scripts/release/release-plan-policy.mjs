const ignored = path => path === '.gitignore'
  || path === 'README.md'
  || path === 'shift-handover.md'
  || path.startsWith('docs/')
  || path.startsWith('e2e/');

const sensitiveFrontend = path => /(^|\/)(auth|authentication|billing|checkout|cognito|iam|login|oauth|payment|subscription|trade|trading)([-./]|$)/i.test(path)
  || path === 'frontend/src/lib/config.ts'
  || path.startsWith('frontend/src/lib/api/');

// This is deliberately a single product outcome, not a general backend lane.
// Any extra backend, infrastructure, identity, migration, or data path stays
// manual-only until it has its own reviewed mapping.
const researchBackend = path => path === 'backend/functions/portfolios/insights/index.ts';

export function classifyReleaseFiles(files) {
  const frontend = [];
  const research = [];
  const ignoredPaths = [];
  const manualOnly = [];
  const unknown = [];

  for (const path of files) {
    if (ignored(path)) ignoredPaths.push(path);
    else if (researchBackend(path)) research.push(path);
    else if (path.startsWith('frontend/') && sensitiveFrontend(path)) manualOnly.push(path);
    else if (path.startsWith('frontend/')) frontend.push(path);
    else if (path.startsWith('backend/') || path.startsWith('infrastructure/') || path.startsWith('scripts/')) manualOnly.push(path);
    else unknown.push(path);
  }
  return {
    lanes: [
      ...(frontend.length ? ['ivanry-frontend-static'] : []),
      ...(research.length ? ['ivanry-research-backend'] : [])
    ],
    deployable: [...frontend, ...research].sort(),
    ignored: ignoredPaths.sort(),
    manualOnly: manualOnly.sort(),
    unknown: unknown.sort()
  };
}
