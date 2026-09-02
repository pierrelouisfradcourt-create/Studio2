---
name: audit-daily
description: Audit quotidien hygiene/vérité/sécurité — orphelins, acceptance TBD, refs obsolètes, supply chain.
---

# /audit-daily

Audit de santé studio en trois axes : hygiène du ledger, cohérence des ancres, sécurité basique.

---

## Axe 1 — Hygiène ledger

Lire `lab/chains/IMPROVEMENT_LEDGER.yaml`.

Signaler :

| Anomalie | Condition |
|---|---|
| Acceptance TBD | `acceptance: TBD` sur un IMP OPEN |
| IMP OPEN sans files | `files: []` sur un IMP OPEN |
| Bloqueur fantôme | `blocked_by` référence un IMP CLOSED |
| IMP OPEN > 30 jours | `opened_session` < date - 30j et status OPEN |

Afficher la liste des anomalies trouvées. Si 0 → "Ledger propre".

---

## Axe 2 — Cohérence vérité (MEMORY.md)

Lire `studio/openclaw-workspace/MEMORY.md`.

Vérifier :

| Check | Condition d'alerte |
|---|---|
| ELO hybride | Mention d'un ELO négatif ou incohérent vs TICK log |
| Ancres Lichess | `last run` > 7 jours → "reanchor recommandé" |
| Dataset actif | ACTIVE_DATASET.txt pointe vers un fichier inexistant |
| IMP refs | Toute mention d'un IMP comme OPEN alors qu'il est CLOSED dans le ledger |

Afficher les incohérences. Si 0 → "MEMORY.md cohérente".

---

## Axe 3 — Sécurité basique

Vérifier :

```bash
# HMAC_KEY absente du repo
grep -r "HMAC_KEY\s*=" --include="*.py" --include="*.yaml" --include="*.json" . \
  --exclude-dir=.git | grep -v "os.environ\|getenv\|\.env"
```

- Résultat non vide → **ALERTE** : valeur de clé potentiellement exposée dans le repo
- Résultat vide → "Pas de clé en clair détectée"

Vérifier aussi :
- `~/.openclaw/.env` non commité (`.gitignore` le couvre ?)
- Aucun `*.pem`, `*.key`, `*.secret` dans le repo

---

## Rapport

```
AUDIT DAILY — <date>
─────────────────────────────────────────────
Hygiène ledger  : <N anomalies | propre>
  <liste si anomalies>
Vérité MEMORY   : <N incohérences | cohérente>
  <liste si incohérences>
Sécurité        : <ALERTE | OK>
  <détail si alerte>
─────────────────────────────────────────────
Action requise : <liste | aucune>
```

Écrire le rapport dans `lab/reports/audit_daily_<date>.md`.

---

## Hard rules

- Lecture seule — aucune modification pendant l'audit.
- Alerte sécurité → escalader Pierre immédiatement, ne pas continuer.
- Ne jamais modifier les zones FORBIDDEN lors de l'audit.
