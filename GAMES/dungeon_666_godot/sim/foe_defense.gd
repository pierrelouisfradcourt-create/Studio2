class_name D6FoeDefense
extends RefCounted
## Portage de src/sim/foe_defense.mjs.
## DÉFENSES d'archétypes lues par combat.damage_enemy (module feuille : n'appelle rien de la sim,
## hors D6Trig). Données : tuning.enemies[kind].
##
##   PAVOIS (Porte-pavois) — tout archétype qui déclare `guardArc` : un coup d'arme ou de
##     compétence (def.guardSources) qui arrive DE FACE, dans l'arc `guardArc` autour de `e.face`,
##     ne porte pas. Le pavois est baissé quand son porteur est étourdi, et écarté pendant la
##     récupération de son propre coup (état 'recover') : là, tout passe.
##   ÉTENDARD (Porte-étendard) — tout archétype qui déclare `auraRadius` : les AUTRES ennemis
##     (hors Gardiens, hors porte-étendards) à moins de `auraRadius` d'un porteur debout (ni mort,
##     ni étourdi, ni en train d'apparaître) ne prennent que `wardMult` des dégâts.
## Ce que l'écran doit montrer se lit avec les mêmes fonctions : guard_up (pavois levé ?) et
## ward_of (qui protège cet ennemi ?).

const MIN_DIR := 1e-6 # en deçà, le coup n'a pas de direction (brûlure, éclair) : il n'est pas arrêté

## Le pavois de `e` est-il levé (porteur ni étourdi, ni en récupération de son coup) ?
static func guard_up(game: Dictionary, e: Dictionary) -> bool:
	if D6Js.truthy(e.get("boss")):
		return false
	var def = game.tuning.enemies.get(e.kind)
	if def == null or not (D6Js.nz(def.get("guardArc"), 0.0) > 0.0) or e.get("face") == null:
		return false
	return not (e.stun > 0.0) and e.state != "recover"

## Le coup `src` ({kind, dirX, dirY} : direction du coup, de l'attaquant VERS la cible) est-il
## arrêté par le pavois de `e` ? Vrai s'il arrive de face, dans l'arc de garde.
static func front_blocked(game: Dictionary, e: Dictionary, src: Dictionary) -> bool:
	if not guard_up(game, e):
		return false
	var def: Dictionary = game.tuning.enemies[e.kind]
	if not (def.guardSources as Array).has(src.get("kind")):
		return false
	var dx: float = D6Js.nz(src.get("dirX"), 0.0)
	var dy: float = D6Js.nz(src.get("dirY"), 0.0)
	var l: float = sqrt(dx * dx + dy * dy)
	if l < MIN_DIR:
		return false
	# Le coup vient de la direction opposée à son élan : on la compare à la face du pavois.
	var toward: float = -(dx * D6Trig.cos(e.face) + dy * D6Trig.sin(e.face)) / l
	return toward >= D6Trig.cos(def.guardArc / 2.0)

## Le porte-étendard debout qui couvre `e`, ou null (le premier trouvé : les auras ne se cumulent pas).
static func ward_of(game: Dictionary, e: Dictionary):
	if D6Js.truthy(e.get("boss")):
		return null
	var enemies: Dictionary = game.tuning.enemies
	if _aura_radius(enemies, e.kind) > 0.0:
		return null # un étendard n'en protège pas un autre
	for o in game.enemies:
		if o.dead or D6Js.truthy(o.get("boss")) or o.spawnT > 0.0 or o.stun > 0.0:
			continue
		var r: float = _aura_radius(enemies, o.kind)
		if not (r > 0.0):
			continue
		var dx: float = e.x - o.x
		var dy: float = e.y - o.y
		if dx * dx + dy * dy < r * r:
			return o
	return null

# enemies[kind]?.auraRadius ?? 0
static func _aura_radius(enemies: Dictionary, kind) -> float:
	var def = enemies.get(kind)
	if def == null:
		return 0.0
	return D6Js.nz(def.get("auraRadius"), 0.0)

## Part des dégâts que `e` subit (1 = tout ; `wardMult` sous un étendard).
static func ward_mult(game: Dictionary, e: Dictionary) -> float:
	var o = ward_of(game, e)
	if o == null:
		return 1.0
	return game.tuning.enemies[o.kind].wardMult
