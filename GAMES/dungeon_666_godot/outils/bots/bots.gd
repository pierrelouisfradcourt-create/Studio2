extends RefCounted
## Portage de tools/bots.mjs.
## Bots de playtest headless : des « joueurs » automatiques qui produisent un InputFrame à
## partir de ce qu'un joueur VOIT à l'écran — positions, télégraphes (e.tele), zones de
## danger (game.hazards), projectiles et mouvements des ennemis. Ils ne lisent JAMAIS le RNG
## de la partie ni les compteurs cachés des ennemis (cooldowns, durées de windup) : le temps
## restant d'un télégraphe est estimé à partir de la vitesse de remplissage observée de sa
## jauge, comme le ferait l'œil. Ils connaissent en revanche leur propre héros (portée,
## vitesse, dash), comme un joueur qui a pris le jeu en main.
##
##   const Bots = preload("res://outils/bots/bots.gd")
##   var mem := {}                                   # mémoire libre, une par partie
##   if game.mode == "choice": Bots.resolve_choice(game, "skilled")
##   D6Game.step_game(game, Bots.play("skilled", game, mem))
##
## Politiques :
##   skilled — joue bien : lit les télégraphes, esquive au dernier moment (marche ou dash),
##             punit les béliers sonnés, gère ses trois emplacements (compétences, gadgets)
##             et l'ultime (attaque TENUE quand la jauge est pleine ; sinon il frappe par appuis).
##   noDash  — identique mais n'utilise JAMAIS le dash ni le gadget : mesure la valeur du dash.
##   masher  — fonce sur l'ennemi le plus proche et tient l'attaque sans arrêt, dash aléatoire
##             rare. Combat V3 : attaque tenue + jauge pleine = l'ultime part tout seul.
##
## Options posées par l'appelant dans la mémoire (jamais lues dans la partie) :
##   mem.wantTown   — prendre le portail de la Ville quand il s'ouvre (sinon : jamais) ;
##   mem.wantRewards — liste de récompenses de porte à préférer (« shop », « event »…) : la
##                    première porte qui y mène est prise (sinon : le choix habituel) ;
##   mem.dashAttack — taper l'attaque au début de chaque dash (mesure du labo D5).
##
## Découpage : base.gd (utilitaires, navigation), perception.gd (menaces), anticipation.gd
## (esquive), intention.gd (combat, hors combat), menus.gd (mode 'choice').
## Garde : les bots jouent les parties de référence. Un réenregistrement (references/enregistrer.sh)
## sans changement de règle doit redonner les mêmes fichiers ; si un fichier change alors que sim/
## n'a pas bougé, c'est un bot qui ne joue plus pareil. (Jusqu'au 2026-10-01 : mêmes entrées que le
## bot web, image par image — parite/LISEZ_MOI.md.)

const Base = preload("res://outils/bots/base.gd")
const Perception = preload("res://outils/bots/perception.gd")
const Anticipation = preload("res://outils/bots/anticipation.gd")
const Intention = preload("res://outils/bots/intention.gd")
const Menus = preload("res://outils/bots/menus.gd")

const POLICIES := ["skilled", "noDash", "masher"]
const DT := 1.0 / 60.0
const MOVE_INTENT_MIN2 := 0.25 # norme² minimale d'une intention de marche (détection de blocage)
const STUCK_WINDOW := 0.75 # s
const STUCK_DIST := 14.0 # u parcourues en moins => coincé
const UNSTICK_TIME := 0.35 # s de déplacement latéral pour se décoincer
const MASHER_DASH_CHANCE := 0.0025 # par image (~ un dash toutes les 7 s)
const MASHER_CONTACT_GAP := 10.0
const SKILLED_OPTS := {"dash": true, "gadget": true, "salt": 1}
const NO_DASH_OPTS := {"dash": false, "gadget": false, "salt": 2}
const MASHER_SALT := 3

# ---------------------------------------------------------------- mémoire

## Mémoire du bot, créée à la première image jouée. Le RNG local (mulberry32, D6Rng) est dérivé
## de la graine : il n'avance jamais celui de la partie.
static func _ensure_mem(game: Dictionary, mem: Dictionary, salt: int) -> Dictionary:
	if D6Js.truthy(mem.get("ready")):
		return mem
	mem.ready = true
	mem.rng = D6Rng.create_rng(Base.mix_hash([game.seed, salt]))
	mem.motion = {} # id -> {x, y, t, vx, vy} : mouvement observé
	mem.tele = {} # id -> {p0, t0, shape} : début d'observation d'une jauge
	var buf := PackedFloat64Array()
	buf.resize((Anticipation.SAMPLES + 1) * 2)
	mem.buf = buf
	mem.targetId = 0.0
	mem.doorFloor = -1.0
	mem.door = 0
	mem.lastGadget = -INF
	mem.evadeUntil = -1.0
	mem.evadeStart = -1.0
	mem.evadeX = 0.0
	mem.evadeY = 0.0
	mem.stuckX = 0.0
	mem.stuckY = 0.0
	mem.stuckT = 0.0
	mem.unstickT = 0.0
	mem.unstickX = 0.0
	mem.unstickY = 0.0
	mem.unstickSign = 1.0
	mem.floor = -1.0
	return mem

