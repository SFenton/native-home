#!/usr/bin/env python3
"""Measure a derived or probe question against its local label set (ad hoc; not part of the product).

    python3 contracts/jev/derived/measure.py owner_msg.reports_failed_fix [more ids ...] [--max-spend 2.0] [--split dev|test]

With --split dev|test only label items whose "split" equals it are kept; without --split every item is kept.
Reads the question wording from candidates.json or probes.json (so the measured wording is the documented
wording), asks `tools/jev_ask.ask` once per labelled item (cache and call log under build/jev), writes
results/<id>.jsonl, or results/<id>.<split>.jsonl with --split (label, answer, probabilities; no text) and prints a summary. The API key is read by
jev_ask itself and is never printed. Exit 3 when Jev is unavailable.
"""
from __future__ import annotations
import json, math, os, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
os.environ.setdefault("JEV_HOME", str(ROOT / "build" / "jev"))
import jev_ask  # noqa: E402


def load_defs() -> dict:
    defs = {c["id"]: c for c in json.loads((HERE / "candidates.json").read_text())["candidates"]}
    defs.update({c["id"]: c for c in json.loads((HERE / "probes.json").read_text())["probes"]})
    return defs


def api_question(d: dict) -> dict:
    q = {"type": d["type"], "instructions": d["instructions"]}
    criteria = d.get("options") or d.get("criteria")
    if criteria is not None:  # a noul probe may have none
        q["criteria"] = criteria
    return q


def auc(pairs):  # (score, is_pos)
    pos = [s for s, y in pairs if y]; neg = [s for s, y in pairs if not y]
    if not pos or not neg: return float("nan")
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return wins / (len(pos) * len(neg))


def ranks(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i]); r = [0.0] * len(xs); i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]: j += 1
        for k in range(i, j + 1): r[order[k]] = (i + j) / 2 + 1
        i = j + 1
    return r


def spearman(a, b):
    ra, rb = ranks(a), ranks(b); n = len(a); ma, mb = sum(ra) / n, sum(rb) / n
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    den = math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))
    return num / den if den else float("nan")


def run(qid: str, split: str | None = None) -> dict:
    d = load_defs()[qid]
    items = [json.loads(l) for l in (HERE / d["labels"]).read_text().splitlines() if l.strip()]
    if split:
        items = [it for it in items if it.get("split") == split]
    q = {"answer": api_question(d)}; field = d["state_fields"][0]

    def one(it):
        a = jev_ask.ask(q, {field: it["text"]}, tag="derive." + qid)
        return None if a is None else a["answer"]
    with ThreadPoolExecutor(6) as ex: answers = list(ex.map(one, items))
    if any(a is None for a in answers):
        print("jev unavailable", file=sys.stderr); sys.exit(3)
    (HERE / "results").mkdir(exist_ok=True)
    rows = []
    for it, a in zip(items, answers):
        rows.append({"id": it["id"], "label": it["label"], "answer": a.value, "confidence": round(a.confidence, 3),
                     "probabilities": {str(k): round(v, 3) for k, v in a.probabilities.items()},
                     "score": None if a.score is None else round(a.score, 3)})
    (HERE / "results" / (f"{qid}.{split}.jsonl" if split else f"{qid}.jsonl")).write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    return summarize(d, rows)


def summarize(d: dict, rows: list) -> dict:
    n = len(rows); out = {"id": d["id"], "type": d["type"], "n": n}
    if d["type"] == "noul":
        p = [r["probabilities"]["true"] for r in rows]; y = [bool(r["label"]) for r in rows]
        out["pos"] = sum(y); out["auc"] = round(auc(list(zip(p, y))), 3)
        for t in (0.3, 0.5, 0.7, 0.85):
            tp = sum(pi >= t and yi for pi, yi in zip(p, y)); fp = sum(pi >= t and not yi for pi, yi in zip(p, y))
            out[f"t{t}"] = {"precision": round(tp / (tp + fp), 3) if tp + fp else None, "recall": round(tp / max(1, sum(y)), 3), "flagged": tp + fp}
        out["uncertain_0.3_0.7"] = sum(0.3 <= pi <= 0.7 for pi in p)
    elif d["type"] == "choice":
        ok = [r["answer"] == r["label"] for r in rows]; out["accuracy"] = round(sum(ok) / n, 3)
        for t in (0.6, 0.8):
            sel = [o for r, o in zip(rows, ok) if r["confidence"] >= t]
            out[f"conf>={t}"] = {"coverage": round(len(sel) / n, 3), "accuracy": round(sum(sel) / len(sel), 3) if sel else None}
        conf = {}
        for r in rows:
            if r["answer"] != r["label"]: conf[f'{r["label"]}->{r["answer"]}'] = conf.get(f'{r["label"]}->{r["answer"]}', 0) + 1
        out["confusions"] = dict(sorted(conf.items(), key=lambda kv: -kv[1])[:8])
        per = {}
        for r in rows: per.setdefault(r["label"], []).append(r["answer"] == r["label"])
        out["recall_by_class"] = {k: f"{sum(v)}/{len(v)}" for k, v in sorted(per.items())}
    else:
        s = [r["score"] for r in rows]; y = [r["label"] for r in rows]
        out["spearman"] = round(spearman(s, y), 3)
        out["exact"] = round(sum(round(a) == b for a, b in zip(s, y)) / n, 3)
        out["within1"] = round(sum(abs(round(a) - b) <= 1 for a, b in zip(s, y)) / n, 3)
        out["mean_pred_by_label"] = {str(k): round(sum(a for a, b in zip(s, y) if b == k) / max(1, sum(b == k for b in y)), 2) for k in sorted(set(y))}
    return out


def spend() -> tuple[int, float]:
    tokens = calls = 0
    try:
        for line in (Path(os.environ["JEV_HOME"]) / "calls.jsonl").read_text().splitlines():
            r = json.loads(line)
            if str(r.get("tag", "")).startswith("derive."):
                calls += 1; tokens += int((r.get("usage") or {}).get("input_tokens") or r.get("input_tokens") or 0)
    except (OSError, ValueError): pass
    return calls, tokens * 4.2e-8


if __name__ == "__main__":
    argv = sys.argv[1:]; split = None
    if "--split" in argv:
        k = argv.index("--split"); split = argv[k + 1]; del argv[k:k + 2]
        if split not in ("dev", "test"): sys.exit("--split takes dev or test")
    ids = [a for a in argv if not a.startswith("--")]
    for qid in ids:
        print(json.dumps(run(qid, split), ensure_ascii=False))
    c, usd = spend(); print(json.dumps({"derive_calls_logged": c, "approx_usd": round(usd, 4)}))
