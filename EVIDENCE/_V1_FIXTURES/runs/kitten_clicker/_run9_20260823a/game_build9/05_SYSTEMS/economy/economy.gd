# economy.gd — LOGIQUE PURE (category system, allowed_deps []).
# Detient l'UNIQUE compteur `ronrons` et applique : le gain d'un clic, l'accrual passif
# d'un montant fourni par le tick, et la depense d'un cout. Croissance monotone pour un
# gain positif. Ne connait NI scene, NI noeud, NI Input, NI rendu (garde-fou (c)).
# DETERMINISME (garde-fou (b)) : aucune source d'alea, aucune horloge — le tick de
# production avance d'un montant fourni par l'appelant, jamais d'un `delta` temps.
extends RefCounted

# --- parametres de gameplay ISOLES (garde-fou (d)) --------------------------------
const BASE_CLICK: int = 10          # valeur de base d'un clic pelote (avant amelioration)
const PASSIVE_UNIT: float = 0.5     # ronrons produits par point de taux et par trame

# Etat canonique du jeu. economy en est le proprietaire d'initialisation (patron
# run8 `CostCurve.initial_state`) : chaque cle est mutee par son systeme proprietaire.
static func initial_state() -> Dictionary:
	return {
		"ronrons": 0.0,          # economy (proprietaire)
		"upgrade_level": 0,      # upgrades
		"adopted": [],           # collection : noms de chatons adoptes
		"prestige_count": 0,     # prestige : indicateur de bonus permanent
		"prod_paused": 0,        # trames de pause de production apres un prestige
	}

# Gain de base d'un clic, AVANT tout multiplicateur d'amelioration (compose ailleurs).
static func base_click() -> int:
	return BASE_CLICK

# Applique un gain (clic ou production). Monotone : un montant negatif est ignore, le
# compteur ne recule jamais par un gain (seule une depense le fait baisser).
static func add(state: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	state["ronrons"] = float(state["ronrons"]) + amount

# Depense un cout : reussit et retranche si le solde suffit, echoue sinon (jamais de
# solde negatif). STRICT : le solde doit etre >= cout (jamais un > qui interdirait
# d'acheter avec exactement le montant).
static func can_afford(state: Dictionary, cost: int) -> bool:
	return float(state["ronrons"]) >= float(cost)

static func spend(state: Dictionary, cost: int) -> bool:
	if not can_afford(state, cost):
		return false
	state["ronrons"] = float(state["ronrons"]) - float(cost)
	return true

# Total AFFICHABLE (entier plancher) — la logique interne reste en flottant pour un
# accrual fin, l'ecran ne montre que des ronrons entiers.
static func total(state: Dictionary) -> int:
	return int(floor(float(state["ronrons"])))

# TICK DE PRODUCTION. Pendant la pause post-prestige (`prod_paused` > 0), aucune
# production : la pause est consommee d'une trame. Sinon, accrual = taux x multiplicateur
# x unite. C'est ce mecanisme qui rend le maillon META_LOOP `resets` compatible avec le
# maillon ADVANTAGE : juste apres un prestige la production est suspendue (le compteur
# reste a 0), puis elle reprend (le compteur remonte au-dela du premier clic).
static func production_tick(state: Dictionary, rate: float, multiplier: float) -> void:
	if int(state["prod_paused"]) > 0:
		state["prod_paused"] = int(state["prod_paused"]) - 1
		return
	if rate <= 0.0:
		return
	add(state, rate * multiplier * PASSIVE_UNIT)
