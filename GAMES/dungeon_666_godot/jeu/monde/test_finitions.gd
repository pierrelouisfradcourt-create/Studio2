extends SceneTree
## Essai headless du lot de triangles (coût du dessin) et de trois finitions.
##   <godot> --headless --path . --script res://jeu/monde/test_finitions.gd      (sortie 0 = vert)
## 1. lot de triangles (jeu/theme/triangles.gd) : un disque, un trait lissé, une forme gardée en
##    mémoire ; les numéros de triangles restent dans le lot ; un corps d'ennemi tient en un lot ;
## 2. ramassables : celui qui tombe juste au nord d'un pilier est repeint devant lui (relais du
##    groupe trié), les autres restent au sol ; l'objet d'interaction est au rang de son pied ;
## 3. Gardien qui bondit : son nœud garde le rang de son point au sol, seul son dessin monte ;
## 4. Grimoire : la note nomme la compétence et le gadget RÉELLEMENT équipés.
## Ce qu'il ne prouve pas : le nombre d'appels de dessin (il faut un vrai rendu : jeu/monde/mesure.gd
## sur jeu/essai/cout.tscn) ni que l'image est la même (captures de _dev/captures/lot_cout).

const Triangles = preload("res://jeu/theme/triangles.gd")
const Objets = preload("res://jeu/monde/objets.gd")
const Principal = preload("res://jeu/principal.gd")

const DOSSIER := "user://essais_finitions"
const PILIER := {"x0": 400.0, "y0": 300.0, "x1": 470.0, "y1": 370.0}

var _banc: Node
var _monde: Node2D
var _g: Dictionary
var _verifs := 0
var _rouges := 0

func _initialize() -> void:
	OS.set_environment("D666_DONNEES", DOSSIER) # AVANT d'instancier quoi que ce soit
	_derouler()

func _ok(vrai: bool, quoi: String) -> void:
	_verifs += 1
	if vrai:
		print("  ok    — ", quoi)
	else:
		_rouges += 1
		print("  ROUGE — ", quoi)

func _images(n: int = 3) -> void:
	for i in n:
		await process_frame

func _derouler() -> void:
	_triangles()
	await _grimoire()
	_banc = (load("res://jeu/monde/banc.tscn") as PackedScene).instantiate()
	root.add_child(_banc)
	await _images()
	_monde = _banc.vues.monde
	_g = _banc.partie.game
	_banc.partie.en_pause = true
	for liste in [_g.enemies, _g.spawns, _g.hazards, _g.pickups]:
		liste.clear()
	_g.room = _g.room.duplicate()
	_g.room.obstacles = [PILIER.duplicate()]
	_g.player.x = 900.0
	_g.player.y = 600.0
	await _ramassables()
	await _objet()
	await _bond()
	await _corps_en_un_lot()
	print("FINITIONS : %d vérifications, %d rouge(s)" % [_verifs, _rouges])
	print("FINITIONS : OK" if _rouges == 0 else "FINITIONS : ECHEC")
	quit(0 if _rouges == 0 else 1)

# ---------------------------------------------------------------- lot de triangles

