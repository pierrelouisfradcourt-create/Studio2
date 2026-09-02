# boot.gd — ligne core.boot. Amorce du produit : au lancement, l'etat initial declare est
# ATTEINT sans aucune intervention humaine, sans menu ni ecran de chargement intercale. La
# construction de l'etat est PURE (deleguee a State.initial), testable en headless. RefCounted.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")

# Nombre de gestes / d'ecrans intercales avant que la balle bouge : EXACTEMENT 0.
const GESTES_AVANT_DEMARRAGE: int = 0
const ECRANS_INTERCALES: int = 0

# Etat atteint immediatement au boot (deterministe pour une graine donnee). Statut EN_COURS.
static func etat_initial(seed_val: int) -> Object:
	return State.initial(seed_val)
