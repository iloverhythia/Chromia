# Chromia: how changes get released

## Push to `test`, never to `main`

- **`test` branch**: every push builds a TEST build (GitHub pre-release
  `test-<date>-<run>`, see `.github/workflows/release.yml`). Test builds talk to
  the test server (`savia-test.savvyscripterpc.workers.dev`) and update from
  other test builds. Players opt in with Settings > Update channel > Test.
- **`main` branch**: production. Only changed by `Servers\Publish to
  production.cmd` on the server PC, which bundles everything on `test` into one
  production release. Don't push to `main` and don't open PRs into it.

## Who publishes

Only SavvyScripter (the owner) and breck (player #3) release to players: the
owner with `Servers\Publish to production.cmd`, breck with the Publish button
on the test website. Claude never publishes, never pushes to `main`, never
merges or opens PRs into `main`, and never adds a production version. If `test`
is behind `main`, merge `main` into `test` (not the other way round).

## Working at the same time (more than one person or Claude session)

- Start every piece of work from the newest `test`: `git pull --rebase origin test`.
- Commit small, finished steps and push them straight away. If the push is
  refused (someone pushed first): `git pull --rebase origin test`, fix any
  conflict, push again. Never force-push.
- `NEXT_RELEASE.md` conflicts: keep both sides' lines.
- `scripts/Savia.gd` VERSION_SEQUENCE / VERSION_NOTES and `config/version` in
  `project.godot` only change through the publish, so nobody should be editing
  them on `test`.
- Each push to `test` makes a test build that every tester gets: push working
  code (the build stops before releasing if the game doesn't reach the menu).

## For each change on `test`

- Don't bump the version (no new entry in `VERSION_SEQUENCE` /
  `VERSION_NOTES` in `scripts/Savia.gd`, no `config/version` change in
  `project.godot`). Test builds name themselves; the publish script adds the
  production version.
- Add a line for players to `NEXT_RELEASE.md` ("- what changed, in plain
  words"). Those lines become the release notes.
- Keep `savia.nysr.host` as the server address in scripts: the workflow swaps
  in the test server for test builds. `scripts/BuildChannel.gd` says which kind
  of build is running.
- Never commit the editor's local changes to `project.godot` or
  `scripts/7.png.import` on the server PC's clone.

## The server

The Savia server and website are in the `savia_web` repo (`dev` = test server,
`main` = production), on the same PC: `Servers\savia-test` and `Servers\savia`.
