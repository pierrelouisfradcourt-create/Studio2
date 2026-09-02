# v6_p3_victory_easter_egg.gd — POINT P3 DU LOT DE VALIDATION.
#
# ORIGINE : demande explicite de Pierre (2026-08-06). AUCUN oracle ne l'a reclame — ce
# n'est pas la correction d'un defaut mesure, c'est un ajout de design, et il est declare
# comme tel.
#
# LA REGLE : sur l'ecran de VICTOIRE seulement, si et seulement si le joueur a gagne SANS
# AUCUNE ASSISTANCE — victoire ET mode du defi ET dash desactive. Les trois conditions
# sont CONJONCTIVES.
#
# CE QUE CETTE PREUVE MESURE :
# (1) LE CAS POSITIF : les trois conditions reunies, le clin d'oeil est la, et il est LU
#     dans le recap reellement produit — une preuve sans lecteur n'existe pas ;
# (2) LES TROIS CONTRE-EPREUVES, une par condition manquante : defaite, mode Decouverte,
#     dash actif. Une condition conjonctive dont on ne teste que le cas positif est
#     indistinguable d'une condition vraie tout le temps ;
# (3) LE FLUX DE VICTOIRE EST INTACT : memes choix, memes effets, memes transitions, meme
#     condition de victoire. Le clin d'oeil s'AJOUTE, il ne deplace rien ;
# (4) LE MESSAGE EST FICTIF ET NON CIBLE : il ne parle que des entites du jeu.
extends RefCounted

const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


# Partie REELLEMENT JOUEE puis menee a son terme, dans les reglages demandes. Le score
# affiche vient donc d'un jeu, pas d'un etat fabrique de toutes pieces.
# LIMITE DE MESURE ASSUMEE : la derniere pastille est posee par le harnais
# (`consommees = total_pose`), comme le fait deja render_end_screen — jouer une victoire
# complete coute des milliers de ticks, et c'est l'oracle de solvabilite R9 qui la prouve.
func _partie_terminee(mode: int, dash: bool, gagnee: bool) -> Dictionary:
	var jeu = State.initial(Maze, 1, 0, {"mode": mode, "dash_actif": dash})
	for _t in range(120):
		if jeu.statut != State.Statut.EN_COURS:
			break
		jeu = Loop.step(jeu, Bot.choisir_action(jeu))["etat"]
	if gagnee:
		jeu.consommees = jeu.total_pose
	else:
		jeu.vies = 0
	Status.appliquer(jeu)
	return Observable.projeter(jeu)


