# v2_bindings_gamepad_coverage.test.gd — ligne bindings.gamepad_coverage, F78/F113.
# COUVERTURE MANETTE de reference : toute intention atteignable au clavier possede AU
# MOINS UNE liaison manette. La question ne se pose que parce que la table est enumerable.
#
# VOLET HUMAIN NON TRANCHE ICI : qu'une personne trouve seule les quatre gestes est un
# constat humain (F113), remonte en fog HumanGate.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")


func run(h) -> void:
	h.eq(Bindings.intentions_sans_manette().size(), 0,
		"bindings.manette: 0 intention atteignable au clavier sans liaison manette")
	h.eq(Bindings.intentions_de_jeu_sans_manette().size(), 0,
		"bindings.manette: 0 intention de jeu injouable a la manette")
	h.eq(Bindings.INTENTIONS_DE_JEU.size(), 6, "bindings.manette: six intentions de jeu declarees")

	# Chaque intention de jeu est atteignable sur les TROIS peripheriques ou explicitement
	# non declaree — jamais silencieusement absente.
	var sans_clavier: int = 0
	var sans_manette: int = 0
	for i in Bindings.INTENTIONS_DE_JEU:
		if Bindings.liaisons(i, Bindings.CLAVIER).is_empty():
			sans_clavier += 1
		if Bindings.liaisons(i, Bindings.MANETTE).is_empty():
			sans_manette += 1
	h.eq(sans_clavier, 0, "bindings.manette: chaque intention de jeu a une liaison clavier")
	h.eq(sans_manette, 0, "bindings.manette: chaque intention de jeu a une liaison manette")

	# LES QUATRE GESTES dont la decouvrabilite sera evaluee par une personne.
	h.eq(Bindings.GESTES_DECOUVRABLES.size(), 4, "bindings.manette: quatre gestes declares")
	var gestes_sans_manette: int = 0
	for g in Bindings.GESTES_DECOUVRABLES:
		if Bindings.liaisons(g, Bindings.MANETTE).is_empty():
			gestes_sans_manette += 1
	h.eq(gestes_sans_manette, 0, "bindings.manette: les quatre gestes ont une liaison manette")

	# LES BOUTONS sont DEUX A DEUX DIFFERENTS pour les quatre gestes : deux gestes sur un
	# meme bouton seraient indiscernables a la main.
	var boutons: Array = []
	var doublons: int = 0
	for g in Bindings.GESTES_DECOUVRABLES:
		var b: int = Bindings.liaisons(g, Bindings.MANETTE)[0]
		if boutons.has(b):
			doublons += 1
		boutons.append(b)
	h.eq(doublons, 0, "bindings.manette: quatre boutons deux a deux differents")
	h.eq(Bindings.liaisons(Intents.Intention.DASH, Bindings.MANETTE).size(), 1,
		"bindings.manette: le dash a exactement une liaison manette")
