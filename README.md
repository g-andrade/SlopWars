Slop Wars is an 1vs1 real time multiplayer game, therefore the backend service
needs to run before two instances of the app can connect.

## [UNITY SETUP]

- Make sure git and git lfs is installed to download the required pacakge references
- Unity version is 6000.0.58f2
- Open Scenes > SampleScene
- To change the backend Web Sockets URL to connect to a custom backend server, go to the SampleScene > Managers > paste you url in the "Socket Url" serialised field

---

## [BACKEND SETUP — DOCKER]

The easiest way to run the backend is with [Docker](https://docs.docker.com/get-started/get-docker/). No Erlang or Elixir install required.

### 1. Install Docker

- **Windows / Mac**: Install [Docker Desktop](https://docs.docker.com/desktop/)
- **Linux**: Install [Docker Engine](https://docs.docker.com/engine/install/)

Verify it's working:

```bash
docker --version
```

### 2. Build the image

```bash
cd backend
docker build -t slop-wars-backend .
```

### 3. Configure API keys

Copy the example env file and fill in your keys:

```bash
cp .env.example .env
# Edit .env with your MISTRAL_API_KEY and HYPER3D_API_KEY
```

### 4. Run

```bash
docker run -p 8080:8080 --env-file .env -v ./models:/app/priv/static/models slop-wars-backend
```

Or pass keys directly without an `.env` file:

```bash
docker run -p 8080:8080 \
  -e MISTRAL_API_KEY=your_key_here \
  -e HYPER3D_API_KEY=your_key_here \
  -v ./models:/app/priv/static/models \
  slop-wars-backend
```

The `-v` flag persists generated 3D models across container restarts. The server starts on **port 8080**.
