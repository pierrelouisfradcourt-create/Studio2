"""Verification HMAC des enveloppes signees de la Forge — P4 SIGNED = verifie.

PROBLEME CORRIGE (invariant INV-2) : avant ce module, `proof=SIGNED` dans
Observer signifiait uniquement « le champ `hmac` existe dans l'enregistrement
source » — aucune verification cryptographique n'etait faite nulle part dans
`scripts/observer/` (0 `import hmac`). Un enregistrement FORGE (au sens
falsifie) avec un `hmac` bidon etait donc etiquete SIGNED au meme titre qu'un
enregistrement authentique.

REUTILISE, NE DUPLIQUE PAS : toutes les enveloppes signees cote Forge suivent
la MEME convention (verifiee par lecture directe des 6 points d'emission —
`forge/verdict.py::_sign_mapping`/`_verify_mapping` [verdicts + recus
d'oracle], `forge/audit.py::sign_audit_record`/`verify_audit_line` [audit de
spawn], `forge/context_manifest.py`, `forge/reasoning_observability.py`,
`forge/tool_observability.py`) : un dict plat portant un champ `hmac`, signe
par `hmac.new(key, json.dumps(corps_sans_hmac, sort_keys=True), sha256)`. Ce
module appelle `forge.verdict._verify_mapping` — la fonction de verification
EXISTANTE — au lieu de re-implementer HMAC ici. C'est l'UNIQUE point d'appel
de cette regle depuis Observer ; aucun autre fichier ne doit reimporter
`forge.verdict` pour ce besoin.

`scripts/` est deja sur `sys.path` (voir le prefixe `sys.path.insert` en tete
de chaque entree Observer : `cli.py`, `selftest.py`, ...), donc `import forge`
fonctionne depuis ce contexte sans manipulation supplementaire ici.

Observer reste LECTURE SEULE et NE GENERE JAMAIS DE CLE : si
`scripts/forge/.forge_key` est absent, aucun enregistrement n'est classe
VERIFIED — l'absence de cle est un etat honnete (UNVERIFIABLE), jamais un OK
implicite ni un INVALID (mentir dans les deux sens serait pire que ne rien
affirmer).
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Optional

LOG = logging.getLogger("observer.signature")

# --------------------------------------------------------------------------- #
# Verdicts de verification — vocabulaire minimal ajoute a celui d'events.py
# --------------------------------------------------------------------------- #

VERIFIED = "VERIFIED"          # hmac present, cle lisible, signature valide sur le corps
INVALID = "INVALID"            # hmac present, cle lisible, signature NE correspond PAS
UNVERIFIABLE = "UNVERIFIABLE"  # hmac present mais cle absente/illisible -> ne peut pas trancher
ABSENT = "ABSENT"              # pas de champ hmac du tout -> pas une enveloppe signee

_STATUSES = (VERIFIED, INVALID, UNVERIFIABLE, ABSENT)

# --------------------------------------------------------------------------- #
# Import paresseux et non fatal de la regle Forge existante
# --------------------------------------------------------------------------- #

_forge_verify_mapping = None
_forge_read_key = None
_forge_default_key_file: Optional[Path] = None
_import_error: Optional[str] = None

try:
    from forge.verdict import _verify_mapping as _forge_verify_mapping  # type: ignore
    from forge.verdict import _read_key as _forge_read_key  # type: ignore
    from forge.verdict import DEFAULT_KEY_FILE as _forge_default_key_file  # type: ignore
except Exception as exc:  # pragma: no cover — garde de disponibilite, jamais fatal
    _import_error = f"{type(exc).__name__}: {exc}"
    LOG.warning(
        "forge.verdict indisponible depuis Observer (%s) — toute enveloppe "
        "signee sera classee UNVERIFIABLE, jamais VERIFIED ni INVALID par "
        "defaut.",
        _import_error,
    )


def rule_available() -> bool:
    """Vrai ssi la regle de verification Forge a pu etre importee."""
    return _forge_verify_mapping is not None and _forge_read_key is not None


def key_available(key_file: Optional[Path] = None) -> bool:
    """Vrai ssi la cle de signature Forge est lisible depuis ce contexte.

    Ne genere JAMAIS de cle (c'est le chemin de VERIFICATION) — meme garantie
    que `forge.verdict._verify_mapping` : une cle absente reste absente."""
    if not rule_available():
        return False
    kf = key_file or _forge_default_key_file
    try:
        return _forge_read_key(kf) is not None
    except OSError as exc:
        LOG.warning("lecture de la cle de signature impossible (%s): %s", kf, exc)
        return False


def verify_envelope(record: Any, key_file: Optional[Path] = None) -> str:
    """Classe une enveloppe signee Forge : VERIFIED | INVALID | UNVERIFIABLE | ABSENT.

    `record` est le dict brut TEL QUE LU sur disque (le champ `hmac` doit
    encore y figurer). Ne devine jamais : un `hmac` absent est ABSENT (pas une
    enveloppe signee), jamais assimile a INVALID.
    """
    if not isinstance(record, dict):
        return ABSENT
    sig = record.get("hmac")
    if not sig or not isinstance(sig, str):
        return ABSENT

    if not rule_available():
        return UNVERIFIABLE
    if not key_available(key_file):
        return UNVERIFIABLE

    body = {k: v for k, v in record.items() if k != "hmac"}
    try:
        ok = _forge_verify_mapping(body, sig, key_file)
    except Exception:  # noqa: BLE001 — une verification qui explose n'est pas un succes
        LOG.exception(
            "verification HMAC en echec inattendu — enregistrement classe INVALID"
        )
        return INVALID
    return VERIFIED if ok else INVALID
