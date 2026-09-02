#!/usr/bin/env python
"""qwen_spec.py — worker Qwen : demande gameplay (langage naturel) -> spec d'asset.

COUCHE PRODUCTEUR, moitie amont. Qwen ne fabrique pas de geometrie et ne juge rien : il
TRADUIT une intention de jeu en parametres. C'est un travail de TRANSFORMATION, pas de
RAPPEL — le registre ou ce modele est mesure fiable (memoire studio : Qwen echoue au
rappel, ses citations derivent meme a temperature 0 ; il tient la transformation).

Appel HTTP direct a LM Studio (OpenAI-compatible, port 1234), stdlib seulement. Volontaire :
un worker qui ne fonctionnerait qu'a travers un outil de session ne serait pas une capacite
de la Forge — il doit tourner depuis un script, sans agent.

GARDES (le modele ne decide jamais seul) :
  * enumerations FERMEES : un archetype ou une categorie hors liste est un REJET, jamais
    une valeur de repli silencieuse ;
  * `consumer` non vide obligatoire — pas d'asset sans consommateur ;
  * dimensions bornees : un modele qui propose une caisse de 40 m est refuse ;
  * temperature 0 et JSON strict ;
  * UNE tentative de reparation ciblee (doctrine REPAIR_LOOP : reparer le champ fautif
    coute moins qu'un nouveau prompt), puis echec explicite.

Ce module N'ECRIT AUCUN FICHIER et ne dispatche rien : il rend une spec ou une erreur.

Usage :
  python -m scripts.forge.asset_producer.qwen_spec "<demande gameplay>" [--model M] [--json]
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]

LM_STUDIO_URL = "http://localhost:1234/v1/chat/completions"
DEFAULT_MODEL = "qwen2.5-14b-instruct"
TIMEOUT_S = 180

# Enumerations FERMEES — memes listes que build_asset.py et kb-validate.mjs.
ARCHETYPES = ["crate", "door", "platform", "barrel", "pillar", "button", "chest"]
CATEGORIES = [
    "character", "monster", "weapon", "armor", "building", "tree", "rock", "prop",
    "robot", "cyborg", "drone", "vehicle", "machine", "neon",
    "door", "chest", "button", "platform", "trap", "decoration",
    "creature", "animal", "absurd",
]
# Bornes de plausibilite, en metres. Un humain fait ~1,8.
DIM_MIN, DIM_MAX = 0.05, 20.0

SYSTEM = (
    "Tu convertis une demande de gameplay en specification d'asset 3D, en JSON STRICT.\n"
    "Reponds UNIQUEMENT par un objet JSON, sans texte avant ni apres, sans balise de code.\n"
    "Champs obligatoires :\n"
    '  asset_id   : identifiant court en snake_case, prefixe "gen_"\n'
    f"  archetype  : STRICTEMENT un de {ARCHETYPES}\n"
    f"  category   : STRICTEMENT un de {CATEGORIES}\n"
    "  style      : chaine courte (ex. lowpoly)\n"
    "  size       : objet {w, d, h} en METRES (un humain fait 1.8)\n"
    "  color      : [r, g, b, a] entre 0 et 1\n"
    "  variants   : liste des etats MUTUELLEMENT EXCLUSIFS livres ensemble, [] sinon\n"
    "  consumer   : liste NON VIDE — a quoi sert cet asset dans le jeu\n"
    "N'invente aucun archetype hors de la liste. Si la demande n'y correspond pas, "
    "choisis le plus proche et explique-le dans consumer."
)


class QwenError(RuntimeError):
    """Echec d'appel ou de conformite. Jamais une spec de repli silencieuse."""


