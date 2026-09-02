---
path: src/**/*.rs
---
- Pas de unwrap() sans // SAFETY: <raison>
- Pas de panic!() en production
- Pas de magic numbers : constantes nommées
- Fonctions > 100 lignes → découper
- Zobrist hash pour répétition (pas to_fen())
