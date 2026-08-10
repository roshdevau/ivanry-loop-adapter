# IVANRY loop adapter

This private repository is the IVANRY-specific boundary around the generic
[`ROSHDEVAU/loop-engineering`](https://github.com/ROSHDEVAU/loop-engineering)
controller. It owns IVANRY's model routing, GitHub Project mapping, validation
commands, isolated preview contract, and narrowly scoped static-frontend
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