def call_lm_studio(prompt: str, *, model: str = DEFAULT_MODEL, system: str = SYSTEM,
                   temperature: float = 0.0, max_tokens: int = 600) -> str:
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": prompt}],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }).encode("utf-8")
    req = urllib.request.Request(LM_STUDIO_URL, data=payload,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as r:
            data = json.loads(r.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise QwenError(f"LM Studio injoignable ({LM_STUDIO_URL}) : {exc}") from exc
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError) as exc:
        raise QwenError(f"reponse LM Studio inexploitable : {str(data)[:200]}") from exc


def extract_json(texte: str) -> dict[str, Any]:
    """Isole l'objet JSON. Qwen encadre parfois sa reponse ; on ne reecrit rien d'autre."""
    t = texte.strip()
    if t.startswith("```"):
        t = t.split("```")[1] if "```" in t[3:] else t.lstrip("`")
        if t.startswith("json"):
            t = t[4:]
    debut, fin = t.find("{"), t.rfind("}")
    if debut == -1 or fin == -1:
        raise QwenError(f"aucun objet JSON dans la reponse : {texte[:200]}")
    try:
        return json.loads(t[debut:fin + 1])
    except json.JSONDecodeError as exc:
        raise QwenError(f"JSON invalide : {exc} — {t[debut:fin + 1][:200]}") from exc


def validate_spec(spec: dict) -> list[str]:
    """Regle des 3 etats : absent = oubli (rejet), declare vide = decision assumee."""
    err: list[str] = []
    if not isinstance(spec, dict):
        return ["la spec n'est pas un objet"]

    aid = spec.get("asset_id")
    if not isinstance(aid, str) or not aid.strip():
        err.append("asset_id absent ou vide")
    elif not aid.replace("_", "").replace("-", "").isalnum():
        err.append(f"asset_id non conforme (snake_case attendu) : {aid!r}")

    if spec.get("archetype") not in ARCHETYPES:
        err.append(f"archetype hors liste fermee : {spec.get('archetype')!r} (attendu {ARCHETYPES})")
    if spec.get("category") not in CATEGORIES:
        err.append(f"category hors liste fermee : {spec.get('category')!r}")

    size = spec.get("size")
    if not isinstance(size, dict):
        err.append("size absent ou mal type")
    else:
        for k in ("w", "d", "h"):
            v = size.get(k)
            if not isinstance(v, (int, float)):
                err.append(f"size.{k} absent ou non numerique")
            elif not (DIM_MIN <= float(v) <= DIM_MAX):
                err.append(f"size.{k}={v} hors bornes [{DIM_MIN}, {DIM_MAX}] metres")

    cons = spec.get("consumer")
    if not isinstance(cons, list) or not cons or not all(isinstance(c, str) and c.strip() for c in cons):
        err.append("consumer doit etre une liste NON VIDE — pas d'asset sans consommateur")

    if "variants" not in spec:
        err.append("variants absent (declarer [] si l'asset n'a pas d'etats exclusifs)")
    elif not isinstance(spec["variants"], list):
        err.append("variants doit etre une liste")

    col = spec.get("color")
    if col is not None and (not isinstance(col, list) or len(col) != 4
                            or not all(isinstance(c, (int, float)) and 0 <= c <= 1 for c in col)):
        err.append("color doit etre [r,g,b,a] entre 0 et 1")

    return err


def generate_spec(demande: str, *, model: str = DEFAULT_MODEL,
                  repair: bool = True) -> tuple[dict[str, Any], dict[str, Any]]:
    """Rend (spec_valide, trace). Leve QwenError si la spec reste non conforme.

    La trace nomme le modele, le nombre de tentatives et les erreurs corrigees : sans
    elle, on ne saurait pas si Qwen a produit une spec juste ou une spec reparee.
    """
    trace: dict[str, Any] = {"model": model, "attempts": 0, "repaired": False,
                             "errors_first_pass": [], "raw_first": ""}

    brut = call_lm_studio(demande, model=model)
    trace["attempts"] = 1
    trace["raw_first"] = brut[:500]
    spec = extract_json(brut)
    errs = validate_spec(spec)
    trace["errors_first_pass"] = errs

    if errs and repair:
        # Reparation CIBLEE : on renvoie les erreurs, pas un nouveau prompt generique.
        rappel = (f"{demande}\n\nTa reponse precedente etait invalide :\n"
                  + "\n".join(f"- {e}" for e in errs)
                  + "\nCorrige UNIQUEMENT ces points et renvoie le JSON complet.")
        brut2 = call_lm_studio(rappel, model=model)
        trace["attempts"] = 2
        spec2 = extract_json(brut2)
        errs2 = validate_spec(spec2)
        if not errs2:
            trace["repaired"] = True
            return spec2, trace
        raise QwenError("spec non conforme apres reparation : " + " | ".join(errs2))

    if errs:
        raise QwenError("spec non conforme : " + " | ".join(errs))
    return spec, trace


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("demande", help="demande gameplay en langage naturel")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--out", default=None, help="ecrit la spec dans ce fichier")
    ns = ap.parse_args(argv)

    try:
        spec, trace = generate_spec(ns.demande, model=ns.model)
    except QwenError as exc:
        print(f"QWEN_SPEC_FAIL: {exc}", file=sys.stderr)
        return 2

    if ns.out:
        Path(ns.out).write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n",
                                encoding="utf-8")

    if ns.json:
        print(json.dumps({"spec": spec, "trace": trace}, indent=2, ensure_ascii=False))
    else:
        print(f"modele        {trace['model']}  (tentatives={trace['attempts']}, "
              f"reparee={trace['repaired']})")
        print(json.dumps(spec, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
