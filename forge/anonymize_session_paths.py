# -*- coding: utf-8 -*-
"""Anonymisation CIBLÉE de la clé `session_file` dans les artefacts Observer.

PRINCIPE RATIFIÉ (Pierre, 2026-08-18) : ne pas supprimer une information parce qu'elle est
PERSONNELLE si elle constitue une PREUVE ; anonymiser ce qui est personnel ET sans fonction
probatoire.

`session_file` pointe vers un transcript de session Claude sur le poste. Il ne prouve RIEN de
la mesure : il est écrit (`observer/adapters/transcripts.py:313`, `observer/prompt.py:355`) et
JAMAIS RELU — 0 lecture de la clé dans tout `scripts/` hors tests, et le seul consommateur de
ces artefacts (`runtime_inventory_oracle.py:36`) en extrait les `capability_role`. Aucune ligne
qui porte un chemin n'est signée (mesuré : 0 sur 1848 pour tetris, 0 sur 4152 pour breakout_v2).

CE QUI N'EST PAS TOUCHÉ, et c'est la moitié de l'intention de ce module :
  · `proof_chain.binaire.path` et `command_executee[]` — ils documentent QUEL binaire et
    QUELLE commande ont produit la mesure. Traçabilité PROBANTE, conservée par arbitrage.
  · `.source.path`, `.payload.path`, `.payload.result_excerpt` — hors périmètre de ce lot.
  · `product_oracle.check_solo_ai_session(session_file=...)` — HOMONYME sans rapport : un
    paramètre de fonction désignant un fichier de preuve à EXÉCUTER.

On DÉRACINE la référence, on ne l'efface pas : le projet et l'identifiant de session
survivent, seul le nom de compte et la disposition du disque disparaissent.
"""
from __future__ import annotations

import re
from typing import Any

CLAUDE_HOME_PLACEHOLDER = "<CLAUDE_HOME>"

# `C:\Users\<compte>\.claude` ou `C:/Users/<compte>/.claude`, séparateurs mêlés tolérés
# (les artefacts JSONL portent les deux formes selon le producteur).
# PIEGE MESURE : dans une classe de caracteres, un antislash UNIQUE devant `/` ECHAPPE la
# barre oblique — l'antislash lui-meme n'entre jamais dans la classe. `[^\/]` ne veut donc
# PAS dire « ni antislash ni slash », il veut dire « pas slash ». Premiere redaction : la
# classe ne matchait que la forme POSIX, en SILENCE, et les artefacts Windows passaient au
# travers. Il en faut DEUX. Construit par code de caractere pour qu'aucun echappement
# traverse (heredoc, shell, source) ne puisse le deformer a nouveau.
_B = chr(92) * 2                      # deux antislashs DANS le motif = un antislash matche
_PREFIXE = re.compile(
    "[A-Za-z]:[" + _B + "/]+Users[" + _B + "/]+[^" + _B + "/]+[" + _B + "/]+"
    + chr(92) + ".claude", re.IGNORECASE)


SESSION_FILE_KEY = "session_file"


def anonymize_session_file_value(value: Any) -> Any:
    """Déracine un chemin de transcript. Non-str, ou sans préfixe personnel => INCHANGÉ.

    IDEMPOTENT : rejouer l'anonymisation ne réabîme rien — le placeholder ne correspond pas
    au motif. Une opération de masse sur des artefacts doit pouvoir être relancée sans risque.
    """
    if not isinstance(value, str):
        return value
    return _PREFIXE.sub(CLAUDE_HOME_PLACEHOLDER, value)


