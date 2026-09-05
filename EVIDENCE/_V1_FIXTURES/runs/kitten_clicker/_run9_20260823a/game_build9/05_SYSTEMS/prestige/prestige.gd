# prestige.gd — LOGIQUE PURE (category system, allowed_deps [economy, collection]).
# Calcule l'etat post-prestige : remise a ZERO du compteur `ronrons`, increment d'un
# indicateur de bonus PERMANENT (`prestige_count`), et pause de production (`prod_paused`)
# qui rend le maillon META_LOOP `resets` compatible avec le maillon ADVANTAGE. Proprietaire
# unique de l'indicateur de bonus permanent. Ne lit ni rendu ni input.
extends RefCounted

# --- parametres de gameplay ISOLES (garde-fou (d)) --------------------------------
const PRESTIGE_THRESHOLD: int = 1   # ronrons minimum requis pour un prestige
const COOLDOWN_FRAMES: int = 45     # trames de production suspendue juste apres le prestige

static func bonus(state: Dictionary) -> int:
	return int(state["prestige_count"])

# Multiplicateur de production PERMANENT gagne par le prestige : 1 + bonus. Le premier
# prestige double la production (c'est l'AVANTAGE mesurable de la meta-boucle).
static func production_multiplier(state: Dictionary) -> int:
	return 1 + bonus(state)

# Un prestige est-il possible ? Il faut avoir accumule au moins le seuil.
static func can_prestige(state: Dictionary) -> bool:
	return float(state["ronrons"]) >= float(PRESTIGE_THRESHOLD)

# Applique le prestige : ronrons -> 0, bonus +1 (STRICTEMENT croissant), production
# suspendue COOLDOWN_FRAMES trames. Les chatons adoptes sont CONSERVES (ils portent la
# production qui reprend apres la pause). Rend true si applique.
static func prestige(state: Dictionary) -> bool:
	if not can_prestige(state):
		return false
	state["ronrons"] = 0.0
	state["prestige_count"] = bonus(state) + 1
	state["prod_paused"] = COOLDOWN_FRAMES
	return true
