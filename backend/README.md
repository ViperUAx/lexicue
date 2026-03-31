# LexiCue Backend

This backend is the secure middle layer between the LexiCue iPhone app and OpenAI.

The flow is:

1. The iPhone app sends a phrase to this backend.
2. This backend calls OpenAI.
3. This backend returns only the safe result the app needs.

## Endpoints

### `GET /health`

Returns:

```json
{ "ok": true }
```

### `POST /generate-sentence`

Request:

```json
{ "phrase": "laser-focused" }
```

Response:

```json
{
  "sentences": [
    "She stayed laser-focused during the entire negotiation.",
    "The athlete remained laser-focused on the final lap.",
    "By noon, the whole team was laser-focused on the deadline.",
    "He sounded laser-focused when he explained the recovery plan."
  ]
}
```

### `POST /classify-difficulty`

Request:

```json
{ "phrase": "exonerate" }
```

Response:

```json
{ "level": 4 }
```

## Local Run

1. Install Node.js 20 or newer.
2. In this `backend` folder, create a `.env` file from `.env.example`.
3. Set `OPENAI_API_KEY` in that `.env` file.
4. Run:

```bash
npm install
npm start
```

The backend will start on `http://localhost:3000`.

## Connect The iPhone App

In the app's `AI` settings, use your backend base URL:

- local testing on simulator:
  `http://localhost:3000/`
- deployed backend:
  `https://your-service-name.onrender.com/`

For a physical iPhone, `localhost` will not work unless the phone can reach your Mac over the network. Deployment is the simpler path.

## Deploy To Render

1. Push this repository to GitHub.
2. In Render, create a new Web Service from that repo.
3. Render can use `backend/render.yaml`, or you can set:
   - Root Directory: `backend`
   - Build Command: `npm install`
   - Start Command: `npm start`
4. Add environment variables:
   - `OPENAI_API_KEY`
   - `OPENAI_MODEL=gpt-4o-mini`
   - `ALLOWED_ORIGIN`

Set `ALLOWED_ORIGIN` to your website if you later expose this backend to browsers. For the iPhone app, you can leave it empty at first.

## Production Notes

- Do not put the OpenAI API key into the iPhone app.
- Keep returning sanitized errors, not raw provider errors.
- Rate limiting is already enabled here, but you may want stricter limits later.
- Add request logging and monitoring before scaling ads aggressively.
