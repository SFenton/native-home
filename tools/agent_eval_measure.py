#!/usr/bin/env python3
"""agent_eval_measure: asks Jev one held-out question set, in its own process, with trusted code only.

    python3 -I tools/agent_eval_measure.py --trusted DIR --out FILE < {"question": {...}, "field": "...", "tag": "...", "items": [...]}

``tools/agent_eval.py`` (the trusted parent) starts this for tier 1 with ``--trusted`` its own checkout. ``sys.path`` holds
the trusted checkout's ``tools`` and the standard library, nothing from the lane, so a lane file named like a standard library
module cannot run here, and no lane ``measure.py`` runs at all: the question (the lane's wording, read as data) and the held-out
items (the base's) come in on stdin, ``tools/jev_ask.py`` is the trusted one. One ``jev_ask.ask`` per item; the result rows go to
``--out`` (a temp dir, never a tracked results file). Exit 3 when Jev is unavailable.

This file is in the fixed set (``tools/agent_eval*.py``).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

EXIT_UNAVAILABLE = 3


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--trusted", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    trusted = Path(args.trusted).resolve()
    request = json.loads(sys.stdin.read())
    sys.path.insert(0, str(trusted / "tools"))
    os.environ.setdefault("JEV_HOME", str(trusted / "build" / "jev"))
    import jev_ask  # the trusted one: only the trusted tools directory is ahead of the standard library

    question, field, tag = request["question"], request["field"], str(request.get("tag", "derive.eval"))
    items = request["items"]

    def one(item):
        answer = jev_ask.ask({"answer": question}, {field: item["text"]}, tag=tag)
        return None if answer is None else answer["answer"]

    with ThreadPoolExecutor(6) as pool:
        answers = list(pool.map(one, items))
    if any(a is None for a in answers):
        print("jev unavailable", file=sys.stderr)
        return EXIT_UNAVAILABLE
    rows = [{"id": it["id"], "label": it["label"], "answer": a.value, "confidence": round(a.confidence, 3),
             "probabilities": {str(k): round(v, 3) for k, v in a.probabilities.items()},
             "score": None if a.score is None else round(a.score, 3)} for it, a in zip(items, answers)]
    Path(args.out).write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
