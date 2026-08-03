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
    uvicorn.run("main:app", port=8000, reload=True)