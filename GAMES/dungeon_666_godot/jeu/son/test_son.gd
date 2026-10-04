extends SceneTree
## Oracle headless du son de Dungeon 666 (version Godot).
##   <godot> --headless --path . --script res://jeu/son/test_son.gd
## Sortie 0 = tout vert, 1 = au moins un rouge. Pendant de GAMES/dungeon_666/tests/audio.test.mjs.
##
## Ce que l'oracle prouve : chaque événement de la simulation a une décision sonore, chaque
## recette se rend en un son sain, la polyphonie est bornée, le son coupé ne joue rien, une
## partie entière ne casse rien. Il ne prouve PAS que les sons sont beaux : personne ne les a
## écoutés ici (voir exporter_planche.gd).

const SceneSon = preload("res://jeu/son/son.tscn")
const Recettes = preload("res://jeu/son/recettes.gd")
const Routage = preload("res://jeu/son/routage.gd")

const TYPES_MIN := 30 # garde anti-faux-vert : la lecture de sim/ doit trouver les événements
const DUREE_MIN := 0.02 # s
const DUREE_MAX := 3.0
const PCM_MAX := 32767.0
const RAFALE := 200
const PAS_DE_PARTIE := 1800
const ETAGES := [7.0, 18.0]
const MENUS_MAX := 400
const ATTENTE_RENDU_S := 180.0
const IMAGE_MAX_MS := 100.0 # une image plus longue pendant le rendu serait un gel visible

class FausseAppli:
	extends Node
	signal reglages_change
	var reglages := {"sound": true, "haptics": true}

class FaussePartie:
	extends Node
	signal evenements(liste: Array)
	signal partie_demarree
	var game = null

var _fails := 0
var _checks := 0
var _app: FausseAppli
var _partie: FaussePartie
var _vibrations: Array = []

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  ok   — ", label)
	else:
		_fails += 1
		print("  ROUGE — ", label)

func _initialize() -> void:
	_derouler()

func _derouler() -> void:
	_routage()
	var son := _nouveau_son(false, false)
	await process_frame # la scène n'est prête (_ready) qu'une fois l'arbre lancé
	_recettes(son)
	_polyphonie(son)
	_groupes(son)
	_coupure(son)
	_vibrer(son)
	for etage in ETAGES:
		_partie_entiere(son, etage)
	son.free()
	await _rendu_etale(false)
	await _rendu_etale(true)
	_liberer_faux()
	await create_timer(0.2).timeout # le moteur audio rend les sons arrêtés avant la sortie
	print("%d vérifications, %d rouges" % [_checks, _fails])
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)

func _liberer_faux() -> void:
	if _app != null:
		_app.free()
		_partie.free()
	_app = null
	_partie = null

func _nouveau_son(rendu_auto: bool, sans_fil: bool) -> Node:
	_liberer_faux()
	_app = FausseAppli.new()
	_partie = FaussePartie.new()
	var son := SceneSon.instantiate()
	son.rendu_auto = rendu_auto
	son.sans_fil = sans_fil
	root.add_child(son)
	son.brancher(_app, _partie)
	son.vibration.connect(func(ms): _vibrations.append(ms))
	return son

func _image(son: Node, liste: Array) -> void:
	_partie.evenements.emit(liste)
	son.avancer_horloge(1.0 / 60.0)

# ---------------------------------------------------------------- 1. routage