def anonymize_obj(obj: Any) -> Any:
    """Copie PROFONDE où SEULE la valeur des clés `session_file` est déracinée.

    Fonction PURE : l'objet d'origine n'est jamais muté — l'appelant peut comparer avant/après
    et prouver que rien d'autre n'a bougé. Un parcours qui remplacerait par balayage de texte
    emporterait `proof_chain` et `command_executee` ; c'est pourquoi il est piloté par la CLÉ.
    """
    if isinstance(obj, dict):
        return {k: (anonymize_session_file_value(v) if k == SESSION_FILE_KEY
                    else anonymize_obj(v))
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [anonymize_obj(v) for v in obj]
    return obj

# --- EXTENSION 2026-08-20 (GO Pierre) : du CHAMP au PREFIXE --------------------------------
#
# MESURE QUI L'IMPOSE. Sur les 21 artefacts Observer exposés au sommet de `master`,
# `session_file` ne porte que **120** des ~16 750 occurrences structurées. La clé DOMINANTE
# est `path` (11 414), puis `sources_read` (4 207) et `sources_lues_pour_rien` (867). Piloter
# par la clé aurait donc couvert **moins de 1 %** — et aurait raté la 10e clé qu'un futur
# producteur inventera. Le périmètre par clé n'était pas trop prudent : il était FAUX pour
# cette population.
#
# POURQUOI UN BALAYAGE PAR VALEUR EST SÛR ICI, alors que le docstring du module le refusait.
# La crainte était d'emporter `proof_chain.binaire.path` et `command_executee[]`. Elle est
# fondée : il est désormais PROUVÉ que les rédiger invalide le reçu signé
# (`verify_receipt` : True -> False sur `bomberman_3d-proof3-20260817`). Mais `_PREFIXE`
# EXIGE le segment `.claude`. Le binaire Godot — `C:\Users\<compte>\Desktop\Godot_...exe`
# — ne le contient pas : il est hors d'atteinte du motif, QUELLE QUE SOIT la clé qui le
# porte. La sûreté vient du MOTIF, jamais du nom de clé.
#
# Ce n'est pas une intention : `test_anonymize_session_paths.py` falsifie les deux sens —
# les trois formes de transcript sont déracinées, les deux chemins probants restent intacts.


def anonymize_deep(obj: Any) -> Any:
    """Copie PROFONDE où TOUTE valeur chaîne portant le préfixe est déracinée.

    Fonction PURE, comme `anonymize_obj` : l'objet d'origine n'est jamais muté, donc
    l'appelant peut comparer avant/après et prouver que rien d'autre n'a bougé.

    IDEMPOTENTE : `<CLAUDE_HOME>` ne correspond pas au motif, une seconde passe ne fait rien.

    Les clés, elles, ne sont PAS réécrites : une clé qui porterait un chemin serait une
    anomalie de schéma à traiter en amont, pas à masquer ici.
    """
    if isinstance(obj, dict):
        return {k: anonymize_deep(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [anonymize_deep(v) for v in obj]
    return anonymize_poste(obj)


def anonymize_text(texte: Any) -> Any:
    """Pour les artefacts NON STRUCTURÉS — Markdown, YAML — qui n'ont aucune clé.

    7 des 21 artefacts Observer sont dans ce cas et concentrent l'essentiel du volume
    (`_selftest/SELFTEST.md` : 2694 occurrences, `RECONSTRUCTION.md` : ~840 chacun). Sans
    ce point d'entrée, l'extension laisserait passer la moitié du problème en silence.
    Même motif, même placeholder : une seule autorité pour ce qu'est un chemin personnel.
    """
    return anonymize_poste(texte)

# --- EXTENSION 2 (GO Pierre 2026-08-20) : temporaire + colonne `ls -l` ---------------------
#
# INSTRUCTION DU RESIDU. Apres l'extension 1, il restait 801 occurrences du compte dans les
# 21 artefacts Observer. Instruites : ~301 chemins de repertoire TEMPORAIRE, ~59 colonnes
# PROPRIETAIRE d'une sortie `ls -l` capturee, ~7 divers — et 107-116 `Desktop\\Godot_...exe`,
# PROBANTS, qui restent hors d'atteinte de ces motifs (aucun ne les decrit).
#
# MESURE QUI AUTORISE LA REDACTION : sur 440 lignes portant une enveloppe `hmac` dans le
# corpus Observer, ZERO ne porte le compte. Rediger ces residus ne detruit donc aucune preuve
# verifiable — contrairement a `proof_chain.binaire.path`, dont la redaction fait passer
# `verify_receipt` de True a False.
#
# AUCUN MOTIF NE NOMME LE COMPTE. Une garde qui s'ancre sur l'instance qu'elle protege ne
# protege que ce poste, et publie le nom qu'elle interdit (lecon ratifiee le 2026-08-20).
# On decrit donc la FORME : l'emplacement standard des temporaires, et le bloc de permissions
# qui ouvre une ligne de `ls -l`.

TEMP_PLACEHOLDER = "<TEMP>"
USER_PLACEHOLDER = "<user>"

# `<disque>:\Users\<compte>\AppData\Local\Temp` — separateurs meles tolérés, comme
# `_PREFIXE`. Le SUFFIXE survit (projet, session, `scratchpad`, fichier) : c'est lui qui rend
# les clefs `id` et `vers` utilisables comme clefs de correlation. Deux sessions distinctes
# restent distinctes apres deracinement — verifie par test, pas suppose.
_PREFIXE_TEMP = re.compile(
    "[A-Za-z]:[" + _B + "/]+Users[" + _B + "/]+[^" + _B + "/]+[" + _B + "/]+"
    + "AppData[" + _B + "/]+Local[" + _B + "/]+Temp", re.IGNORECASE)

# Ligne de `ls -l` : `drwxr-xr-x 1 <compte> 197121 0 Aug  3 08:47 .`
# On s'ancre sur le BLOC DE PERMISSIONS (10 caracteres d'un alphabet tres restreint) suivi du
# compteur de liens — pas sur un nom. Ce qui est remplace est la SEULE colonne proprietaire ;
# permissions, taille, date et nom de fichier survivent, donc l'observation reste lisible.
# Pas d'ancrage `^` : ces sorties vivent DANS des chaines JSON ou les retours a la ligne sont
# echappes, un `^` ne matcherait donc jamais sur le texte brut du fichier.
_LISTING = re.compile(
    r"(?P<av>[-dlbcps][-rwxsStT]{9}[+.@]?\s+\d+\s+)"
    r"(?P<user>[^\s\\\"]+)"
    # Le `\s+` FINAL a ete RETIRE : ces sorties sont capturees en EXTRAITS tronques a une
    # longueur fixe, la ligne peut donc se terminer juste apres le groupe proprietaire.
    # Exiger une espace derriere laissait passer les lignes coupees — defaut trouve sur le
    # corpus REEL (`-rw-r--r-- 1 <compte> 197"}`), pas en theorie.
    r"(?P<ap>\s+\d+)")


def anonymize_poste(value: Any) -> Any:
    """Toutes les traces de POSTE en une passe : `.claude`, temporaires, colonne `ls -l`.

    PURE et IDEMPOTENTE. Aucun placeholder ne correspond a un motif : rejouer ne reabime rien.
    Ce qui n'est PAS decrit ici n'est jamais touche — en particulier `Desktop\\Godot_...exe`,
    dont la conservation est une CONTRAINTE de signature et non un arbitrage.
    """
    if not isinstance(value, str):
        return value
    v = _PREFIXE.sub(CLAUDE_HOME_PLACEHOLDER, value)
    v = _PREFIXE_TEMP.sub(TEMP_PLACEHOLDER, v)
    return _LISTING.sub(lambda m: m.group("av") + USER_PLACEHOLDER + m.group("ap"), v)
