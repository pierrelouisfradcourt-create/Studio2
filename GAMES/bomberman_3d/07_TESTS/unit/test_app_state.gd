# test_app_state.gd — la boucle d'application ET la relance propre (core.restart).
#
# Modification ratifiee par GO explicite de Pierre, 2026-08-12 (P8 navigation).
#
# REGLE DE CETTE MODIFICATION, telle qu'elle a ete posee : AUCUNE assertion supprimee, AUCUNE
# assertion affaiblie. Les assertions qui decrivaient l'ancien comportement ont ete MISES A
# JOUR vers le nouveau (meme propriete, nouvelle cible), jamais retirees. Ce fichier est en
# zone protegee : sans ce GO, il n'aurait pas ete touche.
#
# CE QUE P8 CHANGE ICI, en une phrase : le MENU ne lance plus une partie, il OUVRE un ecran.
# Le choix de carte et le lancement ont demenage d'un cran plus bas (SELECTION_CARTE), donc
# tout chemin de test qui menait au jeu a desormais une etape de plus — et pas une de moins.
#
# `core.restart` exige : « apres une fin de partie, relance -> etat identique au premier
# demarrage (aucun residu) ». Ce fichier le prouve par COMPARAISON de deux etats neufs
# construits par le meme chemin, pas par inspection a l'oeil de quelques champs.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")
const Content = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Shell = preload("res://06_RUNTIME/adapters/ui_shell/ui_shell.gd")


func _empreinte(s) -> Array:
	var acteurs: Array = []
	for a in s.acteurs:
		acteurs.append([a["cellule"], a["vivant"], a["bombes_max"], a["rayon"],
			a["cooldown"], a["cd_restant"], a["bombes_actives"]])
	return [s.ticks, s.statut, s.graine, s.blocs_tombes, s.bombes.size(),
		s.flammes.size(), s.powerups.size(), s.morts.size(),
		s.arene.nb_destructibles(), acteurs]