func _routage() -> void:
	print("[routage] chaque événement de la simulation est routé ou silencieux à dessein")
	var types := _types_de_la_simulation()
	_ok(types.size() > TYPES_MIN, "événements lus dans sim/ : %d (minimum %d)" % [types.size(), TYPES_MIN])
	var sans_decision := types.filter(func(t): return not Routage.connu(t))
	_ok(sans_decision.is_empty(), "aucun événement de sim sans décision sonore %s" % str(sans_decision))
	var doubles := Routage.types_routes().filter(func(t): return Routage.SILENCIEUX.has(t))
	_ok(doubles.is_empty(), "aucun événement à la fois routé et silencieux %s" % str(doubles))
	var connues: Array = Recettes.noms()
	var utilisees := {}
	for cle in _cles_routees():
		_ok(Routage.SONS.has(cle), "son « %s » : règles de mixage présentes" % cle)
		var recettes: Array = Routage.recettes_de(cle)
		var absentes := recettes.filter(func(r): return not connues.has(r))
		_ok(not recettes.is_empty() and absentes.is_empty(), "son « %s » : %d recette(s), toutes existantes %s" % [cle, recettes.size(), str(absentes)])
		for r in recettes:
			utilisees[r] = true
	var orphelines := connues.filter(func(r): return not utilisees.has(r) and not Routage.RECETTES_ECRANS.has(r))
	_ok(orphelines.is_empty(), "aucune recette orpheline %s" % str(orphelines))
	_echantillons_routes()

func _types_de_la_simulation() -> Array:
	var motif := RegEx.new()
	motif.compile("emit\\(game, \"([A-Za-z]+)\"")
	var types := {}
	for fichier in DirAccess.get_files_at("res://sim"):
		if not fichier.ends_with(".gd"):
			continue
		for m in motif.search_all(FileAccess.get_file_as_string("res://sim/" + fichier)):
			types[m.get_string(1)] = true
	return types.keys()

func _cles_routees() -> Array:
	var cles := {}
	for type in Routage.ROUTES:
		cles[Routage.ROUTES[type]] = true
	for type in Routage.ROUTES_CALCULEES:
		for cle in Routage.ROUTES_CALCULEES[type]:
			cles[cle] = true
	return cles.keys()

## Chaque événement échantillon mène à des recettes déclarées ; ensemble ils les atteignent toutes.
func _echantillons_routes() -> void:
	var connues: Array = Recettes.noms()
	var atteintes := {}
	var types_vus := {}
	var fautes: Array = []
	for ev in _echantillons():
		types_vus[ev.type] = true
		var cle: String = Routage.cle(ev)
		if cle == "":
			fautes.append("%s : silencieux" % ev.type)
			continue
		var parties: Array = Routage.parties(cle, ev, Routage.coup_lourd(ev, 2.0), 1.0)
		if parties.is_empty():
			fautes.append("%s : aucune recette" % ev.type)
		for p in parties:
			atteintes[p[0]] = true
			if not connues.has(p[0]) or not Routage.recettes_de(cle).has(p[0]) or not (p[1] > 0.0) or not (p[2] > 0.0):
				fautes.append("%s -> %s" % [ev.type, str(p)])
	_ok(fautes.is_empty(), "chaque événement échantillon donne des recettes déclarées, hauteur et gain > 0 %s" % str(fautes))
	var non_testes := Routage.types_routes().filter(func(t): return not types_vus.has(t))
	_ok(non_testes.is_empty(), "chaque type routé a son échantillon %s" % str(non_testes))
	var jamais := connues.filter(func(r): return not atteintes.has(r) and not r.begins_with("eclair_") and not Routage.RECETTES_ECRANS.has(r))
	_ok(jamais.is_empty(), "chaque recette est atteinte par un échantillon %s" % str(jamais))

# ---------------------------------------------------------------- 2. recettes

func _recettes(son: Node) -> void:
	print("[recettes] chaque recette se rend en un son sain")
	var ms: float = son.rendre_tout()
	var sons: Dictionary = son.sons_rendus()
	_ok(son.est_pret() and sons.size() == Recettes.noms().size(), "%d recettes rendues en %.0f ms, %.2f Mo en mémoire" % [sons.size(), ms, son.memoire_octets() / 1048576.0])
	var total := 0.0
	for nom in Recettes.noms():
		if not sons.has(nom):
			_ok(false, "%s : non rendue" % nom)
			continue
		var m := _mesurer(sons[nom])
		total += m.duree
		var sain: bool = m.n > 0 and m.energie > 0.0 and m.crete <= 1.0 and m.crete > 0.5 and m.duree >= DUREE_MIN and m.duree <= DUREE_MAX
		sain = sain and is_finite(sons[nom].niveau) and sons[nom].niveau > 0.0 and absf(m.duree - sons[nom].duree) < 0.001
		_ok(sain, "%s : %.3f s, crête %.2f, énergie %.3f, niveau %.2f" % [nom, m.duree, m.crete, m.energie, sons[nom].niveau])
	print("  durée cumulée des sons : %.1f s" % total)

