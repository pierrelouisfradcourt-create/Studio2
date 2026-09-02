# v4_p4_progression_visible.gd — CAUSE RACINE P4 : PROGRESSION INCONNUE.
#
# DEFAUT MESURE (playtest Pierre) : `hud.gd` n'affichait ni le numero de carte ni le total
# du catalogue. Le joueur ne savait ni combien de cartes existent, ni ou il en est, ni ce
# que debloque la sortie. Les trois informations etaient DEJA disponibles — le catalogue
# les porte (03_WORLD/rules/level_catalog/catalog.json) et `level_progression` porte la
# regle — mais aucune n'atteignait l'ecran.
#
# CE QUE CETTE PREUVE MESURE : que les trois informations sont affichees, et que chaque
# nombre affiche est EGAL a sa source (etat pour la carte courante, catalogue pour le
# total). L'egalite est verifiee par RELECTURE du texte, pas par relecture humaine.
extends RefCounted

const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Content = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")

const CHEMIN_RUNTIME := "res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd"
const BUDGET: int = 400


func _texte(chemin: String) -> String:
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


func run(h) -> void:
	var total: int = Shell.nb_niveaux()
	h.gt(total, 1, "v4.p4: le catalogue porte plusieurs cartes")
	h.eq(total, Content.nb_niveaux(), "v4.p4: le total vient du catalogue, source unique")

	# --- LES TROIS INFORMATIONS EXISTENT ET SONT LISIBLES. ---
	h.eq(Hud.texte_carte(1, 2), "CARTE 1/2", "v4.p4: la carte courante et le total sont ecrits")
	h.eq(Hud.texte_objectif(244), "OBJECTIF VIDER 244 PASTILLES", "v4.p4: l'objectif est chiffre")
	h.eq(Hud.texte_sortie(1, 2), "SORTIE : PROCHAINE CARTE", "v4.p4: la sortie debloque la carte suivante")
	h.eq(Hud.texte_sortie(2, 2), "SORTIE : FIN DE PARTIE", "v4.p4: sur la derniere, elle mene a la fin")
	h.ok(Hud.texte_sortie(1, 2) != Hud.texte_sortie(2, 2), "v4.p4: les deux issues sont distinctes")

	# LA RELECTURE : chiffre a l'ecran == chiffre de la source, verifie mecaniquement.
	h.eq(Hud.relire(Hud.texte_carte(3, 7), Hud.ETIQUETTE_CARTE), 3, "v4.p4: la carte courante se relit")
	h.eq(Hud.relire_total(Hud.texte_carte(3, 7)), 7, "v4.p4: le total se relit")
	h.eq(Hud.relire_total("SCORE 12"), -1, "v4.p4: sans etiquette, -1 — jamais 0")
	h.eq(Hud.relire_total("CARTE 3"), -1, "v4.p4: sans separateur, -1 — jamais un total invente")
	h.eq(Hud.relire_total("CARTE 3/"), -1, "v4.p4: un total absent apres le separateur donne -1")
	h.ok(Hud.relire_total(Hud.texte_carte(3, 7)) != 8, "v4.p4: la relecture detecte l'ecart")

	# --- LA LIGNE COMPLETE PORTE LES TROIS, DEPUIS LE SEUL RELEVE OBSERVABLE. ---
	var sess: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	var partie = sess["partie"]
	var releve: Dictionary = Observable.projeter(partie)
	var ligne: String = Hud.ligne_progression(releve, total)
	h.eq(Hud.relire(ligne, Hud.ETIQUETTE_CARTE), int(releve["niveau"]),
		"v4.p4: la carte affichee est celle de l'etat")
	h.eq(Hud.relire_total(ligne), total, "v4.p4: le total affiche est celui du catalogue")
	h.eq(Hud.relire(ligne, Hud.ETIQUETTE_OBJECTIF), int(releve["restantes"]),
		"v4.p4: l'objectif affiche est le nombre reel de pastilles restantes")
	h.ok(ligne.contains(Hud.SORTIE_SUIVANTE), "v4.p4: sur la premiere carte, une suivante est annoncee")

	# --- L'AFFICHAGE SUIT L'ETAT SUR UNE PARTIE REELLEMENT JOUEE. ---
	var jeu = Bot.jouer_depuis_graine(Shell.carte(0), 1, BUDGET, Shell.cadence(0))["etat"]
	var suivi: Dictionary = Observable.projeter(jeu)
	var ligne2: String = Hud.ligne_progression(suivi, total)
	h.eq(Hud.relire(ligne2, Hud.ETIQUETTE_OBJECTIF), jeu.total_pose - jeu.consommees,
		"v4.p4: l'objectif suit la consommation reelle")
	h.eq(Hud.relire(ligne2, Hud.ETIQUETTE_CARTE), jeu.niveau, "v4.p4: la carte suit l'etat")
	h.lt(jeu.total_pose - jeu.consommees, jeu.total_pose, "v4.p4: des pastilles ont bien ete mangees")

	# --- LA DERNIERE CARTE ANNONCE LA FIN, et c'est la MEME regle que la logique pure. ---
	var dernier: Dictionary = Observable.projeter(partie)
	dernier["niveau"] = total
	h.ok(Hud.ligne_progression(dernier, total).contains(Hud.SORTIE_FIN),
		"v4.p4: la derniere carte annonce la fin de partie")
	partie.niveau = total
	h.eq(Progression.suite(partie, total), Progression.SUITE_CATALOGUE_TERMINE,
		"v4.p4: et la logique pure dit la meme chose")
	partie.niveau = 1
	h.eq(Progression.suite(partie, total), Progression.SUITE_NIVEAU_SUIVANT,
		"v4.p4: sur une carte intermediaire, elle annonce la suivante")
	h.eq(Progression.dernier_niveau(total, total), true, "v4.p4: la regle du dernier niveau est nette")
	h.eq(Progression.dernier_niveau(total - 1, total), false, "v4.p4: et la precedente ne l'est pas")

	# --- LE RUNTIME L'AFFICHE REELLEMENT. Une ligne que personne ne pose n'existe pas. ---
	var source: String = _texte(CHEMIN_RUNTIME)
	h.ok(source.find("Hud.ligne_progression(releve, Shell.nb_niveaux())") >= 0,
		"v4.p4: la boucle du runtime pose la ligne de progression avec le total du catalogue")

	# --- AJOUTER UNE CARTE RESTE A 0 FICHIER DE LOGIQUE : le total est LU, jamais ecrit. ---
	var logique := FileAccess.open("res://05_SYSTEMS/level_progression/level_progression.gd", FileAccess.READ)
	h.ok(logique != null, "v4.p4: le module de progression est lisible")
	var t: String = logique.get_as_text()
	logique.close()
	h.eq(t.find("catalog.json"), -1, "v4.p4: la logique pure n'ouvre aucun catalogue")
	h.eq(t.find("maze_classic"), -1, "v4.p4: et ne nomme aucune carte")
