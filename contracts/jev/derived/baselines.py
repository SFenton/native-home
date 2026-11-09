#!/usr/bin/env python3
"""Keyword baselines for the noul candidates, over the same label sets (the deterministic floor each question must beat)."""
import json, re
from pathlib import Path
H = Path(__file__).parent
B = {
 "owner_msg.reports_failed_fix": r"\bstill\b|\bagain\b|\bnope\b|not it\b|feels (about )?the same|bad again|not good|struggles",
 "owner_msg.standing_rule": r"\balways\b|\bnever\b|from now on|going forward|should (just )?(always|use|follow|open)|is a deprecated|we're going to call|deprecated|\bstandards?\b|must\b",
 "owner_msg.partial_approval": r"(yes|yep|approve[d]?|ok|okay|go|looks good)\b.{3,}(,|\bbut\b|\band\b|\bas long as\b|\bthen\b|\bonce\b|\bwith\b)",
 "pr.user_visible": r"\b(fix|show|shows|add|adds|screen|sheet|tile|page|chip|header|title|tab|icon|scroll|app|camera|duo|ipad|iphone|profile|settings|chores|vacuum)\b",
 "turn.waiting_narration": r"still waiting|waiting on|no change|i'm first in|queued|re-arming|i'll pick up|fifth in|waiting for|nothing has changed|watching",
}
for qid, rx in B.items():
    rows = [json.loads(l) for l in (H / "labels" / f"{qid}.jsonl").read_text().splitlines()]
    hit = [bool(re.search(rx, r["text"], re.I)) for r in rows]; y = [bool(r["label"]) for r in rows]
    tp = sum(h and t for h, t in zip(hit, y)); fp = sum(h and not t for h, t in zip(hit, y))
    print(json.dumps({"id": qid, "n": len(rows), "precision": round(tp / (tp + fp), 3) if tp + fp else None, "recall": round(tp / sum(y), 3), "flagged": tp + fp}))
