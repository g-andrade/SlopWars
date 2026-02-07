# --- Build stage ---
FROM elixir:1.19-otp-28-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Cache dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

# Copy application code and config
COPY config config
COPY lib lib
COPY priv priv

RUN mix compile --warnings-as-errors

# --- Runtime stage ---
FROM elixir:1.19-otp-28-slim

RUN apt-get update && apt-get install -y --no-install-recommends tini ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Copy build artifacts and source (needed for mix run)
COPY --from=build /app/_build _build
COPY --from=build /app/deps deps
COPY --from=build /app/config config
COPY --from=build /app/lib lib
COPY --from=build /app/priv priv
COPY --from=build /app/mix.exs ./
COPY --from=build /app/mix.lock ./

# Ensure the models directory exists for volume mount
RUN mkdir -p priv/static/models priv/static/images

EXPOSE 8080

# Use tini as init to handle signals properly
ENTRYPOINT ["tini", "--"]

# Run with console logger output
CMD ["mix", "run", "--no-halt"]
