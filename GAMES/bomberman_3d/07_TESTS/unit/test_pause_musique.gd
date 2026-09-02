# MODIFICATION RATIFIEE PAR GO EXPLICITE DE PIERRE, 2026-08-12 (P8 navigation).
#
# Motif : la nouvelle machine d'etats rend le parcours `MENU -> EN_JEU` obsolete — une partie
# se lance desormais depuis SELECTION_CARTE. Ce fichier lancait la partie par l'ancien chemin ;
# sans mise a jour la suite serait rouge pour une raison qui n'est pas un defaut.
# Deux modifications, memes regles que test_app_state : un `sel` intermediaire insere, et la
# cible d'abandon passee de MENU a SELECTION_CARTE. AUCUNE assertion retiree, une ajoutee.
#
# PORTEE DE CETTE RATIFICATION : elle couvre CETTE modification, rendue necessaire par P8.
# Elle NE VAUT PAS autorisation generale de modifier `07_TESTS/**`. Toute autre modification
# de ce repertoire exige un nouveau GO.

# test_pause_musique.gd — ecran de PAUSE, piste MUSICALE, et OBJECTIF lisible.
#
# Le volet le plus important est celui de la pause : reprendre ne doit PAS reconstruire la
# partie. Une pause qui detruit ce qu'elle protege est pire que pas de pause.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Shell = preload("res://06_RUNTIME/adapters/ui_shell/ui_shell.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")


func run(h) -> void:
	# ---------- PAUSE : entree, sortie, et non-destruction ----------
	# MIS A JOUR (P8, GO Pierre 2026-08-12) : lancer une partie passe desormais par l'ecran de
	# SELECTION DE CARTE. Une etape de plus sur le chemin, AUCUNE assertion retiree.
	var a: Dictionary = App.initial(3)
	var sel: Dictionary = App.appliquer(a, App.VALIDER, P.EN_COURS)
	h.eq(int(sel["ecran"]), App.SELECTION_CARTE, "pause: le menu ouvre d'abord le choix de carte")
	var jeu: Dictionary = App.appliquer(sel, App.VALIDER, P.EN_COURS)
	h.eq(int(jeu["ecran"]), App.EN_JEU, "pause: on part bien d'une partie en cours")

	var p: Dictionary = App.appliquer(jeu, App.BASCULER_PAUSE, P.EN_COURS)
	h.eq(int(p["ecran"]), App.PAUSE, "pause: la touche met en pause")
	h.eq(int(p["carte"]), int(jeu["carte"]), "pause: la carte selectionnee est conservee")

	var reprise: Dictionary = App.appliquer(p, App.BASCULER_PAUSE, P.EN_COURS)
	h.eq(int(reprise["ecran"]), App.EN_JEU, "pause: la MEME touche reprend")
	h.ok(not App.doit_demarrer(p, reprise),
		"pause: REPRENDRE NE REDEMARRE PAS — la partie survit a la pause")
	h.ok(not App.doit_demarrer(p, App.appliquer(p, App.VALIDER, P.EN_COURS)),
		"pause: reprendre par VALIDER ne redemarre pas non plus")

	# CONTROLE POSITIF de l'assertion precedente : depuis le MENU, entrer en jeu DOIT
	# demarrer. Sans ce controle, `doit_demarrer` pourrait rendre false partout.
	h.ok(App.doit_demarrer(a, jeu), "pause: depuis le menu, entrer en jeu DEMARRE bien")
	h.ok(App.doit_demarrer(App.appliquer(jeu, App.RIEN, P.GAGNE),
		App.appliquer(App.appliquer(jeu, App.RIEN, P.GAGNE), App.VALIDER, P.GAGNE)),
		"pause: depuis le resultat, rejouer DEMARRE bien")

	# abandon — MIS A JOUR (P8) : ECHAP remonte d'UN niveau, donc vers le choix de carte.
	# La propriete testee est la meme : depuis la pause, on peut ABANDONNER la partie.
	var menu: Dictionary = App.appliquer(p, App.RETOUR_MENU, P.EN_COURS)
	h.eq(int(menu["ecran"]), App.SELECTION_CARTE, "pause: on peut abandonner vers le choix de carte")

	# la FIN prime sur la pause
	var finie: Dictionary = App.appliquer(jeu, App.BASCULER_PAUSE, P.GAGNE)
	h.eq(int(finie["ecran"]), App.RESULTAT,
		"pause: une partie TERMINEE va au resultat, elle ne se met pas en pause")

	# la pause n'existe pas hors du jeu
	h.eq(int(App.appliquer(a, App.BASCULER_PAUSE, P.EN_COURS)["ecran"]), App.MENU,
		"pause: la touche ne fait rien depuis le menu")
	var res: Dictionary = App.appliquer(jeu, App.RIEN, P.PERDU)
	h.eq(int(App.appliquer(res, App.BASCULER_PAUSE, P.PERDU)["ecran"]), App.RESULTAT,
		"pause: la touche ne fait rien depuis le resultat")

	# purete
	var avant: int = int(p["ecran"])
	App.appliquer(p, App.RETOUR_MENU, P.EN_COURS)
	h.eq(int(p["ecran"]), avant, "pause: appliquer ne mute jamais son entree")

	# ---------- MUSIQUE : une PISTE, pas une suite d'effets ----------
	h.gt(Audio.MOTIF.size(), 3, "musique: le motif porte plusieurs notes")
	var hauteurs := {}
	for i in range(Audio.MOTIF.size()):
		hauteurs[Audio.hauteur_note(i)] = true
	h.gt(hauteurs.size(), 2, "musique: le motif emploie plusieurs hauteurs distinctes")
	h.eq(Audio.hauteur_note(0), Audio.MUSIQUE_TONIQUE_HZ, "musique: la note 0 est la tonique")
	h.eq(Audio.hauteur_note(Audio.MOTIF.size()), Audio.hauteur_note(0),
		"musique: le motif BOUCLE (l'index se replie)")
	h.gt(Audio.hauteur_note(1), Audio.hauteur_note(0), "musique: le second degre monte")

	# La piste doit rester SOUS les effets : une musique qui couvre l'alerte de danger est
	# un defaut de conception sonore, pas un reglage.
	const CuesLoc = preload("res://05_SYSTEMS/sound_cues/sound_cues.gd")
	for c in CuesLoc.CUES:
		h.gt(float(CuesLoc.descripteur(String(c))["gain"]), Audio.MUSIQUE_GAIN,
			"musique: l'effet '%s' est plus fort que la piste" % str(c))

	# ---------- OBJECTIF : une phrase, pas un compteur ----------
	h.gt(Shell.objectif(null).length(), 20, "objectif: lisible meme sans partie")
	var s = Fx.etat(Fx.desc_vide(), 1, 2)
	var o1: String = Shell.objectif(s)
	h.gt(o1.length(), 20, "objectif: une phrase en cours de partie")
	h.ok(o1.find("Adversaires") >= 0, "objectif: il NOMME ce qui reste a faire")
	h.ok(o1.find("Fermeture") >= 0, "objectif: il annonce l'echeance de mort subite")
	s.ticks = P.MORT_SUBITE_DEBUT
	var o2: String = Shell.objectif(s)
	h.ok(o2.find("MORT SUBITE") >= 0, "objectif: il CHANGE quand l'arene se referme")
	h.ok(o1 != o2, "objectif: les deux phases ne se lisent pas pareil")
