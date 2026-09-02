# v4_p2_end_screen_modal_layer.gd — CAUSE RACINE P2 : ECRAN DE FIN ILLISIBLE.
#
# DEFAUT MESURE (playtest Pierre) : l'ecran de fin SE MELANGEAIT A LA CARTE. L'audit a
# trouve DEUX causes, toutes deux de rendu — la logique, elle, etait complete depuis V3
# (App.Etat.FIN, end_screen + app_shell._fin cablent deja les choix) :
#   (1) AUCUNE COUCHE entre le labyrinthe et le texte : le recap se lisait sur les murs ;
#   (2) DEUX SURFACES DE TEXTE au meme endroit — le recap de fin (_fin, hauteur/2 - 48)
#       ET l'ecran de coquille FIN (_menu, hauteur/2 - 120) etaient rendus ensemble.
#
# CE QUE CETTE PREUVE MESURE : l'existence d'une couche opaque, son inclusion de la zone
# de texte, le contraste du texte pose dessus, et l'exclusivite des deux surfaces.
#
# CE QUI N'EST PAS MESURE ICI, ET POURQUOI : la comparaison de PIXELS exige une fenetre
# GPU reelle (`--headless` rend une texture nulle, mesure au studio le 2026-07-22). Que
# l'ecran soit LU sans effort par une personne reste un constat humain (fog HumanGate).
extends RefCounted

const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")

const CHEMIN_RUNTIME := "res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd"


func _texte(chemin: String) -> String:
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


func run(h) -> void:
	# --- (1) UNE COUCHE EXISTE, ET ELLE EST OPAQUE. ---
	h.eq(EndScreen.couche_opaque(), true, "v4.p2: la couche de fin est opaque")
	h.gt(int(EndScreen.opacite_modale() * 1000.0), int(EndScreen.OPACITE_MINIMALE * 1000.0),
		"v4.p2: son opacite depasse le seuil declare")
	# Une couche modale n'est PAS un ecran de remplacement : la partie reste visible
	# derriere, assombrie. C'est ce qui la distingue de FOND_ECRAN.
	h.eq(EndScreen.partie_visible_derriere(), true, "v4.p2: la partie reste visible derriere")
	h.ok(EndScreen.fond_modal() != Palette.FOND_ECRAN, "v4.p2: le voile n'est pas le fond d'ecran")
	h.eq(EndScreen.fond_modal(), Palette.FOND_MODAL, "v4.p2: la teinte vient du descripteur unique")
	h.eq(Palette.paires_identiques(), 0, "v4.p2: la palette ne repete aucune teinte")
	h.eq(Purity.couleur_hors_palette().size(), 0, "v4.p2: 0 litteral de couleur hors palette")

	# LE TEXTE SE LIT DESSUS : contraste mesure, jamais suppose.
	h.eq(EndScreen.texte_lisible_sur_le_voile(), true, "v4.p2: le texte contraste sur le voile")
	h.gt(int(EndScreen.contraste_texte() * 1000.0), int(EndScreen.CONTRASTE_MINIMAL * 1000.0),
		"v4.p2: l'ecart de luminance depasse le seuil declare")

	# --- LA COUCHE CONTIENT LA ZONE DE TEXTE : rien du recap n'affleure sur la carte. ---
	var largeur: int = Boot.largeur_fenetre()
	var hauteur: int = Boot.hauteur_fenetre()
	h.gt(largeur, 0, "v4.p2: l'enveloppe a une largeur")
	h.gt(hauteur, 0, "v4.p2: l'enveloppe a une hauteur")
	var voile: Rect2 = EndScreen.rect_modal(largeur, hauteur)
	var zone: Rect2 = EndScreen.rect_texte(largeur, hauteur)
	h.eq(voile.size, Vector2(float(largeur), float(hauteur)), "v4.p2: le voile couvre toute l'enveloppe")
	h.eq(EndScreen.voile_contient_le_texte(largeur, hauteur), true,
		"v4.p2: le voile contient la zone de texte")
	h.gt(int(zone.size.y), 0, "v4.p2: la zone de texte n'est pas degeneree")
	# Elle est CENTREE : autant de place au-dessus qu'en dessous.
	h.eq(int(zone.position.y * 2.0 + zone.size.y), hauteur, "v4.p2: la zone de texte est centree")
	# Elle est assez haute pour les lignes du recap.
	h.eq(EndScreen.LIGNES_RECAP, 5, "v4.p2: le recap compte cinq lignes")
	var recap: String = EndScreen.recap({"statut": State.Statut.GAGNE, "score": 4242}, 0)
	h.eq(recap.split("\n").size(), EndScreen.LIGNES_RECAP, "v4.p2: le recap rend bien ses cinq lignes")
	h.ok(recap.contains("4242"), "v4.p2: le score final y est")

	# --- (2) UNE SEULE SURFACE DE TEXTE PAR ETAT. ---
	h.eq(RuntimeLoop.etats_a_double_surface(), 0, "v4.p2: 0 etat rend deux surfaces de texte")
	h.eq(RuntimeLoop.surface_de_fin(App.Etat.FIN), true, "v4.p2: a la fin, la surface de fin porte le texte")
	h.eq(RuntimeLoop.surface_de_menu(App.Etat.FIN), false, "v4.p2: et le menu de coquille se tait")
	h.eq(RuntimeLoop.surface_de_menu(App.Etat.TITRE), true, "v4.p2: au titre, le menu porte le texte")
	h.eq(RuntimeLoop.surface_de_fin(App.Etat.TITRE), false, "v4.p2: et la surface de fin se tait")
	h.eq(RuntimeLoop.surface_de_menu(App.Etat.PAUSE), true, "v4.p2: en pause, le menu porte le texte")
	h.eq(RuntimeLoop.surface_de_menu(App.Etat.PARTIE), false, "v4.p2: en partie, aucun menu ne s'affiche")
	h.eq(RuntimeLoop.surface_de_fin(App.Etat.PARTIE), false, "v4.p2: ni recap de fin")
	# AUCUN etat sans aucune surface parmi les etats de menu : une couche de trop ET une
	# couche de moins sont deux defauts distincts.
	var sans_surface: int = 0
	for e in App.ETATS_VALIDES:
		if e == App.Etat.PARTIE:
			continue
		if not RuntimeLoop.surface_de_fin(e) and not RuntimeLoop.surface_de_menu(e):
			sans_surface += 1
	h.eq(sans_surface, 0, "v4.p2: aucun ecran hors partie ne reste sans texte")

	# --- LE RUNTIME DESSINE REELLEMENT LA COUCHE. Sans executeur, elle n'existe pas. ---
	var source: String = _texte(CHEMIN_RUNTIME)
	h.ok(source.find("draw_rect(EndScreen.rect_modal(") >= 0,
		"v4.p2: la boucle du runtime dessine le voile")
	h.ok(source.find("EndScreen.rect_texte(") >= 0,
		"v4.p2: elle pose le label de fin a la geometrie declaree")
	h.ok(source.find("surface_de_fin(") >= 0, "v4.p2: elle consulte l'unique autorite d'affichage")
