const ignored = path => path === '.gitignore'
  || path === 'README.md'
  || path === 'shift-handover.md'
  || path.startsWith('docs/')
  || path.startsWith('e2e/');

const sensitiveFrontend = path => /(^|\/)(auth|authentication|billing|checkout|cognito|iam|login|oauth|payment|subscription|trade|trading)([-./]|$)/i.test(path)
  || path === 'frontend/src/lib/config.ts'
  || path.startsWith('frontend/src/lib/api/');

export function classifyProductionFiles(files) {
  const deployable = [];
  const ignoredPaths = [];
  const manualOnly = [];
  const unknown = [];

  for (const path of files) {
    if (ignored(path)) ignoredPaths.push(path);
    else if (path.startsWith('frontend/') && sensitiveFrontend(path)) manualOnly.push(path);
    else if (path.startsWith('frontend/')) deployable.push(path);
    else if (path.startsWith('backend/') || path.startsWith('infrastructure/') || path.startsWith('scripts/')) manualOnly.push(path);
    else unknown.push(path);
  }
  return {
    lanes: deployable.length ? ['ivanry-frontend-static'] : [],
    deployable: deployable.sort(),
    ignored: ignoredPaths.sort(),
    manualOnly: manualOnly.sort(),
    unknown: unknown.sort()
  };
}
