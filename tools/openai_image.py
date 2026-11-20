#!/usr/bin/env python3
"""Small OpenAI image client for portraits and key art (docs/PORTRAITS.md).

Auth: the cloud proxy injects the real key for api.openai.com, so the header carries a dummy.
Every call is logged to tools/art_spend.jsonl with its token usage and an estimated cost from
gpt-image-2 list prices (per 1M tokens: text in $5, image in $8, image out $30). OpenAI has no
balance endpoint for this key, so the estimate is the only per-call figure.

    python3 tools/openai_image.py OUT.png "prompt" [--ref a.png --ref b.png] [--quality medium|high] [--size 1024x1536]
"""
import argparse, base64, json, os, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "art_spend.jsonl")
RATES = {"text": 5.0, "image_in": 8.0, "image_out": 30.0}


def cost(usage):
    d = usage.get("input_tokens_details") or {}
    txt = d.get("text_tokens", usage.get("input_tokens", 0) if not d else 0)
    img = d.get("image_tokens", 0)
    out = usage.get("output_tokens", 0)
    return (txt * RATES["text"] + img * RATES["image_in"] + out * RATES["image_out"]) / 1e6


def generate(out, prompt, refs=(), quality="medium", size="1024x1536", model="gpt-image-2", what="image"):
    if refs:
        cmd = ["curl", "-s", "https://api.openai.com/v1/images/edits", "-H", "Authorization: Bearer sk-proxy",
               "-F", f"model={model}", "--form-string", f"prompt={prompt}", "-F", f"size={size}", "-F", f"quality={quality}"]
        for r in refs:
            cmd += ["-F", f"image[]=@{r}"]
    else:
        body = json.dumps({"model": model, "prompt": prompt, "size": size, "quality": quality})
        cmd = ["curl", "-s", "https://api.openai.com/v1/images/generations", "-H", "Authorization: Bearer sk-proxy",
               "-H", "Content-Type: application/json", "-d", body]
    r = json.loads(subprocess.run(cmd, capture_output=True, text=True, timeout=600).stdout)
    if "error" in r:
        raise SystemExit(json.dumps(r["error"])[:600])
    with open(out, "wb") as f:
        f.write(base64.b64decode(r["data"][0]["b64_json"]))
    u = r.get("usage", {})
    usd = cost(u)
    with open(LEDGER, "a") as f:
        f.write(json.dumps({"t": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "phase": "8", "tool": "openai",
                            "what": what, "usd": round(usd, 5), "usage": u, "model": model, "quality": quality}) + "\n")
    return usd, u


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("prompt")
    ap.add_argument("--ref", action="append", default=[])
    ap.add_argument("--quality", default="medium"); ap.add_argument("--size", default="1024x1536")
    ap.add_argument("--model", default="gpt-image-2"); ap.add_argument("--what", default="image")
    a = ap.parse_args()
    usd, u = generate(a.out, a.prompt, a.ref, a.quality, a.size, a.model, a.what)
    print(f"${usd:.4f}", json.dumps(u))
