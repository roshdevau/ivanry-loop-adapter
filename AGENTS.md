# IVANRY adapter invariants

- This repository contains IVANRY-specific loop configuration and reviewed
  delivery adapters. The generic state machine and orchestration belong in
  `ROSHDEVAU/loop-engineering`; product code belongs in
  `ROSHDEVAU/stock-portfolio-mgmt`.
- Adapter commands must receive the target product root through
  `LOOP_PROJECT_ROOT`, validate the exact release SHA and target before writes,
  and fail closed when scope is unmapped.
- Never place credentials, access tokens, AWS SSO data, synthetic-user
  passwords, or customer data in this repository or command output.
- Local tests and synthesis are allowed. Do not deploy preview or production
  unless the user separately requests that release action.
- Production requires exact-SHA preview evidence and explicit human approval;
  identity, IAM, migrations, destructive data, billing, financial-history,
  backend, and infrastructure changes are not part of the automatic frontend
  lane.
