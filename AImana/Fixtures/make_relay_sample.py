#!/usr/bin/env python3
"""Writes a SYNTHETIC relay file (no real data) with history + costs, timed relative to now.
Usage: python3 Fixtures/make_relay_sample.py /tmp/relay-sample.json   then launch the app with: -relay-file /tmp/relay-sample.json"""
import json, sys, random, datetime as dt
random.seed(7)
now = dt.datetime.now(dt.timezone.utc)
iso = lambda d: d.strftime("%Y-%m-%dT%H:%M:%SZ")
def hist(kind, window_h, elapsed_h, rate):
    reset = now + dt.timedelta(hours=window_h - elapsed_h)
    pts, t = [], now - dt.timedelta(hours=elapsed_h)
    while t <= now:
        frac = (t - (now - dt.timedelta(hours=elapsed_h))).total_seconds() / 3600
        pts.append({"t": iso(t), "used": round(min(100, rate * frac * (1 + random.uniform(-.1, .1))), 1), "resetsAt": iso(reset)})
        t += dt.timedelta(minutes=5 if window_h <= 5 else 60)
    return kind, reset, pts
def window(kind, minutes, used, reset): return {"kind": kind, "usedPercent": used, "windowMinutes": minutes, "resetsAt": iso(reset)}
def costs(pid, models, scale):
    days = []
    for i in range(29, -1, -1):
        d = (dt.datetime.now() - dt.timedelta(days=i)).date()
        ms = []
        for name, share in models:
            usd = round(scale * share * random.uniform(.2, 1.6), 2)
            ms.append({"model": name, "usd": usd, "tokens": {"input": int(usd * 4e4), "output": int(usd * 6e3), "cacheRead": int(usd * 9e5), "cacheWrite": int(usd * 3e4)}})
        tok = {k: sum(m["tokens"][k] for m in ms) for k in ("input", "output", "cacheRead", "cacheWrite")}
        days.append({"day": d.isoformat(), "tokens": tok, "usd": round(sum(m["usd"] for m in ms), 2), "unpricedTokens": 0, "models": ms})
    return {"providerID": pid, "generatedAt": iso(now), "days": days}
ks, rs, ps = hist("session", 5, 3.2, 14)
kw, rw, pw = hist("weekly", 168, 40, .9)
cs, rcs, pcs = hist("session", 5, 2.1, 22)
cw, rcw, pcw = hist("weekly", 168, 70, .8)
env = {"version": 1, "generatedAt": iso(now), "entries": [
  {"providerID": "claude", "usage": {"providerID": "claude", "providerName": "Claude Code", "plan": "max", "lastUpdated": iso(now), "details": [],
    "windows": [window("session", 300, ps[-1]["used"], rs), window("weekly", 10080, pw[-1]["used"], rw)]}},
  {"providerID": "codex", "usage": {"providerID": "codex", "providerName": "OpenAI Codex", "plan": "plus", "lastUpdated": iso(now), "details": [],
    "windows": [window("session", 300, pcs[-1]["used"], rcs), window("weekly", 10080, pcw[-1]["used"], rcw)]}}],
  "history": [{"providerID": "claude", "kind": "session", "points": ps}, {"providerID": "claude", "kind": "weekly", "points": pw},
              {"providerID": "codex", "kind": "session", "points": pcs}, {"providerID": "codex", "kind": "weekly", "points": pcw}],
  "costs": [costs("claude", [("claude-opus-5", .6), ("claude-sonnet-5-5", .3), ("claude-haiku-4-5-20251001", .1)], 40),
            costs("codex", [("gpt-5.6-sol", .8), ("gpt-5.6-luna", .2)], 12)]}
json.dump(env, open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/relay-sample.json", "w"), indent=1)
print("wrote", sys.argv[1] if len(sys.argv) > 1 else "/tmp/relay-sample.json")