func _triangles() -> void:
	print("-- lot de triangles")
	var lot := Triangles.new()
	lot.disque(Vector2(10.0, 20.0), 8.0, Color.RED)
	var n: int = Triangles.SEGMENTS
	_ok(lot._pts.size() == 2 * (n + 1) + 1, "disque lissé : 65 points de bord, le centre, 65 points de frange")
	_ok(lot._numeros.size() == 3 * (n + 2 * n), "disque lissé : 64 triangles pleins et 128 de frange")
	_ok(lot._pts[0].is_equal_approx(Vector2(18.0, 20.0)) and lot._pts[n + 2].is_equal_approx(Vector2(18.0 + Triangles.PLUME, 20.0)), "… son bord est à 8 u du centre, sa frange 1,25 u plus loin")
	_ok(lot._teintes[0] == Color.RED and lot._teintes[n + 2] == Color(1.0, 0.0, 0.0, 0.0), "… plein au bord, transparent au bout de la frange")
	var base := lot._pts.size()
	lot.polyligne(PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0)]), Color.BLUE, 4.0)
	_ok(lot._pts.size() - base == 16, "trait lissé de 2 points : 4 points pleins, 4 de frange, 8 aux deux bouts")
	var bords := [lot._pts[base], lot._pts[base + 2], lot._pts[base + 4], lot._pts[base + 8], lot._pts[base + 12]]
	_ok(absf(bords[0].y) == 2.0 and absf(bords[1].y) == 2.0 and absf(bords[2].y) == 2.0 + Triangles.PLUME, "… large de 4 u, frangé de 1,25 u de chaque côté")
	_ok(is_equal_approx(bords[3].x, -Triangles.PLUME) and is_equal_approx(bords[4].x, 10.0 + Triangles.PLUME), "… et de 1,25 u à chaque bout")
	_ok(lot._pts.size() == lot._teintes.size(), "une couleur par point")
	var dedans := true
	for i in lot._numeros:
		dedans = dedans and i >= 0 and i < lot._pts.size()
	_ok(dedans and lot._numeros.size() % 3 == 0, "tous les triangles désignent des points du lot")
	_ok(lot._numeros[lot._numeros.size() - 1] >= base, "les triangles de la seconde forme sont comptés après ceux de la première")
	var forme := PackedVector2Array([Vector2(0, 0), Vector2(9, 0), Vector2(9, 5), Vector2(4, 9), Vector2(0, 5)])
	var cle := [4, 2.0, true, forme]
	lot.contour(forme, Color.WHITE, 2.0, true)
	var garde = Triangles._retrouver(cle)
	lot.contour(forme.duplicate(), Color.WHITE, 2.0, true, Transform2D(0.0, Vector2(50.0, 0.0)))
	_ok(garde != null and is_same(garde, Triangles._retrouver(cle)), "une forme déjà vue est reprise de la mémoire, où qu'elle soit posée")

# ---------------------------------------------------------------- Grimoire

func _grimoire() -> void:
	print("-- Grimoire")
	var app: Node = Principal.new()
	root.add_child(app)
	await _images()
	if not app.vues.has("ville"):
		_ok(false, "le programme principal a monté la Ville")
		return
	app.ouvrir_ville()
	app.vues.ville.ouvrir_onglet("grimoire")
	await _images()
	var note: Label = app.vues.ville.page("grimoire").get_node("Note")
	var classe: Dictionary = app.contenu.classes[app.profil.loadout.classId]
	var equipee: String = app.contenu.skills[app.profil.loadout.skillId].name
	_ok(note.text.contains(equipee), "la note nomme la compétence équipée (« %s »)" % equipee)
	_ok(note.text.contains(String(app.contenu.gadgets[app.profil.loadout.gadgetId].name)), "… et le gadget équipé")
	_ok(not note.text.contains("bouton Lance"), "… et ne nomme plus « le bouton Lance » en dur")
	# Le test fabrique sa situation (une autre compétence équipée) ; la Ville, elle, n'écrit jamais le profil.
	var autre: String = classe.skills[1]
	app.profil.loadout.skillId = autre
	app.profil_change.emit()
	await _images()
	note = app.vues.ville.page("grimoire").get_node("Note")
	var nom: String = app.contenu.skills[autre].name
	_ok(nom != equipee and note.text.contains(nom) and not note.text.contains(equipee), "une autre compétence équipée : la note la nomme (« %s »)" % nom)
	app.queue_free()
	await _images()

# ---------------------------------------------------------------- profondeur

func _ramassables() -> void:
	print("-- ramassables")
	var o := [PILIER]
	var h: float = preload("res://jeu/monde/piliers.gd").HAUTEUR
	_ok(Objets.pilier_masquant(o, Vector2(435.0, PILIER.y0 - 9.0)) == 0, "tombé juste au nord du pilier : masqué par son dessus")
	_ok(Objets.pilier_masquant(o, Vector2(435.0, PILIER.y0 - h - 20.0)) == -1, "plus au nord que le dessus du pilier : visible")
	_ok(Objets.pilier_masquant(o, Vector2(435.0, PILIER.y1 + 9.0)) == -1, "au sud du pilier : visible")
	_ok(Objets.pilier_masquant(o, Vector2(PILIER.x0 - 12.0, 335.0)) == -1 and Objets.pilier_masquant(o, Vector2(PILIER.x1 + 12.0, 335.0)) == -1, "à côté du pilier : visible")
	var nord: Dictionary = D6Combat.spawn_pickup(_g, "gold", 435.0, PILIER.y0 - 9.0, 1.0, {"vx": 0.0, "vy": 0.0})
	var sud: Dictionary = D6Combat.spawn_pickup(_g, "heal", 435.0, PILIER.y1 + 9.0, 1.0, {"vx": 0.0, "vy": 0.0})
	await _images()
	var debout: Node2D = _monde.get_node("Entites/Debout")
	var objets: Node2D = _monde.get_node("Objets")
	var relais: Node2D = debout.get_node_or_null("Objets")
	_ok(relais != null and relais.y_sort_enabled, "les relais des objets sont dans le groupe trié des créatures et des piliers")
	if relais == null:
		return
	var pilier: Node2D = debout.get_node("Piliers").get_child(0)
	var leve: Node2D = relais.get_node_or_null("Leves0")
	_ok(leve != null and leve.visible and leve.position.y > pilier.position.y, "le ramassable masqué est repeint juste DEVANT son pilier")
	_ok(objets._masques[0] == [nord] and objets._au_sol == [sud], "… lui seul : l'autre reste au sol, sous les créatures")
	_ok(objets.get_index() < _monde.get_node("Entites").get_index(), "le calque du sol reste sous tout ce qui est debout")
	_g.pickups.clear()
	await _images()
	_ok(not leve.visible, "plus de ramassable masqué : son relais est caché")