func run(h) -> void:
	# ---------- etat initial ----------
	var a: Dictionary = App.initial(3)
	h.eq(int(a["ecran"]), App.MENU, "app: l'application demarre au MENU")
	h.eq(int(a["carte"]), 0, "app: la premiere carte est selectionnee")
	h.eq(int(a["issue"]), App.ISSUE_AUCUNE, "app: aucune issue au demarrage")
	h.eq(int(a["parties_jouees"]), 0, "app: aucune partie jouee au demarrage")
	h.eq(int(App.initial(0)["nb_cartes"]), 1, "app: un catalogue vide vaut quand meme 1 carte")
	h.eq(int(a["curseur_menu"]), App.MENU_JOUER, "app: le menu s'ouvre sur JOUER")
	h.eq(bool(a["quitter"]), false, "app: on ne quitte pas au demarrage")

	# ---------- choix de carte, cyclique ----------
	# MIS A JOUR (P8) : le cycle de carte vit desormais sur l'ecran SELECTION_CARTE. La
	# propriete testee est INCHANGEE — la selection avance et boucle sur le catalogue — seule
	# l'adresse de cet ecran a change.
	var sel0: Dictionary = App.appliquer(a, App.VALIDER, P.EN_COURS)
	h.eq(int(sel0["ecran"]), App.SELECTION_CARTE, "app: JOUER ouvre le choix de carte")
	var b: Dictionary = App.appliquer(sel0, App.CARTE_SUIVANTE, P.EN_COURS)
	h.eq(int(b["carte"]), 1, "app: carte suivante")
	b = App.appliquer(b, App.CARTE_SUIVANTE, P.EN_COURS)
	b = App.appliquer(b, App.CARTE_SUIVANTE, P.EN_COURS)
	h.eq(int(b["carte"]), 0, "app: la selection boucle sur le catalogue")
	h.eq(int(b["ecran"]), App.SELECTION_CARTE, "app: choisir une carte ne lance pas la partie")

	# ---------- lancement ----------
	var c: Dictionary = App.appliquer(b, App.VALIDER, P.EN_COURS)
	h.eq(int(c["ecran"]), App.EN_JEU, "app: VALIDER lance la partie")
	h.ok(App.doit_demarrer(b, c), "app: l'entree en jeu demande une partie NEUVE")
	h.ok(not App.doit_demarrer(c, c), "app: rester en jeu ne redemarre rien")

	# ---------- la partie ne se quitte QUE par les regles ----------
	var d: Dictionary = App.appliquer(c, App.VALIDER, P.EN_COURS)
	h.eq(int(d["ecran"]), App.EN_JEU, "app: aucune touche ne quitte une partie en cours")
	d = App.appliquer(c, App.RETOUR_MENU, P.EN_COURS)
	h.eq(int(d["ecran"]), App.EN_JEU, "app: RETOUR_MENU est sans effet pendant la partie")

	# ---------- fin de partie -> resultat ----------
	var e: Dictionary = App.appliquer(c, App.RIEN, P.GAGNE)
	h.eq(int(e["ecran"]), App.RESULTAT, "app: un statut terminal fait passer au RESULTAT")
	h.eq(int(e["issue"]), P.GAGNE, "app: l'issue est retenue")
	h.eq(int(e["parties_jouees"]), 1, "app: la partie est comptee")
	h.eq(App.libelle_issue(P.GAGNE), "VICTOIRE", "app: libelle de victoire")
	h.eq(App.libelle_issue(P.PERDU), "DEFAITE", "app: libelle de defaite")
	h.eq(App.libelle_issue(P.NUL), "MATCH NUL", "app: libelle de match nul")
	h.eq(App.libelle_issue(App.ISSUE_AUCUNE), "", "app: aucune issue -> aucun libelle")

	# ---------- rejouer ----------
	var f: Dictionary = App.appliquer(e, App.VALIDER, P.GAGNE)
	h.eq(int(f["ecran"]), App.EN_JEU, "app: REJOUER relance une partie")
	h.eq(int(f["issue"]), App.ISSUE_AUCUNE, "app: rejouer efface l'issue precedente")
	h.eq(int(f["carte"]), int(e["carte"]), "app: rejouer garde la MEME carte")
	h.ok(App.doit_demarrer(e, f), "app: rejouer demande une partie NEUVE")

	# ---------- retour menu ----------
	# MIS A JOUR (P8) : ECHAP remonte d'UN niveau, donc le resultat rend la main a l'ecran d'ou
	# la partie a ete lancee — pas a la racine. La propriete testee reste la meme : on QUITTE
	# la partie et le compteur lui SURVIT.
	var g: Dictionary = App.appliquer(e, App.RETOUR_MENU, P.GAGNE)
	h.eq(int(g["ecran"]), App.SELECTION_CARTE, "app: retour au choix de carte depuis le resultat")
	h.eq(int(g["parties_jouees"]), 1, "app: le compteur de parties SURVIT au retour menu")
	h.ok(App.doit_arreter(e, g), "app: ce retour ARRETE bien la partie (predicat generalise)")

	# ---------- action inconnue : sans effet, jamais un crash ----------
	# ---------- BOUCLE COMPLETE : MENU -> JEU -> PAUSE -> MENU -> JEU ----------
	# Le playtest a rapporte « pas de retour au menu ». La transition existait au niveau de
	# l'etat ; ce qui manquait etait (1) sa preuve, (2) l'ARRET reel de la partie cote
	# runtime, (3) son rappel a l'ecran. Ce volet couvre (1) et (2).
	#
	# MIS A JOUR (P8) : la boucle passe desormais par SELECTION_CARTE a l'aller comme au
	# retour. Toutes les assertions d'origine sont conservees ; leurs cibles suivent l'arbre
	# ratifie, et deux assertions s'ajoutent pour le cran intermediaire.
	var m0: Dictionary = App.initial(3)
	var s0: Dictionary = App.appliquer(m0, App.VALIDER, P.EN_COURS)
	h.eq(int(s0["ecran"]), App.SELECTION_CARTE, "boucle: MENU -> SELECTION_CARTE")
	h.ok(not App.doit_demarrer(m0, s0), "boucle: ouvrir le choix de carte ne demarre AUCUNE partie")
	var j0: Dictionary = App.appliquer(s0, App.VALIDER, P.EN_COURS)
	h.eq(int(j0["ecran"]), App.EN_JEU, "boucle: MENU -> JEU")
	h.ok(App.doit_demarrer(s0, j0), "boucle: l'entree en jeu demande une partie neuve")
	h.ok(not App.doit_arreter(m0, j0), "boucle: entrer en jeu n'arrete rien")
	var p0: Dictionary = App.appliquer(j0, App.BASCULER_PAUSE, P.EN_COURS)
	h.eq(int(p0["ecran"]), App.PAUSE, "boucle: JEU -> PAUSE")
	h.ok(not App.doit_arreter(j0, p0), "boucle: mettre en pause n'arrete PAS la partie")
	var m1: Dictionary = App.appliquer(p0, App.RETOUR_MENU, P.EN_COURS)
	h.eq(int(m1["ecran"]), App.SELECTION_CARTE, "boucle: PAUSE -> SELECTION_CARTE (abandon)")
	h.ok(App.doit_arreter(p0, m1), "boucle: le retour menu DETRUIT la partie en cours")
	var j1: Dictionary = App.appliquer(m1, App.VALIDER, P.EN_COURS)
	h.eq(int(j1["ecran"]), App.EN_JEU, "boucle: SELECTION_CARTE -> JEU, une seconde fois")
	h.ok(App.doit_demarrer(m1, j1), "boucle: la seconde partie est NEUVE, pas une reprise")
	# Ce qui SURVIT a une partie reste dans l'etat d'application.
	h.eq(int(j1["carte"]), int(m0["carte"]), "boucle: la carte choisie survit au retour menu")
	# Le retour menu depuis le RESULTAT arrete aussi la partie.
	var r0: Dictionary = App.appliquer(j1, App.RIEN, P.GAGNE)
	h.eq(int(r0["ecran"]), App.RESULTAT, "boucle: la fin de partie mene au resultat")
	var m2: Dictionary = App.appliquer(r0, App.RETOUR_MENU, P.GAGNE)
	h.ok(App.doit_arreter(r0, m2), "boucle: RESULTAT -> SELECTION_CARTE arrete aussi la partie")
	# CONTROLE NEGATIF : rester au menu n'arrete rien (sinon le predicat serait toujours vrai).
	h.ok(not App.doit_arreter(m0, m0), "boucle: rester au menu n'arrete rien")
	# CONTROLE NEGATIF du predicat GENERALISE : passer d'un ecran de partie a un AUTRE ecran de
	# partie n'arrete rien. C'est ce que la comparaison litterale « apres == MENU » ne pouvait
	# pas distinguer une fois la cible de retour deplacee.
	h.ok(not App.doit_arreter(r0, App.appliquer(r0, App.VALIDER, P.GAGNE)),
		"boucle: rejouer depuis le resultat n'ARRETE pas (on reste en partie)")
	h.ok(not App.doit_arreter(App.appliquer(m0, App.OUVRIR_OPTIONS, P.EN_COURS), m0),
		"boucle: un aller-retour dans les options n'arrete aucune partie")

	# NETTOYAGE REEL COTE RUNTIME. `doit_arreter` ne prouve qu'une intention ; ce volet
	# verifie que l'adaptateur DETRUIT effectivement la vue et la partie. Sans lui, l'arene
	# abandonnee restait affichee derriere le menu.
	const RT = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
	const Vue = preload("res://06_RUNTIME/adapters/presentation_3d/arena_view_3d.gd")
	var rt = RT.new()
	var vue_test = Vue.new()
	rt.add_child(vue_test)
	rt._vue = vue_test
	rt._partie = App.initial(1)   # objet non nul quelconque : seul le nettoyage est teste
	rt._accu = 0.5
	rt._note = 7
	h.eq(rt.get_child_count(), 1, "arret: CONTROLE POSITIF — la vue est bien attachee avant")
	rt._arreter()
	h.eq(rt._vue, null, "arret: la vue est detruite")
	h.eq(rt._partie, null, "arret: la partie est detruite")
	h.eq(rt._accu, 0.0, "arret: l'accumulateur de temps est remis a zero")
	h.eq(rt._note, 0, "arret: la piste musicale repart du debut")
	rt.free()

	# ---------- OPTIONS SONORES : meme machine a etats, pas un second menu ----------
	h.eq(int(m0["vol_musique"]), App.VOLUME_MAX, "options: volume musique initial au maximum")
	h.eq(int(m0["vol_effets"]), App.VOLUME_MAX, "options: volume effets initial au maximum")
	var o0: Dictionary = App.appliquer(m0, App.OUVRIR_OPTIONS, P.EN_COURS)
	h.eq(int(o0["ecran"]), App.OPTIONS, "options: MENU -> OPTIONS")
	var o1: Dictionary = App.appliquer(o0, App.CYCLE_VOL_MUSIQUE, P.EN_COURS)
	h.eq(int(o1["vol_musique"]), 0, "options: 100%% -> 0%% (le cycle permet de COUPER)")
	h.eq(int(o1["vol_effets"]), App.VOLUME_MAX, "options: regler la musique ne touche pas les effets")
	var o2: Dictionary = App.appliquer(o1, App.CYCLE_VOL_MUSIQUE, P.EN_COURS)
	h.eq(int(o2["vol_musique"]), App.VOLUME_PAS, "options: 0%% -> 25%%")
	var o3: Dictionary = App.appliquer(o2, App.CYCLE_VOL_EFFETS, P.EN_COURS)
	h.eq(int(o3["vol_effets"]), 0, "options: les effets se reglent independamment")
	h.eq(int(o3["vol_musique"]), App.VOLUME_PAS, "options: regler les effets ne touche pas la musique")
	# Le cycle est CLOS : cinq pas ramenent a la valeur de depart.
	var v: int = App.VOLUME_MAX
	for _k in range(5):
		v = App.volume_suivant(v)
	h.eq(v, App.VOLUME_MAX, "options: le cycle de volume revient a son point de depart")
	var m3: Dictionary = App.appliquer(o3, App.RETOUR_MENU, P.EN_COURS)
	h.eq(int(m3["ecran"]), App.MENU, "options: OPTIONS -> MENU")
	h.eq(int(m3["vol_effets"]), 0, "options: le reglage SURVIT a la fermeture de l'ecran")
	h.ok(not App.doit_arreter(o3, m3), "options: revenir au menu depuis OPTIONS n'arrete aucune partie")
	# Une touche de volume pressee EN PARTIE ne doit rien changer.
	var j2: Dictionary = App.appliquer(j0, App.CYCLE_VOL_MUSIQUE, P.EN_COURS)
	h.eq(int(j2["vol_musique"]), App.VOLUME_MAX,
		"options: un reglage n'est pas modifiable en pleine partie")

	h.eq(int(App.appliquer(a, 99, P.EN_COURS)["ecran"]), App.MENU,
		"app: une action hors vocabulaire ne fait rien")
	h.eq(int(App.appliquer(a, -5, P.EN_COURS)["ecran"]), App.MENU,
		"app: une action negative ne fait rien")
	h.eq(int(App.appliquer(e, App.CARTE_SUIVANTE, P.GAGNE)["carte"]), int(e["carte"]),
		"app: on ne change pas de carte depuis l'ecran de resultat")

	# ---------- purete : appliquer ne mute pas son entree ----------
	var avant_ecran: int = int(a["ecran"])
	App.appliquer(a, App.VALIDER, P.EN_COURS)
	h.eq(int(a["ecran"]), avant_ecran, "app: appliquer ne mute JAMAIS l'etat d'entree")

	# ---------- core.restart : la relance repart d'un etat IDENTIQUE au premier ----------
	var neuf1 = Fx.etat(Fx.desc_blocs(), 5, 2)
	var reference: Array = _empreinte(neuf1)
	var joue = neuf1
	for i in range(80):
		joue = Loop.step(joue, [P.POSER, P.DROITE])["state"]
	h.ok(_empreinte(joue) != reference, "restart: la partie jouee DIFFERE de l'etat initial")
	var neuf2 = Fx.etat(Fx.desc_blocs(), 5, 2)
	h.eq(_empreinte(neuf2), reference,
		"restart: une partie relancee est IDENTIQUE au premier demarrage (aucun residu)")
	h.eq(int(neuf2.ticks), 0, "restart: le compteur de ticks repart de zero")
	h.eq(neuf2.morts.size(), 0, "restart: aucune mort heritee")
	h.eq(neuf2.bombes.size(), 0, "restart: aucune bombe heritee")
	h.eq(int(neuf2.blocs_tombes), 0, "restart: la mort subite repart de zero")
	h.eq(neuf2.arene.nb_destructibles(), neuf1.arene.nb_destructibles(),
		"restart: l'arene est reconstruite entiere")

	# ====================================================================================
	# P8 — NAVIGATION PAR ECRANS (arbre ratifie Pierre, 2026-08-12)
	# ====================================================================================

	# ---------- LE MENU RACINE : un curseur, quatre destinations ----------
	var n0: Dictionary = App.initial(3)
	h.eq(int(n0["curseur_menu"]), App.MENU_JOUER, "menu: le curseur demarre sur JOUER")
	var n1: Dictionary = App.appliquer(n0, App.CARTE_SUIVANTE, P.EN_COURS)
	h.eq(int(n1["curseur_menu"]), App.MENU_CONTROLES, "menu: le curseur descend sur CONTROLES")
	h.eq(int(n1["carte"]), int(n0["carte"]),
		"menu: deplacer le curseur au MENU ne touche PAS a la carte selectionnee")
	var n2: Dictionary = App.appliquer(n1, App.CARTE_SUIVANTE, P.EN_COURS)
	h.eq(int(n2["curseur_menu"]), App.MENU_OPTIONS, "menu: puis OPTIONS")
	var n3: Dictionary = App.appliquer(n2, App.CARTE_SUIVANTE, P.EN_COURS)
	h.eq(int(n3["curseur_menu"]), App.MENU_QUITTER, "menu: puis QUITTER")
	var n4: Dictionary = App.appliquer(n3, App.CARTE_SUIVANTE, P.EN_COURS)
	h.eq(int(n4["curseur_menu"]), App.MENU_JOUER, "menu: le curseur BOUCLE sur la premiere entree")
	h.eq(int(n3["ecran"]), App.MENU, "menu: survoler QUITTER ne quitte pas")
	h.eq(bool(n3["quitter"]), false, "menu: survoler QUITTER ne leve AUCUN drapeau")

	# VALIDER est dispatche par le curseur — une destination par entree, aucune ambiguite.
	h.eq(int(App.appliquer(n0, App.VALIDER, P.EN_COURS)["ecran"]), App.SELECTION_CARTE,
		"menu: JOUER -> SELECTION_CARTE")
	h.eq(int(App.appliquer(n1, App.VALIDER, P.EN_COURS)["ecran"]), App.CONTROLES,
		"menu: CONTROLES -> CONTROLES")
	h.eq(int(App.appliquer(n2, App.VALIDER, P.EN_COURS)["ecran"]), App.OPTIONS,
		"menu: OPTIONS -> OPTIONS")
	h.eq(int(App.appliquer(n3, App.VALIDER, P.EN_COURS)["ecran"]), App.MENU,
		"menu: QUITTER ne navigue nulle part — il pose un drapeau")
	# Le raccourci secondaire est CONSERVE : `O` ouvre encore les options depuis le menu.
	h.eq(int(App.appliquer(n0, App.OUVRIR_OPTIONS, P.EN_COURS)["ecran"]), App.OPTIONS,
		"menu: OUVRIR_OPTIONS reste cable sur le MENU (raccourci conserve)")
	# L'ecran CONTROLES est un ecran de LECTURE : rien d'autre que le retour n'y agit.
	var ctl: Dictionary = App.appliquer(n1, App.VALIDER, P.EN_COURS)
	h.eq(int(App.appliquer(ctl, App.VALIDER, P.EN_COURS)["ecran"]), App.CONTROLES,
		"controles: VALIDER n'y fait rien — il n'y a rien a valider")
	h.eq(int(App.appliquer(ctl, App.CARTE_SUIVANTE, P.EN_COURS)["carte"]), int(ctl["carte"]),
		"controles: on n'y change pas de carte")

	# ---------- ECHAP REMONTE D'EXACTEMENT UN NIVEAU, DEPUIS N'IMPORTE OU ----------
	# Table EXHAUSTIVE : un ecran par ligne, sa cible attendue en face. Un ecran ajoute plus
	# tard sans sa ligne ici ferait echouer le controle de couverture qui suit.
	var e_menu: Dictionary = App.initial(3)
	var e_sel: Dictionary = App.appliquer(e_menu, App.VALIDER, P.EN_COURS)
	var e_ctl: Dictionary = App.appliquer(App.appliquer(e_menu, App.CARTE_SUIVANTE, P.EN_COURS),
		App.VALIDER, P.EN_COURS)
	var e_opt: Dictionary = App.appliquer(e_menu, App.OUVRIR_OPTIONS, P.EN_COURS)
	var e_jeu: Dictionary = App.appliquer(e_sel, App.VALIDER, P.EN_COURS)
	var e_pause: Dictionary = App.appliquer(e_jeu, App.BASCULER_PAUSE, P.EN_COURS)
	var e_res: Dictionary = App.appliquer(e_jeu, App.RIEN, P.GAGNE)
	h.eq(int(App.appliquer(e_menu, App.RETOUR_MENU, P.EN_COURS)["ecran"]), App.MENU,
		"echap: MENU est la RACINE — il n'y a rien au-dessus")
	h.eq(int(App.appliquer(e_sel, App.RETOUR_MENU, P.EN_COURS)["ecran"]), App.MENU,
		"echap: SELECTION_CARTE -> MENU")
	h.eq(int(App.appliquer(e_ctl, App.RETOUR_MENU, P.EN_COURS)["ecran"]), App.MENU,
		"echap: CONTROLES -> MENU")
	h.eq(int(App.appliquer(e_opt, App.RETOUR_MENU, P.EN_COURS)["ecran"]), App.MENU,
		"echap: OPTIONS -> MENU")
	# EN_JEU est le SEUL ecran ou ECHAP ne remonte pas : la sortie d'une partie passe par la
	# PAUSE. Propriete d'origine, deliberement conservee — une touche unique ne doit pas
	# pouvoir jeter une partie en cours par inadvertance.
	h.eq(int(App.appliquer(e_jeu, App.RETOUR_MENU, P.EN_COURS)["ecran"]), App.EN_JEU,
		"echap: EN_JEU ne remonte pas — la sortie passe par la PAUSE")
	h.eq(int(App.appliquer(e_pause, App.RETOUR_MENU, P.EN_COURS)["ecran"]), App.SELECTION_CARTE,
		"echap: PAUSE -> SELECTION_CARTE")
	h.eq(int(App.appliquer(e_res, App.RETOUR_MENU, P.GAGNE)["ecran"]), App.SELECTION_CARTE,
		"echap: RESULTAT -> SELECTION_CARTE")
	# ABANDON, pas suspension : remonter depuis la pause DETRUIT la partie.
	h.ok(App.doit_arreter(e_pause, App.appliquer(e_pause, App.RETOUR_MENU, P.EN_COURS)),
		"echap: quitter la PAUSE ABANDONNE la partie — il n'y a pas de partie suspendue")
	h.eq(int(App.appliquer(e_pause, App.RETOUR_MENU, P.EN_COURS)["issue"]), App.ISSUE_AUCUNE,
		"echap: l'abandon ne laisse AUCUNE issue derriere lui")
	# COUVERTURE : tout ecran declare a une ligne ci-dessus. Le controle compte les ecrans du
	# systeme et exige que la table en couvre autant — sinon un ecran ajoute demain echapperait
	# silencieusement a la regle « ECHAP remonte d'un niveau ».
	var ecrans_couverts: Array = [int(e_menu["ecran"]), int(e_sel["ecran"]), int(e_ctl["ecran"]),
		int(e_opt["ecran"]), int(e_jeu["ecran"]), int(e_pause["ecran"]), int(e_res["ecran"])]
	var vus_ecrans := {}
	for x_e in ecrans_couverts:
		vus_ecrans[x_e] = true
	h.eq(vus_ecrans.size(), 7, "echap: les SEPT ecrans du systeme sont couverts, chacun une fois")

	# ---------- QUITTER : un DRAPEAU, jamais un appel a l'OS ----------
	var q0: Dictionary = App.initial(3)
	q0["curseur_menu"] = App.MENU_QUITTER
	var q1: Dictionary = App.appliquer(q0, App.VALIDER, P.EN_COURS)
	h.ok(bool(q1["quitter"]), "quitter: VALIDER sur QUITTER leve le drapeau")
	h.ok(App.doit_quitter(q0, q1), "quitter: le FRONT du drapeau est detecte")
	h.eq(int(q1["ecran"]), App.MENU, "quitter: le drapeau ne deplace aucun ecran")
	var q2: Dictionary = App.appliquer(q1, App.RIEN, P.EN_COURS)
	h.ok(not App.doit_quitter(q1, q2),
		"quitter: un drapeau DEJA haut ne redeclenche pas — c'est un front, pas un etat")
	# CONTROLE NEGATIF EXHAUSTIF : sept ecrans x quatre positions de curseur x tout le
	# vocabulaire d'actions. La seule combinaison qui doit quitter est VALIDER sur le MENU avec
	# le curseur sur QUITTER ; toute autre reponse — manquante ou en trop — est une fuite.
	var echantillons: Array = [e_menu, e_sel, e_ctl, e_opt, e_jeu, e_pause, e_res]
	var fuites: Array = []
	for etat_q in echantillons:
		for c_q in range(App.MENU_NB):
			var dep: Dictionary = etat_q.duplicate()
			dep["curseur_menu"] = c_q
			for act_q in range(App.CYCLE_VOL_EFFETS + 1):
				var arr_q: Dictionary = App.appliquer(dep, act_q, P.EN_COURS)
				var legitime: bool = (int(dep["ecran"]) == App.MENU
					and act_q == App.VALIDER and c_q == App.MENU_QUITTER)
				if App.doit_quitter(dep, arr_q) != legitime:
					fuites.append("ecran %d curseur %d action %d" % [int(dep["ecran"]), c_q, act_q])
	h.eq(fuites, [],
		"quitter: sur 7x4x8 combinaisons, SEULE VALIDER-sur-QUITTER quitte")

	# ---------- LE PARCOURS RATIFIE, D'UN BOUT A L'AUTRE ----------
	# MENU -> SELECTION_CARTE -> carte suivante -> confirmer -> EN_JEU -> PAUSE -> ECHAP ->
	# SELECTION_CARTE -> ECHAP -> MENU. Prouve par assertions PURES, sans moteur.
	var t_menu: Dictionary = App.initial(3)
	h.eq(int(t_menu["ecran"]), App.MENU, "parcours: on part du MENU")
	var t_sel: Dictionary = App.appliquer(t_menu, App.VALIDER, P.EN_COURS)
	h.eq(int(t_sel["ecran"]), App.SELECTION_CARTE, "parcours: JOUER ouvre le choix de carte")
	var t_sel2: Dictionary = App.appliquer(t_sel, App.CARTE_SUIVANTE, P.EN_COURS)
	h.eq(int(t_sel2["carte"]), 1, "parcours: la carte suivante est selectionnee")
	h.eq(int(t_sel2["ecran"]), App.SELECTION_CARTE, "parcours: changer de carte ne quitte pas l'ecran")
	var t_jeu: Dictionary = App.appliquer(t_sel2, App.VALIDER, P.EN_COURS)
	h.eq(int(t_jeu["ecran"]), App.EN_JEU, "parcours: confirmer lance la partie")
	h.eq(int(t_jeu["carte"]), 1, "parcours: c'est bien la carte CHOISIE qui part en jeu")
	h.ok(App.doit_demarrer(t_sel2, t_jeu), "parcours: l'entree en jeu demande une partie neuve")
	var t_pause: Dictionary = App.appliquer(t_jeu, App.BASCULER_PAUSE, P.EN_COURS)
	h.eq(int(t_pause["ecran"]), App.PAUSE, "parcours: P met en pause")
	var t_retour: Dictionary = App.appliquer(t_pause, App.RETOUR_MENU, P.EN_COURS)
	h.eq(int(t_retour["ecran"]), App.SELECTION_CARTE, "parcours: ECHAP remonte au choix de carte")
	h.ok(App.doit_arreter(t_pause, t_retour), "parcours: la partie abandonnee est DETRUITE")
	h.eq(int(t_retour["carte"]), 1, "parcours: la carte choisie SURVIT a l'abandon")
	var t_racine: Dictionary = App.appliquer(t_retour, App.RETOUR_MENU, P.EN_COURS)
	h.eq(int(t_racine["ecran"]), App.MENU, "parcours: ECHAP remonte enfin a la racine")
	h.eq(int(t_racine["curseur_menu"]), App.MENU_JOUER,
		"parcours: le menu retrouve son curseur — la navigation ne perd pas sa position")

	# ---------- LA CARTE CHOISIE EST CELLE QUE LE RUNTIME CONSOMME ----------
	# Le maillon que la machine a etats seule ne prouve pas : `carte` n'est utile que s'il sert
	# reellement d'INDEX au descripteur charge par le runtime. On fait donc tourner le VRAI
	# `_demarrer()` et on compare l'arene construite au descripteur du meme index.
	var total_cartes: int = Content.nb_cartes()
	h.gt(total_cartes, 1, "index: CONTROLE POSITIF — le catalogue porte plusieurs cartes")
	var signatures := {}
	for i_c in range(total_cartes):
		var etat_c: Dictionary = App.appliquer(App.initial(total_cartes), App.VALIDER, P.EN_COURS)
		for _k2 in range(i_c):
			etat_c = App.appliquer(etat_c, App.CARTE_SUIVANTE, P.EN_COURS)
		h.eq(int(etat_c["carte"]), i_c,
			"index: %d pressions sur l'ecran de selection donnent la carte %d" % [i_c, i_c])
		var rt_c = RT.new()
		rt_c._app = etat_c
		rt_c._demarrer()
		h.ok(rt_c._partie != null, "index: le runtime construit bien une partie pour la carte %d" % i_c)
		var attendu = Validator.carte_validee(Content.descripteur(i_c))["arene"]
		var sig_jouee: String = Marshalls.raw_to_base64(rt_c._partie.arene.cases)
		var sig_attendue: String = Marshalls.raw_to_base64(attendu.cases)
		h.eq(sig_jouee, sig_attendue,
			"index: la carte JOUEE est le descripteur d'index %d, pas un autre" % i_c)
		signatures[sig_jouee] = true
		rt_c._arreter()
		rt_c.free()
	# CONTROLE POSITIF de l'assertion precedente : sans arenes distinctes, comparer une arene a
	# elle-meme serait vrai quel que soit l'index, et la preuve ne mesurerait rien.
	h.eq(signatures.size(), total_cartes,
		"index: les cartes du catalogue sont REELLEMENT distinctes (sinon la preuve serait vide)")

	# ---------- L'INTERFACE REND L'ETAT, ET RIEN QU'ELLE NE POSSEDE ----------
	h.eq(Shell.ENTREES_MENU.size(), App.MENU_NB,
		"ui: un libelle par entree du menu — l'interface ne peut pas afficher une entree que la"
		+ " machine a etats ne sait pas ouvrir")
	var lm0: String = Shell.lignes_menu(App.MENU_JOUER)
	var lm3: String = Shell.lignes_menu(App.MENU_QUITTER)
	h.eq(lm0.split("\n").size(), App.MENU_NB, "ui: le menu affiche ses quatre lignes")
	h.ok(lm0 != lm3, "ui: deux positions de curseur ne se lisent pas pareil")
	h.ok(lm0.split("\n")[App.MENU_JOUER].begins_with(Shell.MARQUE_CHOIX),
		"ui: la marque est posee sur la ligne DU curseur")
	h.ok(not lm0.split("\n")[App.MENU_QUITTER].begins_with(Shell.MARQUE_CHOIX),
		"ui: et sur aucune autre")
	h.gt(Shell.legende_commandes().size(), 2, "ui: l'ecran CONTROLES porte plusieurs commandes")
	var texte_cmd: String = "\n".join(Shell.legende_commandes())
	h.ok(texte_cmd.find("ESPACE") >= 0, "ui: la commande de bombe est ecrite quelque part")
	h.ok(texte_cmd.find("ECHAP") >= 0, "ui: le retour arriere est ecrit quelque part")

	# APERCU DU PLAN : derive du descripteur DEJA charge, jamais d'un asset ni d'une copie.
	var desc0: Dictionary = Content.descripteur(0)
	var ap0: String = Shell.apercu_plan(desc0)
	h.eq(ap0.split("\n").size(), (desc0["plan"] as Array).size(),
		"ui: l'apercu porte exactement autant de rangees que le plan de la carte")
	h.ok(ap0.find("#") >= 0, "ui: l'apercu montre les murs du plan reel")
	h.ok(Shell.apercu_plan(Content.descripteur(1)) != ap0,
		"ui: deux cartes n'ont pas le meme apercu (sinon l'apercu ne montrerait rien)")
	h.eq(Shell.apercu_plan({}), "",
		"ui: sans plan, l'apercu se tait au lieu d'inventer une carte")
	# LA FICHE N'EXPOSE QUE CE QUE LA CARTE POSSEDE. Ni difficulte, ni nombre de joueurs :
	# aucun descripteur ne porte ces champs, les afficher serait les inventer.
	var fiche0: String = Shell.fiche_carte(desc0, 0, total_cartes)
	h.ok(fiche0.find(Shell.nom_carte(desc0)) >= 0, "ui: la fiche NOMME la carte")
	h.ok(fiche0.find(Shell.theme_carte(desc0)) >= 0, "ui: la fiche donne son theme")
	h.eq(desc0.has("difficulte"), false,
		"ui: CONTROLE — le descripteur ne porte AUCUNE difficulte (donc la fiche n'en affiche pas)")
	h.eq(fiche0.to_lower().find("difficult"), -1, "ui: la fiche n'invente pas de difficulte")
	h.eq(fiche0.to_lower().find("joueur"), -1, "ui: la fiche n'invente pas un nombre de joueurs")
	h.eq(fiche0.to_lower().find("bot"), -1, "ui: la fiche n'invente pas un nombre de bots")

	# ---------- LES SEPT ECRANS S'AFFICHENT REELLEMENT ----------
	# PREUVE D'EXECUTION, pas d'existence. Le shell est instancie ET ATTACHE (donc `_ready`
	# court pour de vrai) puis rafraichi sur chaque ecran avec le VRAI catalogue. Sans ce volet,
	# les fonctions pures ci-dessus seraient vertes pendant qu'un ecran neuf planterait a
	# l'affichage — le mode de panne que ce depot nomme « preuve sans executeur ».
	var catalogue: Array = []
	for i_u in range(Content.nb_cartes()):
		catalogue.append(Content.descripteur(i_u))
	var shell = Shell.new()
	# `_ready` APPELE A LA MAIN, et c'est un fait mesure et non une preference : ce harnais est
	# un SceneTree qui rend son verdict pendant `_initialize`, avant la premiere frame. Un noeud
	# attache a la racine ici ne recoit jamais son cycle de vie — ses labels restent nuls et le
	# volet s'interrompt en SILENCE au milieu (constate a l'execution). On construit donc l'ecran
	# explicitement, ce qui est exactement ce que ce volet veut prouver : il se construit.
	shell._ready()
	h.ok(shell._bloc != null, "ecrans: CONTROLE POSITIF — le shell est REELLEMENT construit")

	shell.rafraichir(e_menu, null, catalogue, 0)
	h.gt(shell._titre.text.length(), 0, "ecrans: le MENU affiche un titre")
	h.ok(shell._sous_titre.text.find("JOUER") >= 0, "ecrans: le MENU liste ses entrees")
	h.ok(shell._sous_titre.text.find("QUITTER") >= 0, "ecrans: QUITTER est visible au menu")
	h.eq(shell._bloc.visible, false, "ecrans: le MENU n'ouvre aucun bloc de detail")

	shell.rafraichir(e_sel, null, catalogue, 0)
	h.ok(shell._sous_titre.text.find(Shell.nom_carte(catalogue[0])) >= 0,
		"ecrans: la selection NOMME la carte courante, lue dans le catalogue")
	h.ok(shell._bloc.visible, "ecrans: la selection affiche l'apercu du plan")
	h.eq(shell._bloc.text, Shell.apercu_plan(catalogue[0]),
		"ecrans: l'apercu affiche est bien celui de la carte selectionnee")
	# LE CATALOGUE EST CONSOMME, PAS RECOPIE : changer l'index change le nom affiche.
	var sel_derniere: Dictionary = e_sel.duplicate()
	sel_derniere["carte"] = Content.nb_cartes() - 1
	shell.rafraichir(sel_derniere, null, catalogue, 0)
	h.ok(shell._sous_titre.text.find(Shell.nom_carte(catalogue[Content.nb_cartes() - 1])) >= 0,
		"ecrans: une autre carte affiche un AUTRE nom — le shell lit le catalogue")
	h.eq(shell._bloc.text, Shell.apercu_plan(catalogue[Content.nb_cartes() - 1]),
		"ecrans: et un AUTRE apercu")

	shell.rafraichir(e_ctl, null, catalogue, 0)
	h.eq(shell._titre.text, "CONTROLES", "ecrans: l'ecran CONTROLES porte son titre")
	h.ok(shell._sous_titre.text.find("ESPACE") >= 0, "ecrans: il porte les commandes du joueur")
	h.eq(shell._bloc.text, "\n".join(Shell.legende()),
		"ecrans: la legende des power-ups y est ENFIN affichee — elle n'avait aucun lecteur")

	shell.rafraichir(e_opt, null, catalogue, 0)
	h.ok(shell._sous_titre.text.find("Musique") >= 0, "ecrans: les OPTIONS montrent leurs jauges")
	h.eq(shell._bloc.visible, false, "ecrans: les OPTIONS n'heritent pas du bloc precedent")

	shell.rafraichir(e_jeu, null, catalogue, 0)
	h.eq(shell._titre.visible, false, "ecrans: EN JEU, l'ecran se tait")
	h.eq(shell._bloc.visible, false, "ecrans: EN JEU, aucun bloc de detail ne reste affiche")

	shell.rafraichir(e_pause, null, catalogue, 0)
	h.eq(shell._titre.text, "PAUSE", "ecrans: la PAUSE porte son titre")
	h.ok(shell._titre.visible, "ecrans: et redevient visible en sortant du jeu")
	shell.rafraichir(e_res, null, catalogue, 0)
	h.eq(shell._titre.text, App.libelle_issue(int(e_res["issue"])),
		"ecrans: le RESULTAT porte le libelle de l'issue")

	shell.free()
