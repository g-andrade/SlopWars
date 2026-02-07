# Backend

Elixir/Cowboy WebSocket server for the "SLOP!" 2-player artillery/tower-defense game.
Players enter prompts, an AI Slop Brain analyzes them into game builds (stats + asset descriptions),
a Hyper3D pipeline generates 3D models for each build, and the backend manages matchmaking, game rooms, and state.

## Quick Start

```bash
mix deps.get
mix run --no-halt        # starts on port 8080
```

Debug UI: `http://localhost:8080/fhampuaqm7vdq5niuzo3okajq4/debug`

## Common Commands

- `mix compile --warnings-as-errors` — build (treat warnings as errors)
- `mix test` — run tests (requires port 8080 to be free)
- `mix run --no-halt` — start the server

## Project Structure

- `lib/backend/application.ex` — Cowboy HTTP setup, supervisor (Registry, Matchmaker, AssetManager, DynamicSupervisor), route dispatch
- `lib/backend/websocket_handler.ex` — WebSocket message handling for the game protocol
- `lib/backend/matchmaker.ex` — GenServer pairing players into game rooms
- `lib/backend/game_room.ex` — Per-game GenServer managing lifecycle: prompting → generating_assets → playing → game_over
- `lib/backend/asb.ex` — AI Slop Brain: analyzes both players' prompts into balanced builds (tone, stats, descriptions)
- `lib/backend/asset_manager.ex` — GenServer managing async 3D model generation via Hyper3D (job queue, polling, disk persistence)
- `lib/backend/hyper3d/client.ex` — Stateless HTTP wrapper for Hyper3D Rodin Gen-2 API (text-to-3D generation)
- `lib/backend/mistral/client.ex` — Stateless HTTP wrapper for Mistral API (chat completions, agents, file download)
- `lib/backend/mistral/agent_server.ex` — Legacy GenServer for image generation (not currently started)
- `priv/static/debug.html` — Browser debug UI for game testing
- `priv/static/models/` — Generated 3D model files with per-job `status.json` persistence
- `priv/static/images/` — Generated Mistral images (served to clients)
- `priv/static/placeholders/` — Placeholder images and 3D models for dev mode

## Configuration

Secrets go in `config/dev_secrets.exs` (gitignored). See `config/secrets_example.exs` for the template.

- `config :backend, mistral_api_key: "..."` — required for production ASB analysis
- `config :backend, hyper3d_api_key: "..."` — required for production 3D model generation
- `config :backend, dev_mode: true` — ASB returns randomized stub builds; AssetManager returns placeholder models
- `config :backend, port: 8080` — HTTP port (default 8080)

Dev mode is enabled by default in `config/dev.exs` and `config/test.exs`.

## Architecture Notes

- All routes are prefixed with an obfuscating path segment (see `@obfuscating_prefix` in `application.ex`)
- `Backend.GameRegistry` (Registry) is used for naming GameRoom processes by room_id
- `Backend.GameRoomSupervisor` (DynamicSupervisor) supervises per-game GameRoom GenServers
- The WebSocket handler derives `base_url` from the incoming request so model/asset URLs work from any client
- ASB analysis is async: GameRoom kicks off a Task, receives results via `handle_info`
- 3D model generation uses Hyper3D Rodin Gen-2 API, managed by AssetManager with max 4 concurrent jobs
- AssetManager persists job state to `priv/static/models/{id}/status.json` and reloads on startup
- GameRoom tracks 6 assets per game (bomb/tower/shield per player) and broadcasts progress + individual asset readiness

## WebSocket Protocol

Endpoint: `/<prefix>/ws`

```
Client -> {"type": "ping"}
Server -> {"type": "pong"}

Client -> {"type": "join_queue"}
Server -> {"type": "queued"}
Server -> {"type": "matched", "room_id": "abc", "player_number": 1}

Client -> {"type": "submit_prompt", "prompt": "No prisoners!"}
Server -> {"type": "prompt_received", "player_number": 1}
Server -> {"type": "both_prompts_in"}
Server -> {"type": "analyzing"}
Server -> {"type": "builds_ready",
            "your_build": {"tone": "aggressive", "bomb_damage": 8, "tower_hp": 150,
                           "shield_hp": 1, "bomb_description": "...", "tower_description": "...",
                           "shield_description": "...", "bomb_model_url": "...",
                           "tower_model_url": "...", "shield_model_url": "..."},
            "opponent_build": { ... }}

# Asset generation (3D models via Hyper3D)
Server -> {"type": "generating_assets"}
Server -> {"type": "assets_progress", "overall": 45.5, "player1": 50.0, "player2": 41.0}
Server -> {"type": "asset_ready", "player_number": 1, "name": "bomb", "url": "http://..."}
Server -> {"type": "playing"}

# Relay messages (forwarded to opponent as-is, with "player_number" field added)
Client -> {"type": "player_update", "position": {x,y,z}, "rotation": {x,y,z}}
Opponent <- {"type": "player_update", "player_number": 1, "position": {x,y,z}, "rotation": {x,y,z}}

Client -> {"type": "shoot", "power": 5}
Opponent <- {"type": "shoot", "player_number": 1, "power": 5}

# State messages (backend tracks tower HP and detects game over)
Client -> {"type": "tower_hp", "hp": 280}
Server -> both: {"type": "tower_hp", "player_number": 1, "target_player_number": 2, "hp": 280}
Server -> both: {"type": "game_over", "winner_number": 1, "reason": "tower_destroyed"}  (if hp <= 0)

Server -> {"type": "game_over", "winner_number": 1, "reason": "opponent_disconnected"}
```

## Tests

Tests use `gun` to connect to the WebSocket and verify the full game flow (ping/pong, matchmaking, prompt submission, build generation). The server must not already be running on port 8080 when running tests. Test config enables dev_mode so ASB and AssetManager use stubs.
