#!/usr/bin/env python3
"""Report broad exception handlers around selected calls in one Python file."""

from __future__ import annotations

import argparse
import ast
import sys
import tokenize
from dataclasses import dataclass
from typing import List, Optional, Tuple


@dataclass(frozen=True)
class Handler:
    node: ast.ExceptHandler
    try_node: ast.Try
    owner: str
    kind: str
    outcome: str
def broad_type(node: Optional[ast.expr], source: str) -> Optional[str]:
    if node is None:
        return "bare"
    if isinstance(node, ast.Name) and node.id in ("Exception", "BaseException"):
        return node.id
    if isinstance(node, ast.Tuple) and any(
        isinstance(item, ast.Name) and item.id in ("Exception", "BaseException")
        for item in node.elts
    ):
        return ast.get_source_segment(source, node) or "tuple"
    return None
def outcome(body: List[ast.stmt]) -> str:
    if any(isinstance(statement, ast.Raise) for statement in body):
        return "raise"
    if body and all(isinstance(statement, ast.Pass) for statement in body):
        return "pass"
    if body and isinstance(body[-1], ast.Return):
        return "return"
    if body and isinstance(body[-1], ast.Continue):
        return "continue"
    if body and all(
        isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Call)
        for statement in body
    ):
        return "log"
    return "other"
class Mapper(ast.NodeVisitor):
    def __init__(self, source: str, callees: List[str]) -> None:
        self.source = source
        self.callees = set(callees)
        self.tries: List[Tuple[ast.Try, Optional[Handler]]] = []
        self.handlers: List[Handler] = []
        self.calls: List[Tuple[int, str, Optional[Handler], str]] = []
        self.owner = "<module>"
        self.container = "module"
        self.classes: List[str] = []

    def visit_nodes(self, nodes: List[ast.AST]) -> None:
        for node in nodes:
            self.visit(node)

    def visit_Try(self, node: ast.Try) -> None:
        broad = []
        for clause in node.handlers:
            kind = broad_type(clause.type, self.source)
            if kind is not None:
                handler = Handler(clause, node, self.owner, kind, outcome(clause.body))
                self.handlers.append(handler)
                broad.append(handler)
        self.tries.append((node, broad[0] if broad else None))
        self.visit_nodes(node.body)
        self.tries.pop()
        for clause in node.handlers:
            if clause.type is not None:
                self.visit(clause.type)
            self.visit_nodes(clause.body)
        self.visit_nodes(node.orelse)
        self.visit_nodes(node.finalbody)

    def visit_Call(self, node: ast.Call) -> None:
        name = None
        if isinstance(node.func, ast.Name):
            name = node.func.id
        elif isinstance(node.func, ast.Attribute):
            name = node.func.attr
        if name in self.callees:
            guarding = next(
                (handler for _, handler in reversed(self.tries) if handler is not None),
                None,
            )
            self.calls.append((node.lineno, name, guarding, self.owner))
        self.generic_visit(node)

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self.visit_nodes(node.decorator_list)
        self.visit_nodes(node.bases)
        self.visit_nodes(node.keywords)
        old_container = self.container
        self.container = "class"
        self.classes.append(node.name)
        self.visit_nodes(node.body)
        self.classes.pop()
        self.container = old_container

    def visit_function(self, node: ast.AST, body: List[ast.stmt], name: str) -> None:
        self.visit_nodes(getattr(node, "decorator_list", ()))
        self.visit(node.args)  # type: ignore[attr-defined]
        returns = getattr(node, "returns", None)
        if returns is not None:
            self.visit(returns)
        old_owner, old_container, old_tries = self.owner, self.container, self.tries
        if self.container == "class" and self.classes:
            self.owner = f"{self.classes[-1]}.{name}"
        else:
            self.owner = name
        self.container = "function"
        self.tries = []
        self.visit_nodes(body)
        self.owner, self.container, self.tries = old_owner, old_container, old_tries

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self.visit_function(node, node.body, node.name)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self.visit_function(node, node.body, node.name)

    def visit_Lambda(self, node: ast.Lambda) -> None:
        self.visit(node.args)
        old_owner, old_container, old_tries = self.owner, self.container, self.tries
        self.owner, self.container, self.tries = "<lambda>", "function", []
        self.visit(node.body)
        self.owner, self.container, self.tries = old_owner, old_container, old_tries


def map_source(filename: str, source: str, callees: List[str], show_handlers: bool) -> List[str]:
    mapper = Mapper(source, callees)
    mapper.visit(ast.parse(source, filename=filename))
    events = []
    for line, callee, handler, owner in mapper.calls:
        if handler is None:
            text = f"{filename}:{line} {callee} in def {owner}: unguarded"
        else:
            text = (
                f"{filename}:{line} {callee} in def {owner}: handler "
                f"{handler.node.lineno}-{handler.node.end_lineno} "
                f"{handler.kind} -> {handler.outcome}"
            )
        events.append((line, 0, text))
    if show_handlers:
        for handler in mapper.handlers:
            text = (
                f"{filename}:{handler.node.lineno}-{handler.node.end_lineno} handler "
                f"{handler.kind} -> {handler.outcome} try "
                f"{handler.try_node.lineno}-{handler.try_node.end_lineno} in def "
                f"{handler.owner}"
            )
            events.append((handler.node.lineno, 1, text))
    return [text for _, _, text in sorted(events)]


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file")
    parser.add_argument("--callee", action="append", default=[], metavar="NAME")
    parser.add_argument("--handlers", action="store_true")
    try:
        args = parser.parse_args(argv)
        if not args.callee and not args.handlers:
            parser.error("at least one --callee or --handlers is required")
        with tokenize.open(args.file) as stream:
            source = stream.read()
        lines = map_source(args.file, source, args.callee, args.handlers)
    except SystemExit:
        return 0
    except Exception as error:
        filename = args.file if "args" in locals() else "<arguments>"
        reason = " ".join(str(error).splitlines()) or error.__class__.__name__
        print(f"{filename}: {reason}", file=sys.stderr)
        return 0
    if lines:
        print("\n".join(lines))
    return 0
if __name__ == "__main__":
    sys.exit(main())
