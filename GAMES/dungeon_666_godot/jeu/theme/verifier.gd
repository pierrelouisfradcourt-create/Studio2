extends SceneTree
## Vérification du thème commun et de ce qui en dépend, sans fenêtre (0 = vert) :
##   <godot> --headless --path . --script res://jeu/theme/verifier.gd
## 1. chaque variation de thème NOMMÉE sous jeu/ (scènes et scripts) existe dans jeu/theme/theme.gd ;
## 2. l'ordre des couches des vues est celui de jeu/theme/couches.gd ;
## 3. les « Réglages du feel » survivent à la fermeture (réglages relus sur le disque) et une
##    partie neuve NAÎT avec eux (options.tuning), sur l'arme et le Super du héros seulement ;
## 4. le Sanctuaire sait écrire l'effet cumulé de chaque amélioration.
## Finit par « THEME : OK » (code 0) ou « THEME : ECHEC » (code 1).

const ThemeJeu = preload("res://jeu/theme/theme.gd")
const Couches = preload("res://jeu/theme/couches.gd")
const Principal = preload("res://jeu/principal.gd")
const Profil = preload("res://jeu/profil.gd")
const DONNEES := "user://essais_theme"
const RACINE := "res://jeu"
## Dossiers dont les vues prennent leur style au thème commun.
const VUES := ["ecrans", "ville", "interface", "theme"]
const MOTIFS := ["theme_type_variation = &\"([A-Za-z]+)\"", "&\"([A-Z][A-Za-z]+)\"", "\"genre\": \"([A-Z][A-Za-z]+)\""]
const COUCHES := {
	"res://jeu/monde/monde.tscn": ["Voile", Couches.VOILE_MONDE], "res://jeu/effets/effets.tscn": ["Ecran", Couches.FLASH], "res://jeu/interface/hud.tscn": ["", Couches.HUD],
	"res://jeu/ville/ville.tscn": ["", Couches.VILLE], "res://jeu/ecrans/ecrans.tscn": ["", Couches.ECRANS],
}
const ECARTS := {"player.speed": 340.0, "combo.0.hitstop": 0.1, "combo.2.damage": 33.0, "super.chargeDamage": 500.0}

var _echecs := 0
var _verifs := 0

