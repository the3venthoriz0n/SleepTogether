# Server patch: real time advance on sleep

## What the patch is

A small change to the Skyrim Together Reborn server that adds two calendar functions
callable from Lua. Sleep Together uses them so that when everyone sleeps, in-game time
really advances and the new date is shared with all players.

## Where the code lives

- Fork branch: `sleep-time-advance` in `the3venthoriz0n/TiltedEvolution`
- Based on: `player-inventory-transfers` (commit `cedb9bb9`)

## The patch files

Three `git format-patch` files, to be applied in this order with `git am`:

1. `0001-server-add-DateTime-AdvanceHours-and-HoursUntil-with.patch` (DateTime
   `AdvanceHours` and `HoursUntil`, with unit tests)
2. `0002-server-expose-CalendarService-AdvanceHours-and-Hours.patch` (CalendarService
   and the Lua bindings)
3. `0003-ci-build-the-sleep-time-advance-branch-to-the-sleep-.patch` (the GitHub Actions
   change that builds the branch to the `:sleep` image tag)

Verified on 2026-11-11: the three patches were applied in order with `git am` to a clean
checkout of `player-inventory-transfers` and gave the same diff stat as the fork branch.
This was a local `git am` check only: the server was NOT built and was not run.

The patch files use LF line endings (the server sources are LF in the git index).
`.gitattributes` in this repository marks `server/patches/*.patch` as `-text`, so Windows
`autocrlf` cannot rewrite them (which would break `git am`). Do not convert them.

## Building the server image

Pushing the branch `sleep-time-advance` starts the GitHub Actions workflow
`docker-patched-server.yml`. It builds the server (amd64 only, roughly 40+ minutes) and
publishes it as:

    ghcr.io/<owner>/st-reborn-server:sleep

The `:patched` tag is never written by this workflow, so your current stable image is
untouched. This workflow has not been run yet.

## Rolling back

Point the server's image back to `ghcr.io/<owner>/st-reborn-server:patched` and restart.

## Required server settings

In `STServer.ini`, under `[Gameplay]`, this must be set so clients' dates follow the
server's:

    bSyncPlayerCalendar=true

## Relay resource

Replace the `strpm-chat-relay` resource on the server with the new one from
`SleepTogether-Server-0.2.0.zip`, then restart the server. Both the patched server and the
new relay are required.
