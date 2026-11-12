# Server patch: real time advance on sleep

## What the patch is

A small change to the Skyrim Together Reborn server that adds two calendar functions
callable from Lua. Sleep Together uses them so that when everyone sleeps, in-game time
really advances and the new date is shared with all players.

## Where the code lives

- Fork branch: `sleep-time-advance`
- Based on: `player-inventory-transfers` (commit `cedb9bb9`)

The `*.patch` files in this folder (added later) are `git format-patch` output. They
apply to a clean `player-inventory-transfers` with `git am`.

## Building the server image

Pushing the branch `sleep-time-advance` starts the GitHub Actions workflow
`docker-patched-server.yml`. It builds the server (amd64 only, roughly 40+ minutes) and
publishes it as:

    ghcr.io/<owner>/st-reborn-server:sleep

The `:patched` tag is never written by this workflow, so your current stable image is
untouched.

## Rolling back

Point the server's image back to `ghcr.io/<owner>/st-reborn-server:patched` and restart.

## Required server settings

In `STServer.ini`, under `[Gameplay]`, this must be set so clients' dates follow the
server's:

    bSyncPlayerCalendar=true

## Relay resource

Replace the `strpm-chat-relay` resource on the server with the new one from the Sleep
Together server zip, then restart the server.
