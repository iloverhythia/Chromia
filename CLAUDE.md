# Chromia: how changes get released

## Push to `test`, never to `main`

- **`test` branch**: every push builds a TEST build (GitHub pre-release
  `test-<date>-<run>`, see `.github/workflows/release.yml`). Test builds talk to
  the test server (`savia-test.savvyscripterpc.workers.dev`) and update from
  other test builds. Players opt in with Settings > Update channel > Test.
- **`main` branch**: production. Only changed by `Servers\Publish to
  production.cmd` on the server PC, which bundles everything on `test` into one
  production release. Don't push to `main` and don't open PRs into it.

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