## Mesure le son tel qu'il sera joué : les échantillons 16 bits du flux.
func _mesurer(son: Dictionary) -> Dictionary:
	var flux: AudioStreamWAV = son.flux
	var octets := flux.data
	var n := octets.size() / 2
	var crete := 0.0
	var somme := 0.0
	for i in n:
		var v := octets.decode_s16(i * 2) / PCM_MAX
		crete = maxf(crete, absf(v))
		somme += v * v
	var mono16: bool = flux.format == AudioStreamWAV.FORMAT_16_BITS and not flux.stereo
	return {"n": n if mono16 else 0, "crete": crete, "energie": sqrt(somme / maxi(1, n)), "duree": n / float(flux.mix_rate)}

# ---------------------------------------------------------------- 3. polyphonie

func _polyphonie(son: Node) -> void:
	print("[polyphonie] bornée par son et au total")
	var coup := {"type": "hit", "x": 520.0, "y": 400.0, "amount": 10.0, "kind": "melee", "enemy": "imp"}
	for i in 10:
		_partie.evenements.emit([coup])
	_ok(son.voix_de("hit") == 4, "10 coups en 10 images : 4 voix (plafond du son), obtenu %d" % son.voix_de("hit"))
	var echantillons := _echantillons()
	var rafale: Array = []
	for i in RAFALE:
		rafale.append(echantillons[i % echantillons.size()])
	var avant: int = son.stats.abandonnes
	_partie.evenements.emit(rafale)
	for i in 10:
		_partie.evenements.emit(echantillons)
	var voix: int = son.nombre_de_voix()
	_ok(son.stats.abandonnes > avant, "rafale de %d événements : des sons sont refusés (%d)" % [RAFALE, son.stats.abandonnes - avant])
	_ok(voix <= son.VOIX_MAX, "voix en cours ≤ %d : %d" % [son.VOIX_MAX, voix])
	_ok(voix >= son.VOIX_MAX - son.RESERVE_VITALE, "la réserve vitale reste utilisable : %d voix" % voix)
	_ok(son.lecteurs_actifs() <= son.VOIX_MAX and son.lecteurs_actifs() > 0, "lecteurs qui jouent : %d (entre 1 et %d)" % [son.lecteurs_actifs(), son.VOIX_MAX])
	_ok(son.find_children("*", "AudioStreamPlayer", true, false).size() == son.VOIX_MAX, "le réservoir compte %d lecteurs, aucun de plus" % son.VOIX_MAX)
	var debordements: Array = []
	for cle in Routage.SONS:
		if son.voix_de(cle) > Routage.SONS[cle].voix:
			debordements.append(cle)
	_ok(debordements.is_empty(), "aucun son au-dessus de son plafond de voix %s" % str(debordements))
	_ok(son.stats.manquantes == 0 and son.stats.pas_prets == 0, "aucune recette manquante ni pas prête")
	son.avancer_horloge(10.0)
	_ok(son.nombre_de_voix() == 0, "toutes les voix se libèrent avec le temps")