## Copie indépendante de la mémoire d'un bot : sert à rejouer une même situation depuis un
## clone de la partie (audit contrefactuel des dash) sans perturber la partie réelle. Comme en
## JavaScript, `roomRef` et `doorRoom` désignent toujours la salle de la partie d'ORIGINE.
static func clone_memory(mem: Dictionary) -> Dictionary:
	if not D6Js.truthy(mem.get("ready")):
		return {}
	var out := mem.duplicate()
	out.rng = D6Rng.clone_rng(mem.rng)
	out.motion = _copy_map(mem.motion)
	out.tele = _copy_map(mem.tele)
	out.buf = mem.buf.duplicate()
	return out

static func _copy_map(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		out[k] = m[k].duplicate()
	return out

static func _on_new_floor(game: Dictionary, mem: Dictionary) -> void:
	if mem.floor == game.run.floor and is_same(mem.get("roomRef"), game.room):
		return
	mem.floor = game.run.floor
	mem.roomRef = game.room
	mem.motion.clear()
	mem.tele.clear()
	mem.targetId = 0.0

# ---------------------------------------------------------------- composition

## Se décoince quand l'intention de marche ne produit aucun déplacement.
static func _apply_unstick(game: Dictionary, mem: Dictionary, intent: Dictionary) -> void:
	var p: Dictionary = game.player
	var now: float = game.tick * DT
	if mem.unstickT > 0.0:
		mem.unstickT -= DT
		intent.mx = mem.unstickX
		intent.my = mem.unstickY
		intent.attack = false
		return
	var wants: bool = intent.mx * intent.mx + intent.my * intent.my > MOVE_INTENT_MIN2 and not D6Js.truthy(intent.get("attack")) and p.state == "free"
	if not wants or game.hitstop > 0.0 or p.freeze > 0.0:
		mem.stuckX = p.x
		mem.stuckY = p.y
		mem.stuckT = now
		return
	if now - mem.stuckT < STUCK_WINDOW:
		return
	if D6Geo.dist2(p.x, p.y, mem.stuckX, mem.stuckY) < STUCK_DIST * STUCK_DIST:
		mem.unstickSign = -mem.unstickSign
		mem.unstickX = -intent.my * mem.unstickSign
		mem.unstickY = intent.mx * mem.unstickSign
		mem.unstickT = UNSTICK_TIME
	mem.stuckX = p.x
	mem.stuckY = p.y
	mem.stuckT = now

static func _intent_to_input(intent: Dictionary) -> Dictionary:
	var input := D6Game.empty_input()
	input.moveX = intent.mx
	input.moveY = intent.my
	_attack_input(intent, input)
	if D6Js.truthy(intent.get("aimX")) or D6Js.truthy(intent.get("aimY")):
		input.aimX = intent.aimX
		input.aimY = intent.aimY
	var slots: Array = intent.slots
	for i in slots.size():
		if slots[i] != null:
			input[D6Player.SLOT_PRESSED[i]] = true
			input[D6Player.SLOT_AIM_X[i]] = slots[i].x
			input[D6Player.SLOT_AIM_Y[i]] = slots[i].y
	var dash = intent.get("dash")
	if dash != null:
		# Dash offensif (traverser un porte-pavois) : la direction du dash est celle de la marche.
		input.moveX = dash.x
		input.moveY = dash.y
		input.dashPressed = true
	return input

## Le bouton d'attaque d'une intention. L'ultime voulu : il est TENU. Jauge pleine sans le vouloir
## (intent.tap) : des appuis brefs, jamais tenus — tenir le lancerait. Sinon : tenu, comme avant.
static func _attack_input(intent: Dictionary, input: Dictionary) -> void:
	if D6Js.truthy(intent.get("superP")):
		input.attack = true
	elif D6Js.truthy(intent.get("tap")):
		input.attack = false
		input.attackPressed = D6Js.truthy(intent.get("attack"))
	else:
		input.attack = D6Js.truthy(intent.get("attack"))

## Pendant un dash : on tient la direction. Habitude « dash puis frappe » (mesure du labo D5, sur
## demande : mem.dashAttack) : le pouce tape l'attaque dès le début de chaque ruée, comme un
## joueur pressé ; la variante D5 décide quand ce tap devient frappe de dash.
static func _dashing_input(game: Dictionary, mem: Dictionary, input: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	input.moveX = p.dashDirX
	input.moveY = p.dashDirY
	if D6Js.truthy(mem.get("dashAttack")) and mem.get("dashAttackSeq") != game.telemetry.dashes and not Base.visible_enemies(game).is_empty():
		input.attackPressed = true
		mem.dashAttackSeq = game.telemetry.dashes
	return input

static func _tactical(game: Dictionary, mem: Dictionary, opts: Dictionary) -> Dictionary:
	var input := D6Game.empty_input()
	if game.mode != "play":
		return input
	_ensure_mem(game, mem, opts.salt)
	_on_new_floor(game, mem)
	Perception.track_motion(game, mem)
	var p: Dictionary = game.player
	if p.state == "dead":
		return input
	if p.state == "dash":
		return _dashing_input(game, mem, input)
	var enemies := Base.visible_enemies(game)
	var intent: Dictionary = Intention.engage_intent(game, mem, enemies, opts) if not enemies.is_empty() else Intention.explore_intent(game, mem)
	_apply_unstick(game, mem, intent)
	var threats := Perception.perceive_threats(game, mem)
	if not threats.is_empty():
		var evasive = Anticipation.plan_evasion(game, mem, threats, intent, opts)
		if evasive != null:
			# On garde l'ultime s'il est voulu (il rend invulnérable) : l'attaque reste tenue ; et
			# jauge pleine sans le vouloir, l'esquive ne tient pas l'attaque non plus.
			var wanted: Dictionary = {"superP": intent.superP, "tap": intent.tap, "attack": evasive.attack}
			_attack_input(wanted, evasive)
			return evasive
	return _intent_to_input(intent)

# ---------------------------------------------------------------- politiques

static func skilled(game: Dictionary, mem: Dictionary) -> Dictionary:
	return _tactical(game, mem, SKILLED_OPTS)

static func no_dash(game: Dictionary, mem: Dictionary) -> Dictionary:
	return _tactical(game, mem, NO_DASH_OPTS)

static func masher(game: Dictionary, mem: Dictionary) -> Dictionary:
	var input := D6Game.empty_input()
	if game.mode != "play":
		return input
	_ensure_mem(game, mem, MASHER_SALT)
	_on_new_floor(game, mem)
	var p: Dictionary = game.player
	if p.state == "dead":
		return input
	var enemies := Base.visible_enemies(game)
	var intent: Dictionary = {"mx": 0.0, "my": 0.0, "attack": true} if not enemies.is_empty() else Intention.explore_intent(game, mem)
	if not enemies.is_empty():
		var e: Dictionary = Intention.nearest(p, enemies)
		if Base.dist_to(p, e) > e.r + p.r + MASHER_CONTACT_GAP:
			var d := Base.nav_dir(game.room, p.x, p.y, e.x, e.y, p.r)
			intent.mx = d.x
			intent.my = d.y
	_apply_unstick(game, mem, intent)
	input.moveX = intent.mx
	input.moveY = intent.my
	input.attack = D6Js.truthy(intent.get("attack"))
	if D6Rng.rand(mem.rng) < MASHER_DASH_CHANCE:
		var a := D6Rng.rand(mem.rng) * PI * 2.0
		input.moveX = D6Trig.cos(a)
		input.moveY = D6Trig.sin(a)
		input.dashPressed = true
	return input

static func has_policy(policy_name: String) -> bool:
	return POLICIES.has(policy_name)

## Une image d'entrées de la politique `policy_name` (POLICIES[nom](game, mem) du JavaScript).
static func play(policy_name: String, game: Dictionary, mem: Dictionary) -> Dictionary:
	match policy_name:
		"skilled":
			return skilled(game, mem)
		"noDash":
			return no_dash(game, mem)
		"masher":
			return masher(game, mem)
	push_error("politique inconnue : %s" % policy_name)
	return D6Game.empty_input()

## Les commandes que le bot enverrait au menu ouvert, sans les appliquer : voir menus.gd.
static func choice_commands(game: Dictionary, policy_name: String) -> Array:
	return Menus.choice_commands(game, policy_name)

## Résout le menu ouvert (mode 'choice') : voir menus.gd.
static func resolve_choice(game: Dictionary, policy_name: String) -> bool:
	return Menus.resolve_choice(game, policy_name)
