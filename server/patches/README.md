# Server patch: real time advance on sleep

## What the patch is

A small change to the Skyrim Together Reborn server that adds two calendar functions
callable from Lua. Sleep Together uses them so that when everyone sleeps, in-game time
really advances and the new date is shared with all players.

## Which server build it is for (read this first)

The server refuses clients whose version string differs from its own. The owner's players
use the **potion-sync client**, which reports `v1.8.4-potions1`. So the server must be built
from **`potion-sync`** with the same version string. This patch is therefore built on top of
`potion-sync`, not on `player-inventory-transfers` (a server built from that branch reports
`v1.8.4` and refuses potion-sync clients: this was found when the first attempt was tried).

## Where the code lives

- Fork branch: `sleep-on-potions` in `the3venthoriz0n/TiltedEvolution`
- Based on: `potion-sync` (commit `bdfe5573`)
- Image tag: `ghcr.io/<owner>/st-reborn-server:sleep-potions`, built with
  `VERSION_OVERRIDE=v1.8.4-potions1`

(An earlier branch, `sleep-time-advance`, builds the same code on `player-inventory-transfers`
as `:sleep` with version `v1.8.4`. It only suits stock `v1.8.4` clients. Do not use it with the
potion-sync client.)

## The patch files

Three `git format-patch` files, to be applied in this order with `git am` to a clean
`potion-sync`:

1. `0001-server-add-DateTime-AdvanceHours-and-HoursUntil-with.patch` (DateTime
   `AdvanceHours` and `HoursUntil`, with unit tests)
2. `0002-server-expose-CalendarService-AdvanceHours-and-Hours.patch` (CalendarService
   and the Lua bindings)
3. `0003-ci-build-sleep-on-potions-to-the-sleep-potions-image.patch` (the GitHub Actions
   change that builds the branch to the `:sleep-potions` image tag; it keeps
   `VERSION_OVERRIDE=v1.8.4-potions1`)

Verified on 2026-11-12: the three patches were applied in order with `git am` to a clean
copy of `potion-sync`, and the resulting file tree was identical to the fork branch's tree
(compared by git tree hash). This was a local `git am` check; the image is built by GitHub
Actions.

The patch files use LF line endings (the server sources are LF in the git index).
`.gitattributes` in this repository marks `server/patches/*.patch` as `-text`, so Windows
`autocrlf` cannot rewrite them (which would break `git am`). Do not convert them.

## Building the server image

Pushing the branch `sleep-on-potions` starts the GitHub Actions workflow
`docker-patched-server.yml`. It builds the server (amd64 only) and publishes it as:

    ghcr.io/<owner>/st-reborn-server:sleep-potions

The `:potions`, `:patched` and `:sleep` tags are never written by this workflow, so your
current images are untouched. (A build of the same code on a different base took about 15
minutes on GitHub Actions.)

## Rolling back

Point the server's image back to `ghcr.io/<owner>/st-reborn-server:potions` (your potion-sync
server) and restart.

## Required server settings

In `STServer.ini`, under `[Gameplay]`, this must be set so clients' dates follow the
server's:

    bSyncPlayerCalendar=true

## Relay resource

Replace the `strpm-chat-relay` resource on the server with the new one from
`SleepTogether-Server-0.3.0.zip`, then restart the server. Both the patched server and the
new relay are required.
