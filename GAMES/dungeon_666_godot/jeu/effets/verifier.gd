extends SceneTree
## Vérification de la vue Effets, sans fenêtre :
##   <godot> --headless --path . --script res://jeu/effets/verifier.gd
## 1. chaque type d'événement traité par la table HANDLERS de la version web (fx.mjs) a son effet
##    ici, ou est déclaré « au HUD » (bannière seule) ;
## 2. chaque événement d'exemple produit quelque chose (particules, formes, textes, flash, caméra) ;
## 3. un événement inconnu, ou sans type, ne plante pas ; `floorEnter` efface tout ;
## 4. le plafond de particules tient, et le coût d'une image à réservoir plein est mesuré.
## Finit par « EFFETS : OK » (code 0) ou « EFFETS : ECHEC » (code 1).

const Echantillons = preload("res://jeu/effets/echantillons.gd")
const FX_WEB := "res://../dungeon_666/src/render/fx.mjs"

var _banc: Node
var _effets: Node
var _echecs := 0

func _initialize() -> void:
	OS.set_environment("D666_DONNEES", "user://essais")
	_banc = (load("res://jeu/effets/banc.tscn") as PackedScene).instantiate()
	root.add_child(_banc)
	_verifier.call_deferred()

func _verifier() -> void:
	await process_frame
	await process_frame
	_effets = _banc.effets
	_effets.braises = false
	_effets.effacer()
	_table_web()
	await _exemples()
	await _robustesse()
	_plafond_et_cout()
	print("EFFETS : OK" if _echecs == 0 else "EFFETS : ECHEC (%d)" % _echecs)
	quit(0 if _echecs == 0 else 1)

func _echec(message: String) -> void:
	_echecs += 1
	print("  ECHEC : ", message)

## Les types de la table HANDLERS de fx.mjs, lus dans le fichier de la version web.
func _types_web() -> PackedStringArray:
	var texte := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../dungeon_666/src/render/fx.mjs"))
	var debut := texte.find("const HANDLERS = {")
	var fin := texte.find("\n};", debut)
	var motif := RegEx.create_from_string("(?m)^  (\\w+)\\(fx")
	var types := PackedStringArray()
	for m in motif.search_all(texte.substr(debut, fin - debut)):
		types.append(m.get_string(1))
	return types

func _table_web() -> void:
	var web := _types_web()
	var ici: Array = _effets.types()
	print("-- table : %d types dans fx.mjs, %d ici" % [web.size(), ici.size()])
	if web.size() < 20:
		_echec("fx.mjs illisible (%d types)" % web.size())
	for type in web:
		if type in ici:
			continue
		if type in _effets.AU_HUD:
			print("  %s : au HUD (bannière seule)" % type)
		else:
			_echec("%s est traité par fx.mjs, pas ici" % type)
	for type in ici:
		if not (type in web):
			print("  %s : en plus de fx.mjs" % type)

func _etat() -> Dictionary:
	var cam: Node = _banc.camera
	return {"particules": _effets.particules.n, "formes": _effets.formes.nombre(), "textes": _effets.textes.nombre(), "flash": _effets.ecran.actif(), "secouer": cam.appels.secouer, "recul": cam.appels.recul, "zoom": cam.appels.coup_de_zoom}

func _exemples() -> void:
	print("-- exemples : ce que chaque événement produit")
	var p: Vector2 = _banc.partie.position_dessin(_banc.partie.game.player, true)
	var vus := {}
	for ev in Echantillons.poses(p, PackedStringArray(), Vector2.ZERO):
		_effets.effacer()
		_banc.camera.remettre_a_zero()
		_banc.partie.evenements.emit([ev])
		if ev.type == "heal":
			await process_frame # les soins s'additionnent, le chiffre sort à l'image suivante
		var e := _etat()
		vus[ev.type] = true
		var variante := str(ev.get("kind", ev.get("skill", ev.get("gadget", ev.get("super", "")))))
		print("  %-11s %-10s particules %3d  formes %d  textes %d  flash %s  secousse %.2f  recul %.1f  zoom %.3f" % [ev.type, variante, e.particules, e.formes, e.textes, "oui" if e.flash else "non", e.secouer, e.recul, e.zoom])
		if e.particules == 0 and e.formes == 0 and e.textes == 0 and not e.flash and e.secouer == 0.0:
			_echec("%s ne produit rien" % ev.type)
	for type in _effets.types():
		if type != "floorEnter" and not vus.has(type):
			_echec("%s n'a pas d'événement d'exemple" % type)

func _robustesse() -> void:
	print("-- robustesse")
	var p: Vector2 = _banc.partie.position_dessin(_banc.partie.game.player, true)
	_banc.partie.evenements.emit(Echantillons.poses(p))
	if _effets.particules.n == 0:
		_echec("la planche complète ne produit aucune particule")
	_banc.partie.evenements.emit([{"type": "inconnu", "tick": 0.0}, {"tick": 0.0}, {"type": "roomClear", "tick": 0.0, "boss": true}, {"type": "enemyAttack", "tick": 0.0}])
	print("  événement inconnu, sans type, au HUD : ignorés sans erreur")
	_banc.partie.evenements.emit([{"type": "floorEnter", "tick": 0.0, "floor": 2.0}])
	var e := _etat()
	if e.particules != 0 or e.formes != 0 or e.textes != 0 or e.flash:
		_echec("floorEnter n'efface pas tout : %s" % e)
	else:
		print("  floorEnter : tout est effacé")
	# La vue doit vivre sans Monde (pas de caméra).
	_banc.vues = {}
	_banc.partie.evenements.emit(Echantillons.poses(p))
	for i in 3:
		await process_frame
	print("  sans vue Monde : les effets sortent, aucune secousse demandée")
	_banc.vues = {"monde": _banc}

func _plafond_et_cout() -> void:
	print("-- plafond et coût")
	var res: Node = _effets.particules
	res.vider()
	res.gerbe(0.0, 0.0, res.PLAFOND * 3, 300.0, 5.0, 3.0, Color.WHITE)
	if res.n != res.PLAFOND:
		_echec("plafond non tenu : %d particules" % res.n)
	var tours := 600
	var debut := Time.get_ticks_usec()
	for i in tours:
		res.avancer(1.0 / 600.0)
	var cout := (Time.get_ticks_usec() - debut) / float(tours)
	print("  plafond : %d particules ; avancer() à réservoir plein : %.0f µs par image (ce poste, sans dessin)" % [res.n, cout])
	res.vider()
