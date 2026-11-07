"""Tiny reader for the Luau config modules in src/shared/Config.

It understands just enough Luau to read our config files: `X.Key = <expr>` assignments,
table constructors, numbers (incl. 1e6), strings, booleans, + - * / ^ arithmetic,
`local NAME = <number>` constants and `:: Type` casts. Anything else (function calls like
Color3.fromRGB, for loops, functions) is skipped or read as None.

No dependencies, Python 3.8+.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

TOKEN_RE = re.compile(
    r"""
    (?P<ws>\s+)
  | (?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<number>0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)
  | (?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>::|==|~=|<=|>=|\.\.|[{}\[\]()=,;.:+\-*/^%<>#|?&])
    """,
    re.X | re.S,
)


def tokenize(src: str) -> List[Tuple[str, str]]:
    out: List[Tuple[str, str]] = []
    pos = 0
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            pos += 1  # unknown char, skip
            continue
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ws", "comment", "eq"):
            continue
        if kind is None:
            continue
        out.append((kind, m.group(kind)))
    out.append(("eof", ""))
    return out


class Parser:
    def __init__(self, tokens: List[Tuple[str, str]], env: Dict[str, Any]):
        self.t = tokens
        self.i = 0
        self.env = env

    def peek(self, k: int = 0) -> Tuple[str, str]:
        return self.t[min(self.i + k, len(self.t) - 1)]

    def next(self) -> Tuple[str, str]:
        tok = self.t[self.i]
        self.i += 1
        return tok

    def accept(self, value: str) -> bool:
        if self.peek()[1] == value and self.peek()[0] in ("op", "name"):
            self.i += 1
            return True
        return False

    # expressions -------------------------------------------------------------
    def expr(self) -> Any:
        v = self.additive()
        if self.peek()[1] == "::":  # type cast: skip the type
            self.next()
            self.skip_type()
        return v

    def skip_type(self) -> None:
        depth = 0
        while True:
            kind, val = self.peek()
            if kind == "eof":
                return
            if val in ("{", "(", "["):
                depth += 1
            elif val in ("}", ")", "]"):
                if depth == 0:
                    return
                depth -= 1
            elif depth == 0 and val in (",", ";", "="):
                return
            elif depth == 0 and kind == "name" and self.peek(1)[1] in ("=", "."):
                # next statement started (e.g. `Upgrades.ById = ...`)
                return
            self.next()

    def additive(self) -> Any:
        v = self.term()
        while self.peek()[1] in ("+", "-") and self.peek()[0] == "op":
            op = self.next()[1]
            r = self.term()
            v = _arith(op, v, r)
        return v

    def term(self) -> Any:
        v = self.unary()
        while self.peek()[1] in ("*", "/", "%") and self.peek()[0] == "op":
            op = self.next()[1]
            r = self.unary()
            v = _arith(op, v, r)
        return v

    def unary(self) -> Any:
        if self.peek()[1] == "-" and self.peek()[0] == "op":
            self.next()
            v = self.unary()
            return -v if isinstance(v, (int, float)) else None
        return self.power()

    def power(self) -> Any:
        v = self.primary()
        if self.peek()[1] == "^":
            self.next()
            r = self.unary()
            v = _arith("^", v, r)
        return v

    def primary(self) -> Any:
        kind, val = self.next()
        if kind == "number":
            return float(int(val, 16)) if val.lower().startswith("0x") else float(val)
        if kind == "string":
            return bytes(val[1:-1], "utf-8").decode("unicode_escape")
        if val == "{":
            return self.table()
        if val == "(":
            v = self.expr()
            self.accept(")")
            return self.suffix(v)
        if kind == "name":
            if val == "true":
                return True
            if val == "false":
                return False
            if val == "nil":
                return None
            v = self.env.get(val)
            return self.suffix(v, val)
        return None

    def suffix(self, v: Any, name: str = "") -> Any:
        # handles a.b.c and calls f(...) (calls evaluate to None)
        while True:
            val = self.peek()[1]
            if val in (".", ":") and self.peek()[0] == "op" and self.peek(1)[0] == "name":
                self.next()
                key = self.next()[1]
                v = v.get(key) if isinstance(v, dict) else None
            elif val == "(":
                self.next()
                depth = 1
                while depth and self.peek()[0] != "eof":
                    x = self.next()[1]
                    depth += 1 if x == "(" else -1 if x == ")" else 0
                v = None
            elif val == "[" and self.peek(1)[1] != "[":
                self.next()
                k = self.expr()
                self.accept("]")
                v = _index(v, k)
            else:
                return v

    def table(self) -> Any:
        arr: List[Any] = []
        hashed: Dict[Any, Any] = {}
        while not self.accept("}"):
            if self.peek()[0] == "eof":
                break
            if self.peek()[0] == "name" and self.peek(1)[1] == "=":
                key = self.next()[1]
                self.next()
                hashed[key] = self.expr()
            elif self.peek()[1] == "[":
                self.next()
                key = self.expr()
                self.accept("]")
                self.accept("=")
                if isinstance(key, float) and key.is_integer():
                    key = int(key)
                hashed[key] = self.expr()
            else:
                arr.append(self.expr())
            if not (self.accept(",") or self.accept(";")):
                self.accept("}")
                break
        if arr and not hashed:
            return arr
        for idx, v in enumerate(arr):
            hashed[idx + 1] = v
        return hashed


def _arith(op: str, a: Any, b: Any) -> Any:
    if not isinstance(a, (int, float)) or not isinstance(b, (int, float)):
        return None
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    if op == "*":
        return a * b
    if op == "/":
        return a / b
    if op == "%":
        return a % b
    if op == "^":
        return a ** b
    return None


def _index(v: Any, k: Any) -> Any:
    if isinstance(v, dict):
        return v.get(k)
    if isinstance(v, list) and isinstance(k, float) and k.is_integer() and 1 <= k <= len(v):
        return v[int(k) - 1]
    return None


def read_module(path: Path, module_name: str) -> Dict[str, Any]:
    """Reads `<module_name>.Key = expr` assignments and `local NAME = expr` constants."""
    tokens = tokenize(path.read_text(encoding="utf-8"))
    env: Dict[str, Any] = {}
    module: Dict[str, Any] = {}
    env[module_name] = module
    p = Parser(tokens, env)
    while p.peek()[0] != "eof":
        kind, val = p.peek()
        if val == "local" and kind == "name":
            p.next()
            if p.peek()[1] == "function":
                continue
            name = p.next()[1]
            if p.peek()[1] == ":":  # local x: Type = ...
                p.next()
                p.skip_type()
            if p.accept("="):
                if name == module_name:
                    continue  # `local Economy = {}`: keep the module dict
                start = p.i
                try:
                    env[name] = p.expr()
                except Exception:
                    p.i = start + 1
            continue
        if kind == "name" and val == module_name and p.peek(1)[1] == "." and p.peek(3)[1] == "=":
            p.next()
            p.next()
            key = p.next()[1]
            p.next()
            module[key] = p.expr()
            continue
        p.next()
    return env


def read_cows(path: Path) -> Dict[str, Any]:
    """Returns {"growth": float, "tiers": [{"tier", "id", "name", "famous"}]}."""
    env = read_module(path, "Cows")
    rows = env.get("list") or []
    tiers = []
    for i, row in enumerate(rows):
        tiers.append({"tier": i + 1, "id": row[0], "name": row[1], "famous": bool(row[2])})
    return {"growth": env.get("MILK_GROWTH"), "tiers": tiers}


def load_all(config_dir: Path) -> Dict[str, Any]:
    economy = read_module(config_dir / "Economy.luau", "Economy")["Economy"]
    upgrades = read_module(config_dir / "Upgrades.luau", "Upgrades")["Upgrades"]
    events = read_module(config_dir / "Events.luau", "Events")["Events"]
    cows = read_cows(config_dir / "Cows.luau")
    pets = read_module(config_dir / "Pets.luau", "Pets")["Pets"]
    eggs = read_module(config_dir / "Eggs.luau", "Eggs")["Eggs"]
    index_rewards = read_module(config_dir / "IndexRewards.luau", "IndexRewards")["IndexRewards"]
    up_by_id = {u["id"]: u for u in upgrades["List"]}
    return {
        "Economy": economy,
        "Upgrades": up_by_id,
        "Events": events,
        "Cows": cows,
        "Pets": pets,
        "Eggs": eggs,
        "IndexRewards": index_rewards,
    }


if __name__ == "__main__":
    import json
    import sys

    root = Path(__file__).resolve().parent.parent / "src" / "shared" / "Config"
    print(json.dumps(load_all(Path(sys.argv[1]) if len(sys.argv) > 1 else root), indent=1, default=str))
