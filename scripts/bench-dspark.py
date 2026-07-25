#!/usr/bin/env python3
"""A/B decode-speed benchmark for the DS4 server (dspark on vs off).

Usage:
  ./scripts/bench-dspark.py --label dspark-on  [--port 18000] [--runs 3] [--tokens 800]
  # flip DSpark in Settings (Save & Apply restarts the server), wait for Running, then:
  ./scripts/bench-dspark.py --label dspark-off
  ./scripts/bench-dspark.py --compare dspark-on dspark-off

Measures decode tokens/sec from streaming timestamps (time-to-first-token
excluded, so prefill/KV-cache effects don't pollute the number). Saves each
run's full output so the two modes can be diffed — greedy decoding with and
without DSpark must produce identical text.
"""
import argparse, json, statistics, sys, time, urllib.request
from pathlib import Path

PROMPTS = {
    "code": ("Write a complete, well-commented C implementation of an LRU cache "
             "with a hash map and doubly linked list, including tests in main()."),
    "prose": ("Write an original short story about a lighthouse keeper who "
              "discovers the light attracts more than ships."),
}

OUTDIR = Path(__file__).resolve().parent / "bench-results"


def run_once(port: int, prompt: str, max_tokens: int, effort: str = None):
    payload = {
        "model": "ds4",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "max_tokens": max_tokens,
        "stream": True,
    }
    if effort:
        payload["reasoning_effort"] = effort   # "none" = pure answer, no thinking
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=body, headers={"Content-Type": "application/json"})
    t0 = time.monotonic()
    t_first = None
    chunks = 0
    text = []
    with urllib.request.urlopen(req, timeout=600) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                d = json.loads(payload)["choices"][0]["delta"]
            except (KeyError, IndexError, json.JSONDecodeError):
                continue
            # Thinking streams as reasoning_content; both count as decoded tokens.
            delta = d.get("content") or d.get("reasoning_content")
            if delta:
                if t_first is None:
                    t_first = time.monotonic()
                chunks += 1
                text.append(delta)
    t_end = time.monotonic()
    decode_s = t_end - (t_first or t_end)
    return {
        "ttft_s": round((t_first or t_end) - t0, 3),
        "decode_s": round(decode_s, 3),
        "tokens": chunks,                      # 1 SSE chunk ≈ 1 token; identical proxy across A/B
        "tok_per_s": round(chunks / decode_s, 2) if decode_s > 0 else 0.0,
        "text": "".join(text),
    }


def bench(args):
    OUTDIR.mkdir(exist_ok=True)
    base = PROMPTS[args.prompt]
    print(f"[{args.label}] warm-up ({args.prompt}, {args.tokens} tokens)...")
    run_once(args.port, f"Warm-up: {base}", args.tokens, args.effort)   # discard: shader/page warm-up
    results = []
    for i in range(args.runs):
        # Per-run salt busts KV-cache prefix reuse; the same salt is used for
        # every label, so run i stays byte-comparable across configurations.
        r = run_once(args.port, f"Variant {i + 1}: {base}", args.tokens, args.effort)
        results.append(r)
        print(f"[{args.label}] run {i+1}/{args.runs}: "
              f"{r['tok_per_s']} tok/s decode ({r['tokens']} tokens, "
              f"TTFT {r['ttft_s']}s)")
    for i, r in enumerate(results):
        (OUTDIR / f"{args.label}-run{i + 1}.txt").write_text(r["text"])
    summary = {
        "label": args.label, "prompt": args.prompt, "runs": args.runs,
        "median_tok_per_s": statistics.median(r["tok_per_s"] for r in results),
        "results": [{k: v for k, v in r.items() if k != "text"} for r in results],
    }
    (OUTDIR / f"{args.label}.json").write_text(json.dumps(summary, indent=2))
    print(f"[{args.label}] median decode: {summary['median_tok_per_s']} tok/s "
          f"→ saved to {OUTDIR / (args.label + '.json')}")


def compare(a: str, b: str):
    ja, jb = (json.loads((OUTDIR / f"{x}.json").read_text()) for x in (a, b))
    ra, rb = ja["median_tok_per_s"], jb["median_tok_per_s"]
    print(f"{a}: {ra} tok/s   {b}: {rb} tok/s   speedup: {ra / rb:.2f}x")
    for i in range(min(ja["runs"], jb["runs"])):
        ta = (OUTDIR / f"{a}-run{i + 1}.txt").read_text()
        tb = (OUTDIR / f"{b}-run{i + 1}.txt").read_text()
        print(f"run {i + 1} outputs identical:", "YES" if ta == tb else "NO — investigate!")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--label", help="name for this configuration, e.g. dspark-on")
    p.add_argument("--port", type=int, default=18000)
    p.add_argument("--runs", type=int, default=3)
    p.add_argument("--tokens", type=int, default=800)
    p.add_argument("--prompt", choices=PROMPTS, default="code")
    p.add_argument("--effort", help="reasoning_effort, e.g. 'none' to disable thinking")
    p.add_argument("--compare", nargs=2, metavar=("A", "B"))
    args = p.parse_args()
    if args.compare:
        compare(*args.compare)
    elif args.label:
        bench(args)
    else:
        p.error("need --label to benchmark or --compare A B")