func run(h) -> void:
	# --- (1) LE CAS POSITIF : LES TROIS CONDITIONS REUNIES. ---
	var sans_aide: Dictionary = _partie_terminee(Reglages.Mode.NORMAL, false, true)
	h.eq(int(sans_aide["statut"]), State.Statut.GAGNE, "v6.p3: la partie temoin est bien gagnee")
	h.eq(sans_aide["mode_jeu"], Reglages.nom(Reglages.Mode.NORMAL), "v6.p3: dans le mode du defi")
	h.eq(bool(sans_aide["dash_actif"]), false, "v6.p3: et sans dash")
	h.eq(EndScreen.victoire_sans_aide(sans_aide), true, "v6.p3: la victoire sans aide est reconnue")
	h.eq(EndScreen.clin_d_oeil(sans_aide), EndScreen.CLIN_D_OEIL_SANS_AIDE, "v6.p3: le clin d'oeil est rendu")
	# IL EST REELLEMENT LU : il apparait dans le recap produit, en DERNIERE ligne.
	var recap_egg: String = EndScreen.recap(sans_aide, 0)
	h.ok(recap_egg.contains(EndScreen.CLIN_D_OEIL_SANS_AIDE), "v6.p3: le recap le porte")
	var lignes_egg: Array = recap_egg.split("\n")
	h.eq(lignes_egg.size(), EndScreen.LIGNES_RECAP_MAX, "v6.p3: le recap compte alors une ligne de plus")
	h.eq(String(lignes_egg[lignes_egg.size() - 1]), EndScreen.CLIN_D_OEIL_SANS_AIDE,
		"v6.p3: et c'est la derniere ligne")

	# --- (2) LES TROIS CONTRE-EPREUVES : UNE CONDITION MANQUANTE SUFFIT A LE TAIRE. ---
	# (a) DEFAITE, meme mode, meme absence de dash.
	var perdue: Dictionary = _partie_terminee(Reglages.Mode.NORMAL, false, false)
	h.eq(int(perdue["statut"]), State.Statut.PERDU, "v6.p3: contre-epreuve (a) — la partie est perdue")
	h.eq(EndScreen.victoire_sans_aide(perdue), false, "v6.p3: (a) aucun clin d'oeil sur une defaite")
	h.eq(EndScreen.clin_d_oeil(perdue), "", "v6.p3: (a) et le texte rendu est vide")
	h.eq(EndScreen.recap(perdue, 0).contains(EndScreen.CLIN_D_OEIL_SANS_AIDE), false,
		"v6.p3: (a) le recap de defaite ne le porte pas")
	# (b) VICTOIRE, mais en mode Decouverte.
	var decouverte: Dictionary = _partie_terminee(Reglages.Mode.TEST, false, true)
	h.eq(int(decouverte["statut"]), State.Statut.GAGNE, "v6.p3: contre-epreuve (b) — la partie est gagnee")
	h.eq(decouverte["mode_jeu"], Reglages.nom(Reglages.Mode.TEST), "v6.p3: (b) mais en mode Decouverte")
	h.eq(EndScreen.victoire_sans_aide(decouverte), false, "v6.p3: (b) aucun clin d'oeil hors du mode du defi")
	h.eq(EndScreen.recap(decouverte, 0).contains(EndScreen.CLIN_D_OEIL_SANS_AIDE), false,
		"v6.p3: (b) le recap ne le porte pas")
	# (c) VICTOIRE, mode du defi, mais DASH ACTIF.
	var avec_dash: Dictionary = _partie_terminee(Reglages.Mode.NORMAL, true, true)
	h.eq(int(avec_dash["statut"]), State.Statut.GAGNE, "v6.p3: contre-epreuve (c) — la partie est gagnee")
	h.eq(bool(avec_dash["dash_actif"]), true, "v6.p3: (c) mais le dash etait actif")
	h.eq(EndScreen.victoire_sans_aide(avec_dash), false, "v6.p3: (c) aucun clin d'oeil avec le dash")
	h.eq(EndScreen.recap(avec_dash, 0).contains(EndScreen.CLIN_D_OEIL_SANS_AIDE), false,
		"v6.p3: (c) le recap ne le porte pas")
	# UN RELEVE INCOMPLET ne le declenche pas non plus : le repli est le silence.
	h.eq(EndScreen.victoire_sans_aide({"statut": State.Statut.GAGNE, "score": 0}), false,
		"v6.p3: un releve sans mode ni dash ne declenche rien")
	h.eq(EndScreen.victoire_sans_aide({}), false, "v6.p3: un releve vide non plus")

	# CONJONCTION VERIFIEE PAR ENUMERATION : sur les huit combinaisons des trois faits,
	# EXACTEMENT UNE allume le clin d'oeil. Un `ou` a la place d'un `et` en allumerait
	# plusieurs, et ce comptage le verrait.
	var allumees: int = 0
	for statut in [State.Statut.GAGNE, State.Statut.PERDU]:
		for m in Reglages.MODES_VALIDES:
			for d in [false, true]:
				var faux_releve: Dictionary = {
					"statut": statut, "score": 0,
					"mode_jeu": Reglages.nom(m), "dash_actif": d,
				}
				if EndScreen.victoire_sans_aide(faux_releve):
					allumees += 1
	h.eq(allumees, 1, "v6.p3: exactement une des huit combinaisons allume le clin d'oeil")

	# --- (3) LE FLUX DE VICTOIRE EST INTACT. ---
	# Memes choix, dans le meme ordre, avec les memes effets et les memes transitions.
	h.eq(EndScreen.ENTREES.size(), 2, "v6.p3: toujours deux suites offertes")
	h.eq(EndScreen.libelle(EndScreen.Choix.REJOUER), "Rejouer", "v6.p3: Rejouer est toujours la")
	h.eq(EndScreen.libelle(EndScreen.Choix.MENU_PRINCIPAL), "Menu principal", "v6.p3: Menu principal aussi")
	h.eq(EndScreen.effet(EndScreen.Choix.REJOUER)["etat"], App.Etat.PARTIE, "v6.p3: Rejouer mene a la partie")
	h.eq(EndScreen.effet(EndScreen.Choix.REJOUER)["action"], Menu.ACTION_NOUVELLE_PARTIE,
		"v6.p3: par une nouvelle partie")
	h.eq(EndScreen.effet(EndScreen.Choix.MENU_PRINCIPAL)["etat"], App.Etat.TITRE, "v6.p3: l'autre mene au titre")
	h.eq(EndScreen.choix_sans_effet(), 0, "v6.p3: 0 choix sans effet observable")
	# LA CONDITION DE VICTOIRE elle-meme n'a pas bouge : egalite stricte, jamais un >=.
	h.eq(End.victoire(10, 10), true, "v6.p3: la victoire reste l'egalite stricte")
	h.eq(End.victoire(9, 10), false, "v6.p3: a un collectible pres, la partie continue")
	h.eq(End.victoire(11, 10), false, "v6.p3: et un depassement n'est pas une victoire")
	# LE RECAP SANS CLIN D'OEIL est EXACTEMENT celui d'avant : meme nombre de lignes, et le
	# recap avec clin d'oeil le CONTIENT comme prefixe — rien n'a ete deplace ni reecrit.
	h.eq(EndScreen.recap(avec_dash, 0).split("\n").size(), EndScreen.LIGNES_RECAP,
		"v6.p3: sans clin d'oeil, le recap garde ses cinq lignes")
	var sans_egg: Dictionary = sans_aide.duplicate(true)
	sans_egg["dash_actif"] = true
	h.ok(recap_egg.begins_with(EndScreen.recap(sans_egg, 0)),
		"v6.p3: le recap ordinaire est un prefixe exact du recap avec clin d'oeil")
	# LA SELECTION est toujours honoree : le clin d'oeil ne mange pas le marqueur de choix.
	h.ok(EndScreen.recap(sans_aide, 1) != recap_egg, "v6.p3: la selection change encore le recap")
	h.ok(EndScreen.recap(sans_aide, 1).contains(EndScreen.CLIN_D_OEIL_SANS_AIDE),
		"v6.p3: et le clin d'oeil survit au changement de selection")
	# LA ZONE DE TEXTE EST DIMENSIONNEE POUR LA LIGNE SUPPLEMENTAIRE : sans cela, elle se
	# lirait sur le labyrinthe — le defaut corrige en V4.
	h.eq(EndScreen.HAUTEUR_TEXTE, EndScreen.HAUTEUR_LIGNE * EndScreen.LIGNES_RECAP_MAX,
		"v6.p3: la hauteur de la zone est derivee du nombre de lignes maximal")
	h.gt(EndScreen.LIGNES_RECAP_MAX, EndScreen.LIGNES_RECAP, "v6.p3: le maximum depasse le cas ordinaire")

	# --- (4) LE MESSAGE EST FICTIF ET NON CIBLE. ---
	h.gt(EndScreen.CLIN_D_OEIL_SANS_AIDE.length(), 0, "v6.p3: le message n'est pas vide")
	h.lt(EndScreen.CLIN_D_OEIL_SANS_AIDE.length(), 120, "v6.p3: il reste court")
	h.ok(EndScreen.CLIN_D_OEIL_SANS_AIDE.contains("fantomes"),
		"v6.p3: il ne parle que des entites du jeu")
