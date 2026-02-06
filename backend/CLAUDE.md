# Backend

Elixir/Cowboy WebSocket server that generates images via the Mistral Agents API.

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

- `lib/backend/application.ex` — Cowboy HTTP setup, supervisor, route dispatch
- `lib/backend/websocket_handler.ex` — WebSocket message handling (ping/pong, echo, image generation)
- `lib/backend/mistral/client.ex` — stateless HTTP wrapper for Mistral API (agents, conversations, file download)
- `lib/backend/mistral/agent_server.ex` — GenServer managing the Mistral agent; handles dev mode with placeholders
- `priv/static/debug.html` — browser debug UI for WebSocket testing
- `priv/static/placeholders/` — placeholder images for dev mode
- `priv/static/images/` — generated images (gitignored)

## Configuration

Secrets go in `config/dev_secrets.exs` (gitignored). See `config/secrets_example.exs` for the template.

- `config :backend, mistral_api_key: "..."` — required for production image generation
- `config :backend, dev_mode: true` — uses placeholder images with simulated 12-30s delay instead of calling Mistral
- `config :backend, port: 8080` — HTTP port (default 8080)

Dev mode is enabled by default in `config/dev.exs`.

## Architecture Notes

- All routes are prefixed with an obfuscating path segment (see `@obfuscating_prefix` in `application.ex`)
- The WebSocket handler derives `base_url` from the incoming request's host, port, and path prefix so image URLs work from any client (localhost, LAN, etc.)
- Image generation is async: client gets an immediate `{"type": "generating"}` ack, then receives `{"type": "image_result", "url": "..."}` when ready
- Generated images are saved to disk and served as static files rather than sent as base64 over the WebSocket
- `AgentServer` starts only when `dev_mode` or `mistral_api_key` is configured; tests run without either

## WebSocket Protocol

Endpoint: `/<prefix>/ws`

```
Client -> {"type": "ping"}
Server -> {"type": "pong"}

Client -> {"type": "generate_image", "prompt": "a cat in space"}
Server -> {"type": "generating", "prompt": "a cat in space"}
Server -> {"type": "image_result", "url": "http://host:port/<prefix>/images/abc.jpg"}
   or  -> {"type": "error", "message": "..."}

Client -> {"type": "anything_else", ...}
Server -> {"type": "echo", "data": ...}
```

## Tests

Tests use `gun` to connect to the WebSocket and verify ping/pong and echo behavior. The server must not already be running on port 8080 when running tests.