func _groupes(son: Node) -> void:
	print("[regroupement] une image = des événements groupés par son")
	var coups: Array = []
	for i in 6:
		coups.append({"type": "hit", "x": 520.0, "y": 400.0, "amount": 10.0 + i, "crit": i == 1, "kind": "melee", "enemy": "imp"})
	var joues: int = son.stats.joues
	var fusionnes: int = son.stats.fusionnes
	_image(son, coups)
	_ok(son.stats.joues - joues == 2 and son.stats.fusionnes - fusionnes == 4, "6 coups dans la même image : 2 sons, 4 fusionnés")
	son.avancer_horloge(10.0)
	joues = son.stats.joues
	_image(son, [
		{"type": "hazard", "id": 7.0, "kind": "exploder", "x": 600.0, "y": 400.0},
		{"type": "explode", "id": 7.0, "x": 600.0, "y": 400.0, "r": 90.0},
		{"type": "hazardFire", "id": 7.0, "kind": "exploder", "shape": "circle", "x": 600.0, "y": 400.0, "r": 90.0},
	])
	_ok(son.stats.joues - joues == 1, "explosion de possédé : explode + hazardFire(exploder) = un seul boum")
	son.avancer_horloge(10.0)
	joues = son.stats.joues
	_image(son, [
		null, 42, {"sans": "type"},
		{"type": "hit", "amount": NAN, "x": "a", "crit": "oui"},
		{"type": "swing", "index": 7.4, "strike": false},
		{"type": "hazardFire", "kind": "mystère", "r": -50.0},
		{"type": "equip", "rarity": null},
		{"type": "boonGain"},
		{"type": "inconnu"},
	])
	_ok(son.stats.joues - joues == 5, "événements mal formés : 5 sons joués sans erreur, obtenu %d" % (son.stats.joues - joues))
	_ok(son.stats.inconnus.keys() == ["inconnu"], "un type inconnu est compté, pas joué : %s" % str(son.stats.inconnus))
	son.stats.inconnus.clear()
	son.avancer_horloge(10.0)
	_ok(son.jouer("clic") and not son.jouer("recette_qui_n_existe_pas"), "jouer(\"clic\") joue ; une recette inconnue ne joue pas")
	son.stats.manquantes = 0
	son.avancer_horloge(10.0)

# ---------------------------------------------------------------- 4. réglages

func _coupure(son: Node) -> void:
	print("[réglages] son coupé = aucun lecteur ne joue")
	_image(son, _echantillons())
	_ok(son.lecteurs_actifs() > 0, "son ouvert : des lecteurs jouent (%d)" % son.lecteurs_actifs())
	var joues: int = son.stats.joues
	_app.reglages.sound = false
	_app.reglages_change.emit()
	_ok(son.lecteurs_actifs() == 0 and son.nombre_de_voix() == 0, "couper le son arrête tout de suite les lecteurs")
	_image(son, _echantillons())
	var muet_clic: bool = son.jouer("clic")
	_ok(son.stats.joues == joues and not muet_clic and son.lecteurs_actifs() == 0, "son coupé : rien n'est lancé, aucun lecteur ne joue")
	_app.reglages.sound = true
	_app.reglages_change.emit()
	son.avancer_horloge(10.0)
	_image(son, [{"type": "dash", "x": 500.0, "y": 400.0}])
	_ok(son.stats.joues == joues + 1, "son rouvert : le son revient")
	son.avancer_horloge(10.0)

func _vibrer(son: Node) -> void:
	print("[vibrations] durées par événement, une par image, réglage respecté")
	_vibrations.clear()
	var images := [
		[{"type": "playerHurt", "x": 500.0, "y": 400.0, "amount": 10.0}, {"type": "dodge", "x": 500.0, "y": 400.0}],
		[{"type": "dodge", "x": 500.0, "y": 400.0}],
		[{"type": "swing", "index": 2.0, "x": 500.0, "y": 400.0}, {"type": "hit", "kind": "melee", "amount": 22.0, "x": 520.0, "y": 400.0}],
		[{"type": "swing", "index": 0.0, "x": 500.0, "y": 400.0}, {"type": "hit", "kind": "melee", "amount": 10.0, "x": 520.0, "y": 400.0}],
		[{"type": "hit", "kind": "strike", "amount": 18.0, "x": 520.0, "y": 400.0}],
		[{"type": "kill", "boss": true, "x": 520.0, "y": 400.0}],
		[{"type": "bossPhase", "x": 520.0, "y": 400.0}],
	]
	for image in images:
		_partie.evenements.emit(image)
		son.avancer_horloge(1.0)
	_ok(_vibrations == [40, 8, 12, 12, 80, 80], "blessure 40, esquive 8, coup lourd 12, Gardien 80 : %s" % str(_vibrations))
	_vibrations.clear()
	_partie.evenements.emit([{"type": "bossPhase", "x": 0.0, "y": 0.0}])
	son.avancer_horloge(0.01)
	_partie.evenements.emit([{"type": "dodge", "x": 0.0, "y": 0.0}])
	son.avancer_horloge(0.01)
	_partie.evenements.emit([{"type": "kill", "boss": true, "x": 0.0, "y": 0.0}])
	_ok(_vibrations == [80], "une vibration faible ou égale n'interrompt pas celle en cours : %s" % str(_vibrations))
	son.avancer_horloge(1.0)
	_vibrations.clear()
	_app.reglages.haptics = false
	_app.reglages_change.emit()
	_partie.evenements.emit([{"type": "playerHurt", "x": 500.0, "y": 400.0, "amount": 10.0}])
	_ok(_vibrations.is_empty(), "vibrations coupées : aucune")
	_app.reglages.haptics = true
	_app.reglages_change.emit()
	son.avancer_horloge(10.0)