func _objet() -> void:
	print("-- objet d'interaction")
	var relais: Node2D = _monde.get_node("Entites/Debout/Objets")
	var corps: Node2D = relais.get_node("Objet")
	_g.room.interact = null
	await _images()
	_ok(not corps.visible, "pas d'objet dans la salle : son relais est caché")
	_g.room.interact = {"kind": "rest", "x": 435.0, "y": PILIER.y1 + 34.0, "r": 34.0, "used": false}
	await _images()
	var pilier: Node2D = _monde.get_node("Entites/Debout/Piliers").get_child(0)
	_ok(corps.visible and corps.position == Vector2(435.0, PILIER.y1 + 34.0), "l'objet est rangé au rang de son pied")
	_ok(corps.position.y > pilier.position.y, "posé au sud d'un pilier : devant lui (le pilier ne le recouvre pas)")
	_g.room.interact.used = true
	await _images()
	_ok(not corps.visible, "objet utilisé : il disparaît")
	_g.room.interact = null

func _bond() -> void:
	print("-- Gardien qui bondit")
	var e: Dictionary = D6Enemies.create_enemy(_g, "cerbere", PILIER.x1 + 12.0, PILIER.y1 + 22.0, {"boss": true})
	e.spawnT = 0.0
	await _images()
	var pilier: Node2D = _monde.get_node("Entites/Debout/Piliers").get_child(0)
	var corps: Node2D = null
	for n in _monde.get_node("Entites/Debout/Ennemis").get_children():
		if n.e.id == e.id:
			corps = n
	_ok(corps != null and corps.envol == 0.0 and corps.position.y > pilier.position.y, "au sol, au coin sud-est du pilier : devant lui")
	e.airborne = true
	e.leapK = 0.5
	await _images()
	_ok(corps.envol > e.r, "au sommet du bond : son dessin monte (%.0f u)" % corps.envol)
	_ok(absf(corps.position.y - e.y) < 2.0 and corps.position.y > pilier.position.y, "… mais son nœud garde le rang de son point au sol : toujours devant le pilier")
	_g.enemies.clear()
	await _images()

## Le pinceau des créatures ne laisse rien partir seul : après le dessin d'un corps, son lot est vide
## (tout a été tracé d'un coup) et aucun repère ne reste posé.
func _corps_en_un_lot() -> void:
	print("-- un corps, un lot")
	Triangles._oublier()
	for genre in ["imp", "pyromancer", "stalker", "banner"]:
		var e: Dictionary = D6Enemies.create_enemy(_g, genre, 700.0, 500.0, {})
		e.spawnT = 0.0
	await _images(4)
	var calque: Node2D = _monde.get_node("Entites/Debout/Ennemis")
	_ok(calque.get_child_count() == 4, "un nœud par corps")
	_ok(Triangles._neufs.size() > 20, "les corps ont été peints par le lot (%d formes gardées en mémoire)" % Triangles._neufs.size())
	_ok(calque.p.lot.vide() and calque.p.lot.repere == Transform2D.IDENTITY, "après le dessin des corps, le lot du pinceau est vide et son repère levé")
	for nom in ["Sol", "Statuts"]:
		var c: Node2D = _monde.get_node("Entites/" + nom)
		_ok(c.p.lot.vide(), "calque %s : son lot est tracé en entier" % nom)
	_g.enemies.clear()
