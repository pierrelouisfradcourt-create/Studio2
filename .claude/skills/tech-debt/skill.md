---
name: tech-debt
description: Audit dette technique.
---
grep -rn "unwrap()\|panic!\|TODO\|FIXME" src/ ml/
cargo clippy -- -D warnings
Fonctions Rust > 100 lignes, GDScript > 50 lignes.
Rapport : [CRITIQUE] / [ÉLEVÉ] / [BAS]