# ---------------------------------------------------------------- 5. partie entière

func _partie_entiere(son: Node, etage: float) -> void:
	print("[partie] étage %s, %d pas joués par un pilote simple" % [D6Js.num_str(etage), PAS_DE_PARTIE])
	var g: Dictionary = D6Game.create_game({"seed": 666.0, "startFloor": etage})
	_partie.game = g
	_partie.partie_demarree.emit()
	var joues: int = son.stats.joues
	var vus := {}
	var pas := 0
	var menus := 0
	while pas < PAS_DE_PARTIE and menus < MENUS_MAX:
		if g.mode == "play":
			D6Game.step_game(g, _piloter(g, pas))
			pas += 1
		elif not _sortir_du_menu(g):
			break
		else:
			menus += 1
		var liste: Array = g.events.duplicate()
		g.events.clear()
		for ev in liste:
			vus[ev.type] = true
		_image(son, liste)
	_partie.game = null
	_ok(pas == PAS_DE_PARTIE, "la partie va au bout : %d pas, %d menus, mode final « %s »" % [pas, menus, g.mode])
	_ok(son.stats.inconnus.is_empty(), "aucun événement inconnu du son %s" % str(son.stats.inconnus))
	_ok(son.stats.manquantes == 0 and son.stats.pas_prets == 0, "aucune recette manquante ni pas prête")
	_ok(son.stats.joues - joues > 20, "sons joués : %d" % (son.stats.joues - joues))
	_ok(vus.has("swing") and vus.has("hit"), "le pilote se bat (swing, hit) ; %d types vus : %s" % [vus.size(), ", ".join(vus.keys())])
	_ok(son.nombre_de_voix() <= son.VOIX_MAX, "polyphonie bornée en fin de partie : %d voix" % son.nombre_de_voix())
	son.stats.inconnus.clear()
	son.avancer_horloge(10.0)

## Va vers l'ennemi le plus proche et frappe ; dash, compétence et gadget périodiques ; l'attaque
## est tenue : l'ultime part de lui-même quand la jauge est pleine (combat V3).
func _piloter(g: Dictionary, pas: int) -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	var cible = null
	var d_min := INF
	for e in g.enemies:
		if D6Js.truthy(e.get("dead")) or e.get("spawnT", 0.0) > 0.0:
			continue
		var d := Vector2(e.x - g.player.x, e.y - g.player.y).length_squared()
		if d < d_min:
			d_min = d
			cible = e
	if cible != null:
		var v := Vector2(cible.x - g.player.x, cible.y - g.player.y)
		if v.length() > 70.0:
			input.moveX = v.normalized().x
			input.moveY = v.normalized().y
	input.attack = true
	input.attackPressed = pas % 12 == 0
	input.dashPressed = pas % 50 == 25
	input.skill1Pressed = pas % 240 == 100
	input.skill2Pressed = pas % 400 == 200
	return input

func _sortir_du_menu(g: Dictionary) -> bool:
	var commandes: Array = []
	match g.mode:
		"choice":
			commandes = [{"type": "choose", "index": 0.0}, {"type": "equip"}, {"type": "close"}]
		"dead":
			commandes = [{"type": "respawn", "floor": D6Run.last_checkpoint(g)}]
	for cmd in commandes:
		if D6Js.truthy(D6Game.apply_command(g, cmd)):
			return true
	return false

