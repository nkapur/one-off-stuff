# Lithic API Exploration: Virtual Cards & Auth Stream Access (ASA)

This document summarizes our initial exploration of the Lithic API, focusing on creating virtual cards and implementing a Just-In-Time (JIT) funding model using Auth Stream Access (ASA).

## Overview
Lithic is a developer-centric card issuing platform. We explored how to programmatically issue a virtual card and configure a webhook to conditionally approve or decline transactions in real-time based on the merchant's descriptor.

## Step 1: Issuing a Virtual Card
We created a standard `VIRTUAL` card intended for AI subscriptions. This card was issued via the `/v1/cards` endpoint in the Sandbox environment.

```bash
# Requires LITHIC_SANDBOX_KEY from ~/.zshrc
curl --request POST \
  --url https://sandbox.lithic.com/v1/cards \
  --header "Authorization: ${LITHIC_SANDBOX_KEY}" \
  --header 'Content-Type: application/json' \
  --data '{
    "type": "VIRTUAL",
    "memo": "AI Subscriptions",
    "state": "OPEN",
    "spend_limit": 10000,
    "spend_limit_duration": "MONTHLY"
  }'
```
*Note: Amounts in Lithic are always defined in cents (e.g., 10000 = $100.00).*

## Step 2: Implementing the ASA Webhook
To implement JIT funding and restrict the card's usage exclusively to allowed tech vendors (like Cursor, Gemini, and Claude), we set up a minimal FastAPI server. This server acts as the ASA webhook endpoint.

When a transaction occurs, Lithic pauses the authorization and sends a payload to this endpoint. The server inspects the `merchant.descriptor` and responds with either `APPROVED` or `DECLINED`.

```python
import uvicorn
from fastapi import FastAPI, Request

app = FastAPI()

# Target keywords for your allowed tech vendors
ALLOWED_VENDORS = ["CURSOR", "GEMINI", "CLAUDE", "OPENAI", "ANTHROPIC", "GITHUB"]

@app.post("/asa")
async def auth_stream_access(request: Request):
    payload = await request.json()
    
    # Extract merchant descriptor and transaction amount
    merchant = payload.get("merchant", {})
    descriptor = merchant.get("descriptor", "").upper()
    amount = payload.get("authorization_amount", 0)

    # Allow if the descriptor contains any of our target vendors
    if any(vendor in descriptor for vendor in ALLOWED_VENDORS):
        print(f"✅ APPROVED: {descriptor} for {amount} cents")
        return {"result": "APPROVED"}
    
    # Otherwise, reject
    print(f"❌ DECLINED: {descriptor} is not an allowed tech vendor")
    return {"result": "DECLINED"}

if __name__ == "__main__":
    uvicorn.run("lithic_asa_main:app", port=8000, reload=True)
```

To expose this local server to Lithic's webhooks, we used ngrok (authed with `NGROK_KEY` from `~/.zshrc`):
```bash
ngrok config add-authtoken "${NGROK_KEY}"
ngrok http --url=doozy-uniformed-scuttle.ngrok-free.dev 8000
```
Then enroll the public ASA URL via the responder endpoints API (program is inferred from the API key):
```bash
curl --request POST \
  --url https://sandbox.lithic.com/v1/responder_endpoints \
  --header "Authorization: ${LITHIC_SANDBOX_KEY}" \
  --header 'Content-Type: application/json' \
  --data '{
    "type": "AUTH_STREAM_ACCESS",
    "url": "https://doozy-uniformed-scuttle.ngrok-free.dev/asa"
  }'
```

## Step 3: Simulating Authorizations
We used the Lithic Sandbox simulation endpoints to test the webhook logic without requiring a real merchant.

Env vars (from `~/.zshrc`):
- `LITHIC_SANDBOX_KEY` — Lithic sandbox API key
- `NGROK_KEY` — ngrok authtoken (used when starting the tunnel above)

Set `PAN` to the 16-digit card number from Step 1 (digits only, no spaces).

### Simulation 1: Approved Transaction
Testing an allowed merchant descriptor.
```bash
curl --request POST \
  --url https://sandbox.lithic.com/v1/simulate/authorize \
  --header "Authorization: ${LITHIC_SANDBOX_KEY}" \
  --header 'Content-Type: application/json' \
  --data "{
    \"pan\": \"${PAN}\",
    \"amount\": 2000,
    \"descriptor\": \"GOOGLE *GEMINI\"
  }"
```

### Simulation 2: Declined Transaction
Testing an unauthorized merchant descriptor.
```bash
curl --request POST \
  --url https://sandbox.lithic.com/v1/simulate/authorize \
  --header "Authorization: ${LITHIC_SANDBOX_KEY}" \
  --header 'Content-Type: application/json' \
  --data "{
    \"pan\": \"${PAN}\",
    \"amount\": 1500,
    \"descriptor\": \"STARBUCKS\"
  }"
```

Simulate authorize returns a `token` (transaction ID), not the approve/decline decision. Set `TXN_TOKEN` from that response, then fetch the transaction:

```bash
curl --request GET \
  --url "https://sandbox.lithic.com/v1/transactions/${TXN_TOKEN}" \
  --header "Authorization: ${LITHIC_SANDBOX_KEY}"
```

Check `status` and `result` in the response (e.g. approved vs declined). You should also see the matching `APPROVED` / `DECLINED` log line on the local ASA server.


