# IVANRY loop adapter

This private repository is the IVANRY-specific boundary around the generic
[`ROSHDEVAU/loop-engineering`](https://github.com/ROSHDEVAU/loop-engineering)
controller. It owns IVANRY's model routing, GitHub Project mapping, validation
commands, the `preview.ivanry.com` sandbox contract, and narrowly scoped static-frontend
production adapter.

The stock portfolio repository intentionally contains no loop configuration,
dispatcher, preview, production, or release-plan scripts. A local registry
links that repository identity to this checked-in configuration:

```sh
cd /path/to/stock-portfolio-mgmt
loopctl project link /path/to/ivanry-loop-adapter/loop.config.json
loopctl doctor
```

`ivanry-loop-adapter` is installed locally with `npm link`. Every command uses
`LOOP_PROJECT_ROOT` supplied by `loopctl`; it never guesses another checkout.

The automatic production lane accepts only mapped static frontend changes plus
non-deploying documentation/E2E evidence. Backend, infrastructure, identity,
access-control, financial-data, billing, migration, and unknown paths fail
closed for a separately reviewed lane. No deployment runs during installation
or tests.

Preview delivery is bound to AWS account `109837541383`, profile
`ivanry-sandbox`, `us-east-1`, and the verified `IvanrySandboxCoreStack`
outputs. A frontend-only preview captures the current versioned S3 object set,
builds the exact loop SHA with public sandbox runtime values, publishes it to
the verified sandbox bucket, and invalidates the verified distribution. It
does not run CDK. If E2E fails, rollback restores the captured object versions.

Preview preparation refreshes the one permanent reserved
`loop.preview.e2e@portfolio.invalid` identity and its sandbox-only paid profile,
writes credentials only to an ignored mode-0600 runtime file, allows the build
and invalidation interval for propagation, and deletes that file after E2E.
Playwright never rotates the password immediately before browser sign-in. An existing Cognito identity is accepted only when it is the
exact confirmed reserved address; an existing application record must also be
marked `e2eSynthetic=true`.