func _initialize() -> void:
	OS.set_environment("D666_DONNEES", DONNEES)
	for fichier in ["reglages_jeu.json", "reglages_jeu.json.bak", "profil.json", "profil.json.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DONNEES.path_join(fichier)))
	_derouler.call_deferred()

func _derouler() -> void:
	_variations()
	_couches()
	await _feel()
	_sanctuaire()
	print("%d vérifications, %d échec(s)" % [_verifs, _echecs])
	print("THEME : OK" if _echecs == 0 else "THEME : ECHEC (%d)" % _echecs)
	quit(0 if _echecs == 0 else 1)

func _ok(vrai: bool, quoi: String) -> void:
	_verifs += 1
	if not vrai:
		_echecs += 1
		print("  ECHEC : ", quoi)

# ---------------------------------------------------------------- 1. variations

func _fichiers(dossier: String, sortie: PackedStringArray) -> void:
	for nom in DirAccess.get_files_at(dossier):
		if nom.ends_with(".tscn") or (nom.ends_with(".gd") and nom != "verifier.gd" and nom != "theme.gd"):
			sortie.append(dossier.path_join(nom))
	for sous in DirAccess.get_directories_at(dossier):
		_fichiers(dossier.path_join(sous), sortie)

func _variations() -> void:
	var theme := ThemeJeu.theme()
	var fichiers := PackedStringArray()
	for vue in VUES:
		_fichiers(RACINE.path_join(vue), fichiers)
	var vues := {}
	for chemin in fichiers:
		var texte := FileAccess.get_file_as_string(chemin)
		for motif in MOTIFS:
			for m in RegEx.create_from_string(motif).search_all(texte):
				vues[m.get_string(1)] = chemin
	for nom in vues:
		_ok(theme.get_type_variation_base(nom) != &"", "variation « %s » (%s) absente du thème" % [nom, vues[nom]])
	print("-- variations : %d noms dans %d fichiers, toutes au thème commun" % [vues.size(), fichiers.size()])

# ---------------------------------------------------------------- 2. couches

func _couches() -> void:
	var lues: Array = []
	for chemin in COUCHES:
		var scene: Node = (load(chemin) as PackedScene).instantiate()
		var noeud: Node = scene if COUCHES[chemin][0] == "" else scene.get_node(COUCHES[chemin][0])
		_ok(noeud is CanvasLayer and noeud.layer == COUCHES[chemin][1], "%s : couche %s attendue" % [chemin, COUCHES[chemin][1]])
		lues.append(noeud.layer if noeud is CanvasLayer else -1)
		scene.free()
	_ok(Couches.MONDE < Couches.VOILE_MONDE and Couches.VOILE_MONDE < Couches.FLASH and Couches.FLASH < Couches.HUD and Couches.HUD < Couches.VILLE and Couches.VILLE < Couches.ECRANS and Couches.ECRANS < StudioTransitions.COUCHE, "ordre monde < voile < flash < HUD < Ville < écrans < fondu")
	print("-- couches : voile, flash, HUD, Ville, écrans = ", lues, " ; fondu = ", StudioTransitions.COUCHE)

# ---------------------------------------------------------------- 3. réglages du feel

func _nouvelle_app() -> Node:
	var app: Node = Principal.new()
	root.add_child(app)
	return app

func _feel() -> void:
	var app := _nouvelle_app()
	await process_frame
	var ref: Dictionary = app.contenu
	_ok(app.reglages.feel.is_empty(), "réglages neufs : aucun écart de feel")
	app.regler_feel(ECARTS)
	app.free()
	# « Fermeture » : une application neuve relit les réglages sur le disque.
	app = _nouvelle_app()
	await process_frame
	_ok(app.reglages.feel == ECARTS, "les écarts sont relus après fermeture : %s" % [app.reglages.feel])
	app.demarrer_descente(1.0, false, false, 7.0)
	var t: Dictionary = app.partie.game.tuning
	var kit: Dictionary = app.partie.game.kit
	_ok(t.player.speed == 340.0, "player.speed passe par options.tuning (%s)" % t.player.speed)
	_ok(t.combo[0].hitstop == 0.1 and t.combo[1].hitstop == 0.1, "combo.0.hitstop règle aussi le coup 2")
	_ok(t.combo[2].damage == 33.0 and t.combo[0].damage == ref.weapons[kit.weaponType].combo[0].damage, "combo.2.damage seul change dans le combo de l'arme portée (%s)" % kit.weaponType)
	_ok(t["super"].chargeDamage == 500.0, "super.chargeDamage vise le Super de la classe (%s)" % kit.superId)
	for arme in ref.weapons:
		if arme != kit.weaponType:
			_ok(t.weapons[arme].combo == ref.weapons[arme].combo, "l'arme non portée « %s » garde son combo" % arme)
	_ok(ref.player.speed != 340.0 and app.contenu.player.speed == ref.player.speed, "le tuning de référence n'est pas touché")
	app.regler_feel({})
	app.demarrer_descente(1.0, false, false, 7.0)
	_ok(app.partie.game.tuning.player.speed == ref.player.speed, "sans écart, la partie reprend la référence")
	_ok(Profil.charger_reglages().feel.is_empty(), "…et le disque aussi")
	_ok(Profil._feel_valide({"player.speed": "vite", "x": NAN, "dash.distance": 120}) == {"dash.distance": 120.0}, "un fichier abîmé ne donne que des nombres finis")
	print("-- feel : écarts enregistrés, relus, passés par options.tuning (arme %s, Super %s)" % [kit.weaponType, kit.superId])
	app.free()

# ---------------------------------------------------------------- 4. Sanctuaire

func _sanctuaire() -> void:
	var onglet: Node = (load("res://jeu/ville/onglet_sanctuaire.tscn") as PackedScene).instantiate()
	var ameliorations: Dictionary = D6Data.create_tuning().town.upgrades
	print("-- Sanctuaire : effet cumulé au niveau maximal")
	for id in ameliorations:
		var a: Dictionary = ameliorations[id]
		var texte: String = onglet._effet_cumule(a, a.max)
		print("  %-10s niv. %s : %s" % [id, D6Js.num_str(a.max), texte])
		var attendu: float = absf(a.perLevel) * a.max
		var nombre := D6Js.num_str(snappedf(attendu * 100.0, 0.1) if absf(a.perLevel) < 1.0 else attendu)
		_ok(texte.contains(nombre) and not texte.contains("par niveau"), "%s : « %s » devrait contenir %s" % [id, texte, nombre])
	onglet.free()
