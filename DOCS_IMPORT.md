# `docs/` — IMPORT SÉLECTIF · EXÉCUTION

*2026-09-02 · copie **verbatim depuis `58095ba9`**, aucun contenu réécrit.
**V1 non modifié.** `docs/` est un **support de Forge**, pas une nouvelle station du Studio.*

---

## Une correction de mesure avant la copie

Mon chiffre précédent — *« 59 cités / 56 présents »* — venait d'un grep sur `scripts/forge` en V1,
avec un motif qui ramassait des points de fin de phrase. Refait sur **le paquet V2, qui est
désormais l'autorité** :

```
cités par forge/ (contrats · .py · .mjs)  : 46
présents au HEAD 58095ba9                 : 44
absents du HEAD                           :  2
```

*Et une erreur que j'ai failli publier : mon premier passage a rendu **« 0 présent au HEAD »**.
Cause — la commande `git cat-file` tournait avec `cwd = Studio`, qui **est un dépôt git depuis le
`git init` d'il y a une heure**, et dans lequel `58095ba9` n'existe pas. La mesure interrogeait le
mauvais dépôt. Refaite depuis V1.*

## Les 2 absents — classés, non inventés

| fichier | en `mandatory_read` ? | classement |
|---|---|---|
| `docs/ARCHI.md` | **non** | **UNKNOWN** — cité, absent du HEAD canonique. Non copié, **non remplacé par un document ressemblant** |
| `docs/forge/RUN2_PROTOCOLE_V1_PROPOSED.md` | **non** | **UNKNOWN** — idem |

> Aucun des deux n'est une **précondition dure**. S'ils l'avaient été, la ligne aurait été
> `BLOCKED`, pas « on cherche l'équivalent le plus proche ».

## La copie

```
44 fichiers · 764 Ko · verbatim depuis 58095ba9
docs/{forge, adr, audit, fvl, superpowers/{plans,specs}}
```
**149 fichiers existent en V1 ; 44 sont entrés.** Le critère est la citation par du code ou un
contrat actif — pas le dossier.

**Aucun `.md` n'a été réécrit.** Les chemins historiques qu'ils contiennent (`lab/…`, `games/…`,
`scripts/forge/…`) restent tels quels : *une preuve documentaire doit rester fidèle à ce qu'elle
constatait*. Seules les références **exécutables** ont été migrées, et elles l'ont été à l'étape 9.

---

## Le contrôle qui motivait tout ça

```
mandatory_read des 27 contrats portant une référence fichier
   références totales : 69
   PRÉSENTES en V2    : 69
   ABSENTES           :  0
```

**La « précondition dure » de chaque contrat d'agent est désormais satisfaite en V2.**

*Deuxième correction, du même lot : ma première passe annonçait 1 absente, `forge/skill.md`. C'était
un faux positif — mon motif tronquait `.claude/skills/forge/skill.md`, qui **existe** en V2 (36 Ko,
copié avec les 31 skills). Le fichier était là ; c'est ma mesure qui coupait le chemin.*

---

## État

```
Git                    CLOSED        6/6, .gitignore-preuve restauré
agent_policy           OUT_OF_SCOPE  0 appelant
workflow_lab           OUT_OF_SCOPE  garde conservée
games/                 CLOSED        0 chemin actif
docs/                  CLOSED        44 importés · 2 UNKNOWN nommés
mandatory_read         PASS          69 / 69
Blender / Godot        CONDITIONNEL  jamais préconditions globales
asset_lessons          NOT_YET_PRODUCED
Pacman 00_CHARTER · 09_WIREMAP   UNAVAILABLE @ 58095ba9
V1                     INTACT        58095ba9
Q2 / R8                UNTOUCHED
```

```
status_by_surface:
  docs_cites:          TESTED   # 46 depuis le paquet V2
  docs_au_head:        TESTED   # 44 copiés verbatim
  docs_absents:        UNKNOWN  # 2, aucun en mandatory_read, non inventés
  md_non_reecrits:     TESTED   # contenu verbatim
  mandatory_read:      TESTED   # 69/69 résolues
  suite_complete:      BLOCKED  # dernier gros morceau franchi — la validation V2 peut être décidée
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
