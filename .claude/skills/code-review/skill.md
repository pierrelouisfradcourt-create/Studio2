---
name: code-review
description: Revue code avant merge.
---
1. git diff main...HEAD dans le worktree.
2. Pas de unwrap() injustifié, panic!() prod, magic numbers.
3. Couverture tests sur nouveaux cas limites.
4. cargo test / pytest.
Verdict : [APPROUVER] / [CHANGER] / [BLOQUER]
