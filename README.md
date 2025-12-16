# Gauntlet Go

Mobile-first, 10-player party gauntlet built with Phoenix Channels. Three rounds, one winner, live leader crown.

Match loop: up to 10 players per room, auto-starts when someone joins, auto-restarts a fresh gauntlet every 5 minutes (scores reset each gauntlet).

## Rounds
- **Round 1 – Survival Rush:** +1 point/sec while alive, bonus pickups, hazards knock you out, last standing gets +15.
- **Round 2 – Carry the Light:** Carry = +2/sec, assists = +1/sec, steals = +5, final carrier +10. Help or betray at will.
- **Round 3 – Leak Run:** Everyone bleeds -1/sec until they finish the course. Faster = more points saved.
- **Crown:** ⛅ Crown floats over the live leader (highest score, earliest finish wins ties).

## Controls (phones)
- Left thumb: on-screen joystick (move)
- Jump button
- Action button (pickup/steal/assist in Round 2)

## Local run
```bash
mix deps.get
mix assets.build   # first run to build assets
mix phx.server
# open http://localhost:4000
```

## Render deployment (HTTPS + WebSockets)
1) Create a **Web Service** on Render, repo: this project, root: `/`, language: Elixir.
2) Env vars:
   - `PHX_HOST=gauntlet-go.onrender.com` (host only, no https://)
   - `SECRET_KEY_BASE=<mix phx.gen.secret output>`
   - `PORT` is provided by Render.
3) Build command:
   ```bash
   MIX_ENV=prod mix deps.get --only prod && MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release
   ```
4) Start command:
   ```bash
   MIX_ENV=prod PHX_SERVER=true PORT=$PORT _build/prod/rel/gauntlet_go/bin/gauntlet_go start
   ```
5) Use a paid (non-sleeping) instance for game night to avoid cold starts.

## Repo layout
- `lib/gauntlet_go/game_room.ex` – authoritative room process + round transitions
- `lib/gauntlet_go/rounds/*.ex` – per-round rules
- `lib/gauntlet_go_web/channels/game_channel.ex` – WebSocket input/output
- `assets/js/game.js` – mobile controls, channel client, canvas rendering
- `lib/gauntlet_go_web/controllers/page_html/home.html.heex` – landing + HUD

## Quick join flow
1) Start the server, load the homepage on your phone.
2) Enter a room code (e.g., `family`) and your name, tap **Join/Rejoin**.
3) Move with the joystick, tap **Jump**, tap **Action** to steal/assist in Round 2.

## Notes
- Tests may fail in restricted environments because `lazy_html` needs network/build tools; re-run `mix test` once dependencies can download/build.
