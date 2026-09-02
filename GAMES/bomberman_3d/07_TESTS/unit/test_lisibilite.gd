# test_lisibilite.gd — DISCERNABILITE et TELEGRAPHE DE DANGER.
#
# Oracle porte de games/snake/.../grid_view.gd::categories_couleur_partagee (« l'oracle
# exige 0 ») et DURCI : pour un power-up, la couleur seule ne suffit pas, il faut aussi une
# forme distincte. C'est ce volet qui echouait avant ce lot — trois power-ups partageaient
# une seule couleur et une seule forme.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Pal = preload("res://06_RUNTIME/adapters/palette/palette.gd")
const Shell = preload("res://06_RUNTIME/adapters/ui_shell/ui_shell.gd")
const Explosion = preload("res://05_SYSTEMS/explosion/explosion.gd")
const Purete = preload("res://06_RUNTIME/adapters/proof_harness/purete_visuelle.gd")
const Fx = preload("res://07_TESTS/unit/fixtures.gd")


func run(h) -> void:
	# ---------- UNICITE DU DESCRIPTEUR (oracle porte de Pacman) ----------
	# `palette.gd` AFFIRMAIT etre la source unique ; rien ne le verifiait. Une regle qui
	# vit dans la prose echappe a toute verification.
	h.eq(Purete.couleur_hors_palette(), [],
		"purete: 0 litteral de couleur hors du descripteur, dans tout le runtime")
	h.ok(Purete.couleur_dans_palette(),
		"purete: le descripteur en porte — CONTROLE POSITIF (sinon la sonde ne mesure rien)")
	h.eq(Purete.couleur_dans_logique(), [],
		"purete: 0 fichier de REGLES ne connait une couleur")
	h.eq(Purete.code_seul("var a = 1  # Color(1,0,0)").find("Color("), -1,
		"purete: un commentaire qui PARLE d'une couleur n'en porte pas une")
	h.ok(Purete.code_seul("var c = Color(1,0,0)").find("Color(") >= 0,
		"purete: un vrai litteral est bien detecte")

	# ---------- REPERTOIRE DE DECOR PAR THEME ----------
	for nom in Pal.THEMES.keys():
		var kit: Array = Pal.decor(String(nom))
		h.gt(kit.size(), 1, "decor: le theme '%s' declare plusieurs elements" % str(nom))
		var formes := {}
		for d in kit:
			formes[int(d["forme"])] = true
			h.gt(int(d["poids"]), 0, "decor: '%s' — tout element a un poids positif" % str(nom))
		h.gt(formes.size(), 1, "decor: le theme '%s' melange plusieurs formes" % str(nom))
	h.eq(Pal.decor("theme_inexistant"), Pal.decor(Pal.THEME_DEFAUT),
		"decor: un theme inconnu retombe sur le defaut")
	# Deux themes ne racontent pas le meme lieu.
	h.ok(Pal.decor("foret") != Pal.decor("eau"), "decor: foret et eau ont des repertoires distincts")
	h.ok(Pal.decor("pierre") != Pal.decor("foret"), "decor: pierre et foret ont des repertoires distincts")
	# ASSERTION TAUTOLOGIQUE CORRIGEE (auto-detectee en regardant la capture, 2026-08-10) :
	# la version precedente testait `pose == "jouable"`, valeur qu'AUCUN kit ne porte. La
	# condition etait donc toujours fausse et l'assertion ne pouvait pas echouer. Un test
	# qui ne peut pas echouer compte comme vert et ne mesure rien.
	#
	# La regle REELLE : un element de decor ne partage jamais la COULEUR EXACTE d'un
	# power-up. Le decor vit hors de l'arene, donc une forme commune est tolerable ; une
	# teinte commune ne l'est pas, c'est elle qui fait chercher un bonus dans le decor.
	var couleurs_pu := {}
	for id in P.POWERUP_IDS:
		couleurs_pu[Pal.powerup(String(id))["couleur"]] = String(id)
	for nom in Pal.THEMES.keys():
		for d in Pal.decor(String(nom)):
			h.ok(not couleurs_pu.has(d["couleur"]),
				"decor: '%s' — aucun element ne porte la couleur exacte d'un power-up" % str(nom))
	# CONTROLE POSITIF de cette regle : la sonde detecte bien une collision fabriquee.
	h.ok(couleurs_pu.has(Pal.powerup(P.PU_FIRE_UP)["couleur"]),
		"decor: la table de couleurs de power-ups est bien peuplee (controle positif)")
	# ---------- discernabilite (oracle Snake) ----------
	h.eq(Pal.categories_couleur_partagee(), 0,
		"lisibilite: 0 paire de categories de gameplay partageant une couleur")
	h.eq(Pal.powerups_identite_partagee(), 0,
		"lisibilite: 0 paire de power-ups partageant couleur OU forme")
	h.eq(Pal.powerups_sans_identite(), [],
		"lisibilite: tout power-up du registre de REGLES a une identite visuelle")

	# ---------- IDENTITE DES 4 JOUEURS : couleur + SILHOUETTE (art-bible P1) ----------
	# LE TROU QUE CE VOLET FERME : `_identites_jouables()` posait `FORME_CUBE` EN DUR pour les
	# quatre acteurs. Leur silhouette n'etait consommee par AUCUNE verification.
	# Le canal est desormais porte par un PERSONNAGE 3D complet (un .glb par joueur) et non
	# plus par un couvre-chef pose sur un cube — approche rejetee au playtest.
	h.eq(Pal.acteurs_identite_partagee(), 0,
		"joueurs: 0 paire d'acteurs partageant couleur OU silhouette")
	h.eq(Pal.SILHOUETTES_ACTEURS.size(), Pal.ACTEURS.size(),
		"joueurs: une silhouette declaree par acteur (tableaux PARALLELES)")
	var couleurs_act := {}
	var formes_act := {}
	for ia in range(Pal.ACTEURS.size()):
		couleurs_act[Pal.ACTEURS[ia]] = true
		formes_act[Pal.silhouette_acteur(ia)] = true
	h.eq(couleurs_act.size(), Pal.ACTEURS.size(), "joueurs: une couleur par joueur")
	h.eq(formes_act.size(), Pal.ACTEURS.size(), "joueurs: une SILHOUETTE par joueur")

	# ---------- LES PERSONNAGES EXISTENT, SONT CHARGEABLES, ET SONT CONSOMMES ----------
	# Une preuve d'existence du .glb ne suffit pas : ce volet va jusqu'au chargement reel par
	# Godot et jusqu'a la table que le runtime consomme.
	const Vue3D = preload("res://06_RUNTIME/adapters/presentation_3d/arena_view_3d.gd")
	h.eq(Vue3D.MESHES_ACTEURS.size(), Pal.ACTEURS.size(),
		"personnages: un .glb declare par joueur")
	var vus := {}
	var sommets_par_perso := {}
	for ip in range(Vue3D.MESHES_ACTEURS.size()):
		var chemin: String = String(Vue3D.MESHES_ACTEURS[ip])
		vus[chemin] = true
		h.ok(ResourceLoader.exists(chemin),
			"personnages: %s existe et est importable par Godot" % chemin.get_file())
		var scn = load(chemin)
		h.ok(scn != null, "personnages: %s se charge reellement" % chemin.get_file())
		var noeud = scn.instantiate()
		var mailles: Array = noeud.find_children("*", "MeshInstance3D", true, false)
		h.gt(mailles.size(), 0, "personnages: %s porte au moins un mesh" % chemin.get_file())
		var m0: MeshInstance3D = mailles[0]
		# DEUX surfaces : corps + accent. C'est ce qui permet l'override PAR SURFACE, donc
		# une figurine bicolore au lieu d'un aplat d'une seule teinte.
		h.eq(m0.mesh.get_surface_count(), 2,
			"personnages: %s expose 2 surfaces (corps + accent)" % chemin.get_file())
		var aabb: AABB = m0.mesh.get_aabb()
		sommets_par_perso[chemin] = aabb.size
		# Tient dans sa case et ne masque pas un mur.
		h.ok(aabb.size.x <= Vue3D.TILE and aabb.size.z <= Vue3D.TILE,
			"personnages: %s tient dans une case (%.2f x %.2f)"
				% [chemin.get_file(), aabb.size.x, aabb.size.z])
		h.ok(aabb.size.y < 1.0,
			"personnages: %s reste sous la hauteur d'un mur (%.2f)"
				% [chemin.get_file(), aabb.size.y])
		# Pivot au pied : sinon la figurine s'enfonce dans le sol ou flotte au-dessus.
		h.ok(abs(aabb.position.y) < 0.02,
			"personnages: %s a son pivot au pied (min_y=%.4f)"
				% [chemin.get_file(), aabb.position.y])
		noeud.free()
	h.eq(vus.size(), Pal.ACTEURS.size(),
		"personnages: quatre .glb DISTINCTS — aucun joueur ne reutilise le mesh d'un autre")
	# MEME SET : meme gabarit general. Ecarts de hauteur faibles entre les quatre, sinon ce
	# sont quatre figurines choisies separement et non une escouade.
	var hmin: float = 9.0
	var hmax: float = 0.0
	for k in sommets_par_perso.keys():
		hmin = min(hmin, sommets_par_perso[k].y)
		hmax = max(hmax, sommets_par_perso[k].y)
	h.ok(hmax - hmin < 0.10,
		"personnages: meme gabarit — ecart de hauteur %.3f entre le plus petit et le plus grand"
			% (hmax - hmin))

	# CONSOMMATION REELLE PAR LE RUNTIME — le maillon que ni l'oracle de geometrie ni
	# l'existence du fichier ne prouvent. On fait tourner le VRAI chemin de rendu
	# (`batir` -> `rafraichir` -> `_acteur`) et on compte ce qui est reellement instancie.
	# Le repli de `_acteur` est une BoxMesh a UNE surface ; un personnage en porte DEUX.
	# Compter les noeuds a deux surfaces distingue donc mecaniquement « personnage instancie »
	# de « repli silencieux » — sans quoi un asset manquant passerait pour un asset consomme.
	var plan_r: Array = []
	for yr in range(9):
		var lr := ""
		for xr in range(9):
			if xr == 0 or yr == 0 or xr == 8 or yr == 8:
				lr += "#"
			elif (xr == 1 or xr == 7) and (yr == 1 or yr == 7):
				lr += "S"
			else:
				lr += "."
		plan_r.append(lr)
	var etat_r = Fx.etat({"id": "t_rt", "nom": "rt", "plan": plan_r, "powerup_rules": {},
		"victory_rule": P.VICTOIRE_LAST_STANDING}, 1, 4)
	var vue = Vue3D.new()
	vue.batir(etat_r, "pierre")
	var bicolores: int = 0
	for mi2 in vue.find_children("*", "MeshInstance3D", true, false):
		if mi2.mesh != null and mi2.mesh.get_surface_count() == 2:
			bicolores += 1
	h.eq(bicolores, 4,
		"runtime: les 4 personnages sont REELLEMENT instancies par le chemin de rendu")
	# Un acteur MORT reste dans la scene, aplati : l'ecran de resultat doit raconter le combat.
	etat_r.acteurs[1]["vivant"] = false
	vue.rafraichir(etat_r)
	var vivants_r: int = 0
	var aplatis_r: int = 0
	for mi3 in vue.find_children("*", "MeshInstance3D", true, false):
		if mi3.mesh == null or mi3.mesh.get_surface_count() != 2:
			continue
		var noeud_perso = mi3
		while noeud_perso.get_parent() != null and noeud_perso.get_parent() != vue._racine_dyn:
			noeud_perso = noeud_perso.get_parent()
		if noeud_perso.scale.y < 0.5:
			aplatis_r += 1
		else:
			vivants_r += 1
	h.eq(aplatis_r, 1, "runtime: l'acteur mort est APLATI, pas supprime")
	h.eq(vivants_r, 3, "runtime: les 3 survivants gardent leur taille normale")
	vue.free()

	# FALSIFICATION DU CONTROLE — deux entrees, MEME fonction, resultats opposes. Sans ce
	# volet, un controle toujours vert passerait pour une preuve.
	var reelles_act: Array = []
	var falsifie_act: Array = []
	for ib in range(Pal.ACTEURS.size()):
		reelles_act.append({"nom": "J%d" % ib, "couleur": Pal.ACTEURS[ib],
			"forme": Pal.silhouette_acteur(ib)})
		# Memes couleurs, une SEULE silhouette pour tous : le defaut qu'on veut voir rougir.
		falsifie_act.append({"nom": "F%d" % ib, "couleur": Pal.ACTEURS[ib],
			"forme": Pal.silhouette_acteur(0)})
	h.eq(Pal.identites_partagees(reelles_act), 0,
		"joueurs: CONTROLE POSITIF — les identites REELLES passent le controle")
	h.gt(Pal.identites_partagees(falsifie_act), 0,
		"joueurs: FALSIFICATION — deux joueurs a la MEME silhouette font echouer le controle")

	# VOCABULAIRES SEPARES : une silhouette d'acteur est un personnage 3D complet, jamais une
	# primitive de rendu. Les confondre reintroduirait le defaut « chapeau sur un cube ».
	for ic in range(Pal.ACTEURS.size()):
		var sa: int = Pal.silhouette_acteur(ic)
		h.gt(sa, Pal.FORME_NAPPE,
			"joueurs: la silhouette de J%d est hors du vocabulaire des primitives" % (ic + 1))

	# ---------- PULSATION DE MENACE : un canal de MOUVEMENT, pas une seconde teinte ----------
	var m0: Color = Pal.menace_pulsee(0)
	var m_mi: Color = Pal.menace_pulsee(Pal.MENACE_PERIODE_TICKS / 2)
	h.ok(m0.a != m_mi.a, "menace: l'opacite VARIE reellement au fil des ticks")
	h.eq(m0.r, Pal.MENACE.r, "menace: la pulsation ne touche pas le rouge")
	h.eq(m0.g, Pal.MENACE.g, "menace: la pulsation ne touche pas le vert")
	h.eq(m0.b, Pal.MENACE.b, "menace: la pulsation ne touche pas le bleu")
	h.eq(Pal.menace_pulsee(3), Pal.menace_pulsee(3 + Pal.MENACE_PERIODE_TICKS),
		"menace: fonction PURE et periodique du tick — deux rejeux rendent la meme image")
	var bornes_ok: bool = true
	for t2 in range(Pal.MENACE_PERIODE_TICKS * 2):
		var a2: float = Pal.menace_pulsee(t2).a
		if a2 < Pal.MENACE_ALPHA_MIN - 0.001 or a2 > Pal.MENACE_ALPHA_MAX + 0.001:
			bornes_ok = false
	h.ok(bornes_ok, "menace: l'opacite reste dans ses bornes declarees")
	h.gt(Pal.MENACE_ALPHA_MIN, 0.0,
		"menace: la pulsation ne rend JAMAIS le danger invisible")

	# ---------- FERMETURE : le TROISIEME etat, jamais fondu dans les deux autres ----------
	for nf in Pal.THEMES.keys():
		var fm: Dictionary = Pal.fermeture(String(nf))
		h.ok(int(fm["forme"]) != Pal.FORME_CUBE,
			"fermeture: '%s' n'est pas un cube recolore" % str(nf))
		h.ok(fm["couleur"] != Pal.MENACE and fm["couleur"] != Pal.FLAMME,
			"fermeture: '%s' ne porte ni la teinte MENACE ni la teinte FLAMME" % str(nf))
	h.eq(Pal.FERMETURES.size(), Pal.THEMES.size(),
		"fermeture: tout theme declare sa representation de fermeture")
	h.eq(Pal.fermeture("theme_inexistant"), Pal.fermeture(Pal.THEME_DEFAUT),
		"fermeture: un theme inconnu retombe sur le defaut, jamais sur une case invisible")
	var formes_fm := {}
	for nf2 in Pal.FERMETURES.keys():
		formes_fm[int(Pal.FERMETURES[String(nf2)]["forme"])] = true
	h.eq(formes_fm.size(), Pal.FERMETURES.size(),
		"fermeture: une forme distincte par theme — la representation thematique est reelle")
	h.ok(Pal.H_FERMETURE < 1.0,
		"fermeture: plus basse qu'un mur permanent — les deux ne se lisent pas pareil")
	h.gt(Pal.H_FERMETURE, 0.06,
		"fermeture: nettement plus haute que la dalle MENACE")

	# Trois canaux reellement distincts, verifies un par un.
	var couleurs := {}
	var formes := {}
	var hauteurs := {}
	for id in P.POWERUP_IDS:
		var d: Dictionary = Pal.powerup(String(id))
		couleurs[d["couleur"]] = true
		formes[int(d["forme"])] = true
		hauteurs[float(d["hauteur"])] = true
	h.eq(couleurs.size(), P.POWERUP_IDS.size(), "lisibilite: une couleur par power-up")
	h.eq(formes.size(), P.POWERUP_IDS.size(), "lisibilite: une forme par power-up")
	h.eq(hauteurs.size(), P.POWERUP_IDS.size(), "lisibilite: une hauteur par power-up")

	# Un power-up hors registre reste VISIBLE (magenta) : un defaut doit crier.
	var inconnu: Dictionary = Pal.powerup("PAS_UN_POWERUP")
	h.ok(inconnu["couleur"] != Pal.DESTRUCTIBLE[0], "lisibilite: un identifiant inconnu ne disparait pas")

	# ---------- identite des cartes ----------
	h.gt(Pal.THEMES.size(), 1, "lisibilite: plusieurs themes declares")
	var sols := {}
	for nom in Pal.THEMES.keys():
		sols[Pal.theme(String(nom))["sol"]] = true
	h.eq(sols.size(), Pal.THEMES.size(), "lisibilite: chaque theme a une couleur de sol distincte")
	h.eq(Pal.theme("theme_inexistant"), Pal.theme(Pal.THEME_DEFAUT),
		"lisibilite: un theme inconnu retombe sur le defaut, jamais sur une carte invisible")

	# ---------- telegraphe de danger ----------
	var s = Fx.etat(Fx.desc_vide(), 1, 2)
	h.eq(Explosion.zone_menacee(s).size(), 0, "danger: aucune bombe -> aucune zone menacee")
	s.bombes.append({"proprietaire": 0, "cellule": Vector2i(4, 4), "meche": 50, "rayon": 2})
	var z: Dictionary = Explosion.zone_menacee(s)
	h.eq(z.size(), 9, "danger: la zone annoncee est la croix complete (1 + 4x2)")
	h.ok(z.has(Vector2i(4, 4)), "danger: le centre est annonce")
	h.ok(z.has(Vector2i(4, 6)) and z.has(Vector2i(2, 4)), "danger: les bras sont annonces")
	h.ok(not z.has(Vector2i(5, 5)), "danger: aucune diagonale annoncee")

	# La zone annoncee COINCIDE avec ce qui brulera reellement : un telegraphe qui ment est
	# pire que pas de telegraphe.
	var r: Dictionary = Explosion.resoudre(s, [0])
	var reelles: Array = r["flammes"].duplicate()
	reelles.sort()
	var annoncees: Array = z.keys()
	annoncees.sort()
	h.eq(annoncees, reelles, "danger: la zone ANNONCEE est exactement la zone qui brulera")

	# Un mur borne l'annonce comme il borne la flamme.
	var s2 = Fx.etat(Fx.desc_vide(), 1, 2)
	s2.bombes.append({"proprietaire": 0, "cellule": Vector2i(1, 1), "meche": 50, "rayon": 5})
	var z2: Dictionary = Explosion.zone_menacee(s2)
	h.ok(not z2.has(Vector2i(0, 1)), "danger: l'annonce n'entre pas dans le mur")

	# `zone_menacee` est PURE : elle ne modifie ni l'arene ni les bombes.
	var avant_bombes: int = s2.bombes.size()
	var avant_blocs: int = s2.arene.nb_destructibles()
	Explosion.zone_menacee(s2)
	h.eq(s2.bombes.size(), avant_bombes, "danger: zone_menacee ne consomme aucune bombe")
	h.eq(s2.arene.nb_destructibles(), avant_blocs, "danger: zone_menacee ne detruit rien")

	# ---------- retour de ramassage ----------
	h.eq(Shell.libelle_ramassage(P.PU_BOMB_UP, true), "BOMBE +1", "feedback: libelle BOMB_UP")
	h.eq(Shell.libelle_ramassage(P.PU_FIRE_UP, true), "PORTEE +1", "feedback: libelle FIRE_UP")
	h.eq(Shell.libelle_ramassage(P.PU_SPEED_UP, true), "VITESSE +", "feedback: libelle SPEED_UP")
	var libelles := {}
	for id in P.POWERUP_IDS:
		libelles[Shell.libelle_ramassage(String(id), true)] = true
	h.eq(libelles.size(), P.POWERUP_IDS.size(), "feedback: un libelle DISTINCT par power-up")
	h.ok(Shell.libelle_ramassage(P.PU_FIRE_UP, false).find("maximum") >= 0,
		"feedback: un ramassage SANS effet le dit, au lieu d'annoncer un gain qui n'a pas eu lieu")
	h.ok(Shell.libelle_ramassage(P.PU_FIRE_UP, false) != Shell.libelle_ramassage(P.PU_FIRE_UP, true),
		"feedback: avec et sans effet ne se lisent pas pareil")

	# ---------- LEGENDE : le joueur peut comprendre AVANT de mourir ----------
	var leg: Array = Shell.legende()
	h.eq(leg.size(), P.POWERUP_IDS.size(), "legende: une ligne par power-up du registre de REGLES")
	var vues := {}
	for l in leg:
		vues[String(l)] = true
		h.gt(String(l).length(), 8, "legende: '%s' est une phrase, pas un sigle" % str(l))
	h.eq(vues.size(), leg.size(), "legende: aucune ligne dupliquee")
	var formes_nommees := {}
	for id in P.POWERUP_IDS:
		formes_nommees[Shell.nom_forme(int(Pal.powerup(String(id))["forme"]))] = true
	h.eq(formes_nommees.size(), P.POWERUP_IDS.size(), "legende: un NOM DE FORME distinct par power-up")

	# ---------- HUD COMPACT PAR JOUEUR : indexe par JOUEUR, jamais par position ----------
	# Fonctions PURES, donc prouvables sans moteur ni rendu — meme discipline que
	# `libelle_ramassage`. Ce volet existe parce qu'un HUD « implemente » sans preuve reste
	# une intention : rien ne garantirait que les quatre joueurs y figurent vraiment.
	# Descripteur A QUATRE SPAWNS, local a ce volet : `Fx.desc_vide()` n'en porte que deux et
	# ne pourrait donc pas prouver une bande de quatre joueurs. Construit ici plutot qu'ajoute
	# a la fixture partagee — les autres tests n'ont pas a changer pour celui-ci.
	var plan4: Array = []
	for y4 in range(9):
		var l4 := ""
		for x4 in range(9):
			if x4 == 0 or y4 == 0 or x4 == 8 or y4 == 8:
				l4 += "#"
			elif (x4 == 1 or x4 == 7) and (y4 == 1 or y4 == 7):
				l4 += "S"
			else:
				l4 += "."
		plan4.append(l4)
	var desc4: Dictionary = {
		"id": "t_quatre", "nom": "quatre", "plan": plan4,
		"powerup_rules": {}, "victory_rule": P.VICTOIRE_LAST_STANDING,
	}
	var sh = Fx.etat(desc4, 1, 4)
	h.eq(sh.acteurs.size(), 4, "hud: CONTROLE POSITIF — le scenario porte bien 4 joueurs")
	var bande: String = Shell.bande_joueurs(sh, false)
	for ij in range(4):
		h.ok(bande.find("J%d" % (ij + 1)) >= 0,
			"hud: la bande porte une zone pour J%d" % (ij + 1))
	# Un joueur ELIMINE garde sa zone : une case qui disparait decale les autres et fait
	# perdre son repere a chaque survivant.
	sh.acteurs[2]["vivant"] = false
	var bande_mort: String = Shell.bande_joueurs(sh, false)
	h.ok(bande_mort.find("J3") >= 0, "hud: un joueur elimine CONSERVE sa zone")
	h.ok(bande_mort.find(Shell.MARQUE_MORT) >= 0, "hud: l'elimination porte une marque propre")
	h.ok(bande_mort != bande, "hud: vivant et elimine ne se lisent pas pareil")

	# INDEXE PAR JOUEUR, PAS PAR POSITION : deplacer tout le monde ne change pas la bande.
	# C'est la propriete qui distingue un reperage d'un affichage flottant.
	var avant_deplacement: String = Shell.bande_joueurs(sh, false)
	for id3 in range(sh.acteurs.size()):
		sh.acteurs[id3]["cellule"] = Vector2i(1, 1)
	h.eq(Shell.bande_joueurs(sh, false), avant_deplacement,
		"hud: la bande est indexee par JOUEUR — deplacer les acteurs ne la change pas")

	# MEME systeme en pause, seul `detaille` change. Pas de seconde architecture de HUD.
	var detail: String = Shell.bande_joueurs(sh, true)
	h.ok(detail != Shell.bande_joueurs(sh, false),
		"hud: le mode detaille (pause) differe du mode compact (en jeu)")
	for ik in range(4):
		h.ok(detail.find("J%d" % (ik + 1)) >= 0,
			"hud: le detail de pause porte aussi J%d" % (ik + 1))
	h.eq(Shell.bande_joueurs(null, false), "",
		"hud: sans partie, la bande se tait au lieu d'inventer des joueurs")

	# La VITESSE est enfin lisible : le cooldown DECROIT quand on accelere, l'afficher tel
	# quel se lirait a l'envers.
	h.eq(Shell.niveau_vitesse(P.MOVE_COOLDOWN_BASE), 1, "hud: vitesse initiale = niveau 1")
	h.gt(Shell.niveau_vitesse(P.MOVE_COOLDOWN_BASE - P.SPEED_STEP),
		Shell.niveau_vitesse(P.MOVE_COOLDOWN_BASE),
		"hud: un SPEED_UP fait MONTER le niveau affiche, alors que le cooldown descend")

	# ---------- LISIBILITE DE LA GRILLE (patron pacman : dessiner CASE PAR CASE) ----------
	#
	# PREUVE MECANIQUE SEULE, ET C'EST UNE MESURE, PAS UN RENONCEMENT.
	# J'ai ecrit un volet pixel (`07_TESTS/oracle/lisibilite_grille.gd`) puis je l'ai RETIRE
	# apres falsification : il restait VERT sur un damier neutralise. Deux causes mesurees,
	# dans cet ordre de decouverte :
	#   (1) il echantillonnait la rangee y=6, or les piliers sont en x PAIR et y PAIR — il
	#       comparait donc sol contre MUR (ecart 0,745, faux positif franc). Corrige.
	#   (2) corrige, il mesurait encore 0,196 d'ecart sur l'etat CASSE contre 0,084 sur
	#       l'etat SAIN : signal INVERSE. Les ombres portees des piliers voisins dominent
	#       l'albedo du damier d'un ordre de grandeur.
	# Un seuil qui ferait passer ce volet serait un seuil ajuste au resultat voulu. La
	# propriete reste donc prouvee ici, mecaniquement, et la verification PIXEL du damier
	# est NOT_MEASURED — pas OK.
	for nom in Pal.THEMES.keys():
		var th: Dictionary = Pal.theme(String(nom))
		h.ok(th.has("sol_alt"), "grille: le theme '%s' declare une seconde teinte de sol" % str(nom))
		var d1: float = abs(Pal.luminance(th["sol"]) - Pal.luminance(th["sol_alt"]))
		h.ok(d1 >= Pal.ECART_LUMINANCE_MIN,
			"grille: '%s' — les deux teintes de sol se distinguent (ecart %.3f)" % [str(nom), d1])
		var d2: float = abs(Pal.luminance(th["sol"]) - Pal.luminance(th["mur"]))
		h.ok(d2 >= Pal.ECART_LUMINANCE_MIN,
			"grille: '%s' — sol et mur se distinguent (ecart %.3f)" % [str(nom), d2])
	# Le damier ALTERNE reellement : deux cases voisines n'ont pas la meme teinte.
	for nom2 in Pal.THEMES.keys():
		h.ok(Pal.sol_de(String(nom2), Vector2i(4, 4)) != Pal.sol_de(String(nom2), Vector2i(5, 4)),
			"grille: '%s' — deux cases VOISINES different" % str(nom2))
		h.eq(Pal.sol_de(String(nom2), Vector2i(4, 4)), Pal.sol_de(String(nom2), Vector2i(6, 4)),
			"grille: '%s' — deux cases de meme parite sont identiques (c'est un damier)" % str(nom2))
	# CONTROLE POSITIF de la mesure d'ecart : deux teintes identiques doivent donner 0.
	h.eq(Pal.luminance(Pal.BOMBE) - Pal.luminance(Pal.BOMBE), 0.0,
		"grille: la mesure de luminance rend 0 sur deux teintes identiques (controle positif)")
	h.gt(Pal.luminance(Pal.UI_TITRE), Pal.luminance(Pal.BOMBE),
		"grille: la mesure ordonne bien clair et sombre")

	# ---------- PATCH : routage vs letalite (bug graine 1, acteur 1, t=688) ----------
	# Le bot ne doit JAMAIS poser le pied sur une case qui brule, meme si cette case est sa
	# cible de routage. L'exemption de cible sert a CALCULER une route, pas a survivre.
	const BotL = preload("res://06_RUNTIME/adapters/solvability_bot/bot_policy.gd")
	var sp1 = Fx.etat(Fx.desc_vide(), 1, 2)
	sp1.acteurs[0]["cellule"] = Vector2i(4, 4)
	sp1.acteurs[1]["cellule"] = Vector2i(2, 4)      # ennemi = cible de routage
	sp1.flammes[Vector2i(3, 4)] = P.DUREE_FLAMME    # la case INTERMEDIAIRE brule
	sp1.flammes_auteur[Vector2i(3, 4)] = 1
	var act1: int = BotL.decider(sp1, 0, true)
	h.ok(act1 != P.GAUCHE,
		"patch: le bot ne marche PAS vers une case en flammes, meme sur la route de sa cible")

	# La cible elle-meme en flammes : meme exigence.
	var sp2 = Fx.etat(Fx.desc_vide(), 1, 2)
	sp2.acteurs[0]["cellule"] = Vector2i(4, 4)
	sp2.acteurs[1]["cellule"] = Vector2i(3, 4)
	sp2.flammes[Vector2i(3, 4)] = P.DUREE_FLAMME
	sp2.flammes_auteur[Vector2i(3, 4)] = 1
	h.ok(BotL.decider(sp2, 0, true) != P.GAUCHE,
		"patch: le bot ne marche pas sur sa CIBLE quand elle brule")

	# CONTROLE POSITIF, sans lequel les deux assertions ci-dessus seraient vides : sans
	# flamme, le bot avance BIEN vers la meme cible. Le patch bloque le danger, pas le jeu.
	var sp3 = Fx.etat(Fx.desc_vide(), 1, 2)
	sp3.acteurs[0]["cellule"] = Vector2i(4, 4)
	sp3.acteurs[1]["cellule"] = Vector2i(2, 4)
	h.eq(BotL.decider(sp3, 0, true), P.GAUCHE,
		"patch: SANS flamme, le bot avance vers sa cible (controle positif)")

	# L'exemption de cible est CONSERVEE : un ennemi reste atteignable en routage.
	h.gt(BotL.nb_cases_sures(sp3, 0, {}), 0, "patch: le bot garde un espace vital calculable")
