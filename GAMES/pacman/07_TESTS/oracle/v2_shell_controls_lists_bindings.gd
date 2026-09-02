# v2_shell_controls_lists_bindings.gd — ligne shell.controls_lists_bindings, capacite F113.
# PROVENANCE, PAS PREUVE. Volet MACHINE : l'ecran Controles est produit par LECTURE de
# la table de liaisons (aucune chaine de touche recopiee dans ce fichier), et le nombre
# d'intentions affichees sans liaison manette vaut exactement 0.
# Volet HUMAIN, qu'aucun oracle ne tranche : qu'une personne execute les quatre gestes
# sans consigne est un CONSTAT HUMAIN — besoin remonte en fog HumanGate.
extends RefCounted

const Controles = preload("res://06_RUNTIME/adapters/shell_view/controls_screen.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")


func run(h) -> void:
	# VOLET MACHINE 1 : l'ecran LIT la table, il ne recopie aucune touche.
	var f := FileAccess.open("res://06_RUNTIME/adapters/shell_view/controls_screen.gd", FileAccess.READ)
	h.ok(f != null, "shell.liaisons: l'ecran est lisible")
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("KEY_"), false, "shell.liaisons: aucun code de touche recopie")
	h.eq(texte.contains("JOY_"), false, "shell.liaisons: aucun code de bouton recopie")
	h.eq(texte.contains("Bindings.liaisons"), true, "shell.liaisons: la table est lue")

	# VOLET MACHINE 2 : 0 intention affichee sans liaison manette.
	h.eq(Controles.intentions_affichees_sans_manette(), 0,
		"shell.liaisons: 0 intention affichee sans liaison manette")
	h.eq(Controles.gestes_absents_de_l_ecran(), 0, "shell.liaisons: les quatre gestes sont affiches")

	# Les lignes CITENT reellement les liaisons de la table.
	var ligne: String = Controles.ligne(Intents.Intention.DASH)
	var attendu: String = Controles.liaisons_lisibles(Intents.Intention.DASH, Bindings.MANETTE)
	h.eq(ligne.contains(attendu), true, "shell.liaisons: la ligne cite la liaison de la table")
	h.eq(ligne.contains(Bindings.MANETTE), true, "shell.liaisons: le peripherique est nomme")
	h.eq(Controles.liaisons_lisibles(Intents.Intention.AUCUNE, Bindings.CLAVIER), Controles.AUCUNE_LIAISON,
		"shell.liaisons: une intention sans liaison est marquee comme telle")
	h.eq(Controles.libelle(Intents.Intention.PAUSE), "Pause", "shell.liaisons: libelle lisible")
	h.eq(Controles.libelle(Intents.Intention.SELECTION_SUIVANTE), Intents.nom(Intents.Intention.SELECTION_SUIVANTE),
		"shell.liaisons: une intention sans libelle retombe sur son nom")

	# VOLET HUMAIN : non tranche ici. La ligne fournit le MATERIAU, pas le constat.
	h.eq(Bindings.GESTES_DECOUVRABLES.size(), 4, "shell.liaisons: quatre gestes a faire decouvrir")
