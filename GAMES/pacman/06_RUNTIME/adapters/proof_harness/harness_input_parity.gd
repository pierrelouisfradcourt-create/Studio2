# harness_input_parity.gd — PARITE CLAVIER / MANETTE (ligne harness.keyboard_gamepad_parity).
#
# Pour CHAQUE intention de jeu, deux executions sont rejouees sur une fenetre DECLAREE —
# l'une pilotee par les entrees clavier, l'autre par les entrees manette — et les traces
# d'etat sont comparees TICK PAR TICK.
#
# Mesure depuis l'ETAT EXPOSE (game_state/observable.gd) : le harnais ne rappelle jamais
# les systemes qu'il mesure pour recalculer ce qu'il devrait constater. La table qui rend
# la parite possible appartient a input_bindings.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")

# Fenetre DECLAREE de comparaison, en ticks.
const FENETRE: int = 40
const GRAINE: int = 4


# Trace des releves exposes obtenue en emettant `intention` a chaque tick de la fenetre.
static func trace(carte, intention: int, graine: int, fenetre: int) -> Array:
	var s = State.initial(carte, graine)
	var suite: Array = [Observable.projeter(s)]
	for _t in range(fenetre):
		if s.statut != State.Statut.EN_COURS:
			break
		s = Loop.step_intentions(s, [intention])["etat"]
		suite.append(Observable.projeter(s))
	return suite


# Nombre de champs divergents entre deux traces, compare tick par tick.
static func divergences(a: Array, b: Array) -> int:
	if a.size() != b.size():
		return 1
	var n: int = 0
	for i in range(a.size()):
		for cle in Observable.CLES:
			if a[i].get(cle) != b[i].get(cle):
				n += 1
	return n


# Une intention de jeu est-elle atteignable sur les DEUX peripheriques ? Sans cette
# garde, comparer deux traces ne prouverait rien quand l'un des deux chemins n'existe pas.
static func atteignable_sur_les_deux(intention: int) -> bool:
	var clavier: Array = Bindings.liaisons(intention, Bindings.CLAVIER)
	var manette: Array = Bindings.liaisons(intention, Bindings.MANETTE)
	if clavier.is_empty() or manette.is_empty():
		return false
	return (InputAdapter.intention_de_touche(clavier[0]) == intention
		and InputAdapter.intention_de_bouton(manette[0]) == intention)


# Constat par intention de jeu : l'intention obtenue par la touche, celle obtenue par le
# bouton, et le nombre de divergences entre les deux traces.
static func constats(carte) -> Array:
	var sortie: Array = []
	for intention in Bindings.INTENTIONS_DE_JEU:
		var clavier: Array = Bindings.liaisons(intention, Bindings.CLAVIER)
		var manette: Array = Bindings.liaisons(intention, Bindings.MANETTE)
		var par_touche: int = Intents.Intention.AUCUNE
		var par_bouton: int = Intents.Intention.AUCUNE
		if not clavier.is_empty():
			par_touche = InputAdapter.intention_de_touche(clavier[0])
		if not manette.is_empty():
			par_bouton = InputAdapter.intention_de_bouton(manette[0])
		var d: int = divergences(
			trace(carte, par_touche, GRAINE, FENETRE),
			trace(carte, par_bouton, GRAINE, FENETRE))
		sortie.append({
			"intention": intention,
			"nom": Intents.nom(intention),
			"par_touche": par_touche,
			"par_bouton": par_bouton,
			"atteignable": atteignable_sur_les_deux(intention),
			"divergences": d,
		})
	return sortie


# CONTRE-EPREUVE : le comparateur DETECTE bien une difference quand elle existe — sans
# quoi « 0 divergence » ne prouverait rien.
static func divergences_de_controle(carte) -> int:
	return divergences(
		trace(carte, Intents.Intention.GAUCHE, GRAINE, FENETRE),
		trace(carte, Intents.Intention.DROITE, GRAINE, FENETRE))


static func mesurer(carte) -> Dictionary:
	var liste: Array = constats(carte)
	var divergentes: int = 0
	var non_atteignables: int = 0
	for c in liste:
		if c["divergences"] != 0:
			divergentes += 1
		if not c["atteignable"]:
			non_atteignables += 1
	return {
		"intentions": liste.size(),
		"intentions_divergentes": divergentes,
		"intentions_non_atteignables": non_atteignables,
		"divergences_de_controle": divergences_de_controle(carte),
		"fenetre": FENETRE,
		"constats": liste,
	}
