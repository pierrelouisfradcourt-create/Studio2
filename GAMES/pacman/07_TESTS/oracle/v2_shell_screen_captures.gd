# v2_shell_screen_captures.gd — ligne shell.screen_captures, capacite F112.
# PROVENANCE, PAS PREUVE. Volet MACHINE : une capture de CHAQUE ecran est produite et
# les captures different deux a deux.
# CONTRAINTE DE PLATEFORME CONNUE ET NON CONTOURNEE : une capture Godot exige une
# FENETRE GPU REELLE ; en headless, la texture est NULLE. Ce volet vaut donc
# NOT_MEASURED MOTIVE — jamais un vert, jamais un fichier vide.
# Volet HUMAIN : ce qu'une personne voit et comprend n'est tranche par aucun oracle.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")


func run(h) -> void:
	var contexte: Dictionary = {"selection": 0, "reglages": {}, "releve": {}}
	# SANS FENETRE GPU : le constat est NOT_MEASURED, motive, jamais un vert.
	var captures: Array = ShellView.captures(null)
	h.eq(captures.size(), ShellView.ECRANS.size(), "shell.captures: un constat par ecran")
	var mesurees: int = 0
	var motives: int = 0
	for c in captures:
		if c["mesure"]:
			mesurees += 1
		if String(c["raison"]) != "":
			motives += 1
	h.eq(mesurees, 0, "shell.captures: en headless, aucune capture n'est mesuree")
	h.eq(motives, captures.size(), "shell.captures: chaque non-mesure est MOTIVEE")
	h.eq(String(captures[0]["raison"]), ShellView.RAISON_HEADLESS, "shell.captures: la raison est nommee")

	# CE QUI EST MESURABLE SANS FENETRE : les six ecrans different deux a deux.
	h.eq(ShellView.paires_identiques(contexte), 0, "shell.captures: 0 paire d'ecrans identiques")
	var signatures: Array = []
	for e in ShellView.ecrans(contexte):
		signatures.append(ShellView.signature(e))
	h.eq(signatures.size(), 6, "shell.captures: six signatures produites")
	var vides: int = 0
	for s in signatures:
		if String(s).strip_edges() == "":
			vides += 1
	h.eq(vides, 0, "shell.captures: aucun ecran vide")
	h.eq(ShellView.ECRANS.has(App.Etat.FIN), true, "shell.captures: l'ecran de fin est couvert")
	h.eq(ShellView.ECRANS.has(App.Etat.PARTIE), true, "shell.captures: l'ecran de partie est couvert")
