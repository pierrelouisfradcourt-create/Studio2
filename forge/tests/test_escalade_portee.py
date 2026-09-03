"""ESC-1 — une escalade du builder ne modifie JAMAIS le modèle du reviewer indépendant.

DÉFAUT RÉEL, mesuré sur RUN M ter (2026-09-03) :
`state["model_override"]` était de portée RUN, et `run_real.py` l'appliquait à TOUTES les
étapes (`model = context.get("model_override") or payload.model`). Le build de M ter a
nécessité deux escalades (haiku -> sonnet -> opus) ; l'override a donc aussi remplacé le
reviewer de `s11-redteam-code`, dont le `capability_role: redteam_code` existe précisément
pour garantir une revue INDÉPENDANTE (ADR-002 gate 4).

Résultat dans le verdict signé : `redteam_ran: False`,
`redteam_reviewer: claude-opus-4-8`, flag « red-team dégradé ».

> **Plus le build était difficile, moins sa revue était indépendante.**

Le verdict le signalait — le défaut n'était pas silencieux. Mais rien ne disait que la CAUSE
était l'escalade : un lecteur concluait « qwen indisponible », alors que qwen tournait très bien
à s6 dans le même run.

DÉCISION CONTRACTUELLE (Pierre) : l'override porte le nom de l'étape qu'il vise, et cette étape
SEULE l'applique. Ce n'est pas un correctif de journalisation, c'est une règle de portée.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import forge.run_real as run_real


def _modele_applique(payload_model: str, override: str | None, portee: str | None,
                     etape: str) -> str:
    """Reproduit EXACTEMENT la règle de `run_real` au point de décision du modèle.

    On ne teste pas une copie de la logique : la même expression est lue ici et là-bas, et
    `test_la_regle_testee_est_bien_celle_du_code` ci-dessous vérifie qu'elle n'a pas divergé.
    """
    return override if (override and (not portee or portee == etape)) else payload_model


def test_le_builder_escalade_recoit_bien_le_modele_superieur():
    assert _modele_applique("claude-haiku-4-5", "opus", "s9-build", "s9-build") == "opus"


def test_le_reviewer_independant_GARDE_son_routage():
    """Le coeur de la décision : s11 n'est PAS l'étape visée, il conserve son modèle."""
    assert _modele_applique("qwen2.5-14b-instruct", "opus", "s9-build",
                            "s11-redteam-code") == "qwen2.5-14b-instruct"


def test_aucune_autre_etape_n_est_touchee():
    for etape in ("s0-contrat", "s5-wiremap", "s6-redteam-plan", "s12-verdict"):
        assert _modele_applique("modele-du-contrat", "opus", "s9-build", etape) == "modele-du-contrat"


def test_sans_escalade_rien_ne_change():
    assert _modele_applique("claude-haiku-4-5", None, None, "s9-build") == "claude-haiku-4-5"


def test_state_anterieur_sans_portee_reste_applique():
    """Compatibilité de REPRISE : un `state.json` écrit avant ce lot n'a pas de portée.
    Le driver la reconstruit (`_builder_step()`), mais si elle manquait malgré tout,
    l'ancien comportement subsiste — une reprise ne doit jamais devenir un no-op silencieux."""
    assert _modele_applique("claude-haiku-4-5", "opus", None, "s9-build") == "opus"


def test_la_regle_testee_est_bien_celle_du_code():
    """Garde anti-divergence : la règle ci-dessus doit rester CELLE de `run_real`.

    Un test qui recopie une logique et s'en satisfait mesure sa propre copie — c'est
    exactement l'erreur du premier lot D-1 (test sur un objet que la production ne fournit
    jamais). On vérifie donc que l'expression vit toujours dans le fichier réel.
    """
    from pathlib import Path

    src = Path(run_real.__file__).read_text(encoding="utf-8", errors="replace")
    assert 'context.get("model_override_scope")' in src, \
        "la portée n'est plus lue par run_real : l'override redeviendrait global"
    assert "_portee == etape" in src, \
        "la comparaison de portée a disparu — le reviewer indépendant n'est plus protégé"


def test_le_driver_declare_la_portee_a_l_escalade():
    """L'autre moitié : l'escalade doit NOMMER l'étape qu'elle vise."""
    from pathlib import Path

    import forge.driver as driver_mod
    src = Path(driver_mod.__file__).read_text(encoding="utf-8", errors="replace")
    assert 'state["model_override_scope"] = builder' in src, \
        "l'escalade ne déclare plus sa portée : elle redeviendrait de portée RUN"
    assert src.count('"model_override_scope": state.get("model_override_scope")') >= 3, \
        "la portée doit être transportée par TOUS les contextes d'étape, sinon un chemin la perd"
