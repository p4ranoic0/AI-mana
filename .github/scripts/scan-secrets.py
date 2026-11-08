#!/usr/bin/env python3
"""Fails when a directory contains something that looks like a real credential.

Used by the public export and by CI. Test fixtures use unsigned JWTs and short fake values, which never match.

    scan-secrets.py <dir>     scan text files under <dir>; exit 1 and list matches
    scan-secrets.py --self-test
"""
import re
import sys
from pathlib import Path

PATTERNS = [
    ("signed JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{20,}")),
    ("API key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}")),
    # Session fields as Claude Code, Codex and OAuth responses serialize them, also split across lines.
    ("stored token", re.compile(
        r'"(?:refresh_?token|access_?token|id_?token|client_?secret|refreshToken|accessToken|idToken|clientSecret)"'
        r'\s*:\s*"([^"\s]{20,})"', re.IGNORECASE)),
]
# Obviously synthetic values in tests and docs, and string interpolations (`${…}`, `\(…)`) built at test time.
SYNTHETIC = re.compile(r"fake|example|dummy|abcdefghijklmnop|^\$\{|^\\\(", re.IGNORECASE)
SKIP_DIRS = {".git", ".build", ".dd", "build", "DerivedData", ".gradle", "node_modules", ".superpowers"}


def findings(text):
    for name, pattern in PATTERNS:
        for match in pattern.finditer(text):
            value = match.group(match.lastindex or 0)
            if SYNTHETIC.search(value) or value.endswith("."):   # unsigned JWT ("alg":"none") or a fake
                continue
            yield name, match.group(0)[:40]


def scan(root):
    hits = []
    for path in Path(root).rglob("*"):
        if not path.is_file() or SKIP_DIRS.intersection(path.parts) or path.resolve() == Path(__file__).resolve():
            continue   # this file spells its own test secrets
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue   # binary or unreadable: not a text secret
        hits += [(path, name, sample) for name, sample in findings(text)]
    return hits


def self_test():
    secret = "Zq8vR2mN5xT1kL9pW3cY7bH4jF6dG0sA"
    must_match = [
        '{"refresh_token": "%s"}' % secret,
        '{"refreshToken": "%s"}' % secret,
        '{"refresh_token":\n   "%s"}' % secret,
        '{"accessToken" : "%s"}' % secret,
        '{"clientSecret":"%s"}' % secret,
        'key = "sk-%s"' % secret,
        'sk-ant-%s' % secret,
        "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.%s" % secret,
    ]
    must_not_match = [
        '{"refreshToken": "fake-claude-refresh"}',
        '{"access_token": "eyJhbGciOiAibm9uZSJ9.eyJleHAiOiA0MTAyNDQ0ODAwfQ."}',
        '{"refresh_token": "R"}',
        '{"refresh_token": "abcdefghijklmnopqrstuvwxyz123"}',
        'let token = "sk-fake"',
        '{"access_token":"${jwt(Instant.now().minusSeconds(60))}"}',
        '{"access_token":"\\(makeToken(expiresIn: 3600))"}',
    ]
    failed = [s for s in must_match if not any(findings(s))] + [s for s in must_not_match if any(findings(s))]
    for sample in failed:
        print("self-test failed on:", sample.replace("\n", "\\n"), file=sys.stderr)
    return 1 if failed else 0


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    hits = scan(argv[1])
    for path, name, sample in hits:
        print(f"Possible secret ({name}) in {path}: {sample}…", file=sys.stderr)
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
