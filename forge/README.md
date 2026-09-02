# forge — oracle gate (PROUVER + FORCER)

`forge_gate(project)` resolves the project's deterministic oracle from
`oracles.json`, runs it, captures raw output under `lab/forge_evidence/`, and
returns an HMAC-signed verdict. `claim_verdict` is always `NO_CLAIM_ALLOWED`.
A non-green oracle (red, missing config, or unrunnable binary) yields
`ok=False` — callers must not proceed.

Add a project by adding an entry to `oracles.json`:
`"<project>": {"cwd": "<repo-relative dir>", "command": [<argv>]}`.

This deliberately does NOT touch `scripts/studio_meta.py`. Replacing the global
ELO gate with this per-project gate is a separate, Pierre-gated change.