# ---------------------------------------------------------------- 6. rendu au démarrage

## Le rendu de démarrage (fil d'exécution, ou étalé sur les images) aboutit sans geler l'image.
func _rendu_etale(sans_fil: bool) -> void:
	var mode := "étalé sur les images (sans fil)" if sans_fil else "dans un fil d'exécution"
	print("[démarrage] rendu %s" % mode)
	var son := _nouveau_son(true, sans_fil)
	var depart := Time.get_ticks_msec()
	var avant := Time.get_ticks_usec()
	var pire := 0.0
	var images := 0
	while not son.est_pret() and Time.get_ticks_msec() - depart < ATTENTE_RENDU_S * 1000.0:
		await process_frame
		var t := Time.get_ticks_usec()
		pire = maxf(pire, (t - avant) / 1000.0)
		avant = t
		images += 1
	_ok(son.est_pret(), "toutes les recettes prêtes en %.0f ms (%d images)" % [son.temps_rendu_ms, images])
	_ok(pire < IMAGE_MAX_MS, "image la plus longue pendant le rendu : %.1f ms (maximum %.0f)" % [pire, IMAGE_MAX_MS])
	_image(son, [{"type": "dash", "x": 500.0, "y": 400.0}])
	_ok(son.stats.joues == 1 and son.stats.pas_prets == 0, "un son rendu ainsi se joue")
	son.free()

# ---------------------------------------------------------------- événements échantillons

## Un événement plausible par variante sonore (champs tels que la simulation les émet).
func _echantillons() -> Array:
	return _echantillons_heros() + _echantillons_ennemis() + _echantillons_progression()

func _echantillons_heros() -> Array:
	var out: Array = [
		{"type": "swing", "x": 500.0, "y": 400.0, "index": 0.0, "strike": false, "ranged": false},
		{"type": "swing", "x": 500.0, "y": 400.0, "index": 1.0, "strike": false, "ranged": false},
		{"type": "swing", "x": 500.0, "y": 400.0, "index": 2.0, "strike": false, "ranged": false},
		{"type": "swing", "x": 500.0, "y": 400.0, "index": 0.0, "strike": true, "ranged": false},
		{"type": "swing", "x": 500.0, "y": 400.0, "index": 0.0, "strike": false, "ranged": true, "weapon": "arc"},
		{"type": "swing", "x": 500.0, "y": 400.0, "index": 0.0, "strike": false, "ranged": true, "weapon": "arbalete"},
		{"type": "hit", "id": 3.0, "x": 560.0, "y": 400.0, "amount": 10.0, "crit": false, "kind": "skill", "enemy": "imp"},
		{"type": "hit", "id": 3.0, "x": 560.0, "y": 400.0, "amount": 38.0, "crit": true, "kind": "strike", "enemy": "brute"},
		{"type": "hit", "id": 3.0, "x": 560.0, "y": 400.0, "amount": 3.0, "crit": false, "kind": "burn", "enemy": "imp"},
		{"type": "kill", "id": 3.0, "x": 560.0, "y": 400.0, "enemy": "imp", "elite": false, "boss": false},
		{"type": "kill", "id": 4.0, "x": 560.0, "y": 400.0, "enemy": "brute", "elite": true, "boss": false},
		{"type": "kill", "id": 5.0, "x": 560.0, "y": 400.0, "enemy": "gardien", "elite": false, "boss": true},
		{"type": "chain", "x0": 560.0, "y0": 400.0, "x1": 620.0, "y1": 420.0},
		{"type": "dash", "x": 500.0, "y": 400.0, "dirX": 1.0, "dirY": 0.0},
		{"type": "dodge", "x": 500.0, "y": 400.0},
		{"type": "dashNova", "x": 500.0, "y": 400.0, "r": 90.0},
		{"type": "dashReady", "charges": 2.0},
		{"type": "deflect", "x": 540.0, "y": 380.0},
		{"type": "superEnd", "x": 500.0, "y": 400.0},
		{"type": "superReady"},
		{"type": "gadgetCharge", "x": 0.0, "y": 0.0, "charges": 2.0},
		{"type": "playerHurt", "x": 500.0, "y": 400.0, "amount": 14.0, "source": "imp"},
		{"type": "playerDeath", "x": 500.0, "y": 400.0, "source": "arrow"},
	]
	for style in [null, "chain", "bond", "brasier", "volee"]:
		out.append({"type": "skill", "x": 500.0, "y": 400.0, "skill": style})
	for style in [null, "bombe", "piege", "cri", "totem"]:
		out.append({"type": "gadget", "x": 500.0, "y": 400.0, "gadget": style})
	for style in [null, "sentence", "nuee"]:
		out.append({"type": "super", "x": 500.0, "y": 400.0, "super": style})
		out.append({"type": "superTick", "x": 500.0, "y": 400.0, "super": style})
	return out

func _echantillons_ennemis() -> Array:
	var out: Array = [
		{"type": "explode", "id": 9.0, "x": 600.0, "y": 400.0, "r": 90.0},
		{"type": "explode", "x": 600.0, "y": 400.0, "r": 120.0, "hero": true, "kind": "bombe"},
		{"type": "hazardCancel", "id": 9.0, "x": 600.0, "y": 400.0},
		{"type": "wallSlam", "id": 9.0, "x": 100.0, "y": 400.0},
		{"type": "chargerWall", "id": 9.0, "x": 100.0, "y": 400.0, "boss": true},
		{"type": "spawnWarn", "id": 9.0, "x": 900.0, "y": 600.0, "enemy": "imp", "elite": true},
		{"type": "bossPhase", "id": 9.0, "x": 700.0, "y": 300.0, "phase": 2.0},
		{"type": "bossSummon", "id": 9.0, "x": 700.0, "y": 300.0},
	]
	for ennemi in Routage.RECETTE_PAR_CHAMP.enemyAttack[2] + ["exploder"]:
		out.append({"type": "enemyAttack", "id": 9.0, "x": 700.0, "y": 300.0, "enemy": ennemi})
	for zone in Routage.STYLE_ZONE:
		if zone != "exploder":
			out.append({"type": "hazardFire", "id": 9.0, "kind": zone, "shape": "circle", "x": 600.0, "y": 400.0, "r": 120.0})
	out.append({"type": "hazardFire", "id": 9.0, "kind": "colosseFist", "shape": "rect", "x": 600.0, "y": 400.0, "r": null})
	return out

func _echantillons_progression() -> Array:
	var out: Array = [
		{"type": "pickup", "kind": "gold", "x": 500.0, "y": 400.0, "amount": 3.0},
		{"type": "pickup", "kind": "heal", "x": 500.0, "y": 400.0, "amount": 12.0},
		{"type": "gold", "x": 500.0, "y": 400.0, "amount": 25.0},
		{"type": "buy", "kind": "heal"},
		{"type": "heal", "x": 500.0, "y": 400.0, "amount": 12.0},
		{"type": "roomClear", "floor": 3.0, "kind": "combat", "boss": false},
		{"type": "roomClear", "floor": 6.0, "kind": "boss", "boss": true},
		{"type": "doorsOpen", "count": 2.0},
		{"type": "floorEnter", "floor": 2.0, "circle": 1.0, "isBoss": false},
		{"type": "floorEnter", "floor": 6.0, "circle": 1.0, "isBoss": true},
		{"type": "checkpoint", "floor": 7.0},
		{"type": "respawn", "floor": 7.0},
		{"type": "choiceOpen", "kind": "boon"},
		{"type": "victory", "floor": 666.0},
		{"type": "gameOver", "floor": 12.0},
	]
	for rarete in ["commun", "rare", "epique"]:
		out.append({"type": "boonGain", "id": "b", "rarity": rarete})
	for rarete in ["commun", "magique", "rare", "legendaire"]:
		out.append({"type": "equip", "slot": "arme", "rarity": rarete})
	return out
