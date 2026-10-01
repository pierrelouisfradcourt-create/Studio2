extends RefCounted
## Portage de tools/playtest.mjs (runEpisode, summarize, audit des dash) : UNE partie jouée par un
## bot, et son résumé mesuré.
##
##   const Episode = preload("res://outils/bots/episode.gd")
##   var r := Episode.run_episode("skilled", 1.0, {"floors": 18.0, "minutes": 30.0})
##
## Pour une politique et une graine : create_game, boucle step_game, événements vidés à chaque
## pas (et comptés), menus résolus par le bot. Arrêt quand l'étage floors + 1 est atteint (section
## battue), à la première mort (pas de reprise), au retour en Ville (sur demande seulement :
## options.town) ou après `minutes` de temps simulé.
##
## Salles comptées : seules les salles JOUÉES (étage <= floors). L'étage floors + 1, ouvert
## puis aussitôt abandonné quand la section est battue, n'est pas une salle de combat.
##
## Audit des dash (politique skilled, options.dashAudit) : à chaque dash, la situation est rejouée
## DEUX fois depuis un clone de la partie, pendant DASH_AUDIT_SECONDS : avec le dash, puis sans ce
## dash et avec la meilleure esquive à pied (bot noDash). Un dash est « décisif » si seule la
## version sans dash prend un coup.
##
## Non porté : les agrégats, le rapport markdown et le labo de playtest.mjs (--lab-report).

const Bots = preload("res://outils/bots/bots.gd")

const DT := 1.0 / 60.0
const DEFAULT_FLOORS := 18.0 # une section complète (Gardien compris)
const DEFAULT_MINUTES := 30.0
const AUDITED_POLICY := "skilled" # la seule politique qui dashe « exprès »
const COUNTERFACTUAL_POLICY := "noDash" # meilleure esquive à pied
const DASH_AUDIT_SECONDS := 1.0 # fenêtre de comparaison des deux futurs
const SECONDS_PER_MINUTE := 60.0
const MAX_CHOICE_ATTEMPTS := 8 # menus consécutifs sans progrès => run bloqué
const STALL_SECONDS := 30.0 # salle nettoyée depuis si longtemps sans changer d'étage => blocage
const COMBAT_KINDS := ["combat", "elite", "boss"]

# ---------------------------------------------------------------- une partie

static func _new_recorder() -> Dictionary:
	return {
		"events": {}, "rooms": [], "current": null, "stall": null, "stallRoom": null, "stallTick": -1.0,
		"strikes": 0.0, # frappes de dash (attaque partie pendant ou juste après un dash)
		"frozenTicks": 0.0, # images où le héros est figé (gel global ou local, D8)
		"audit": {"dashes": 0.0, "decisive": 0.0, "harmful": 0.0, "bothHit": 0.0, "idle": 0.0, "skipped": 0.0},
	}

static func _open_room(rec: Dictionary, game: Dictionary, ev: Dictionary) -> void:
	rec.current = {
		"floor": ev.get("floor"), "kind": ev.get("kind"), "damage0": game.telemetry.damageTaken, "hits0": game.telemetry.hitsTaken,
		"tick0": game.tick, "time0": game.time, "clearTime": null, "clearTick": null,
	}

static func _close_room(rec: Dictionary, game: Dictionary) -> void:
	var c = rec.current
	if c == null:
		return
	rec.rooms.append({
		"floor": c.floor,
		"kind": c.kind,
		"damage": game.telemetry.damageTaken - c.damage0,
		"hits": game.telemetry.hitsTaken - c.hits0,
		"seconds": (game.tick - c.tick0) * DT,
		# Temps de combat (temps de sim, gel d'impact exclu) : de l'entrée au nettoyage, ou à la fin du run.
		"combatSeconds": D6Js.nz(c.clearTime, game.time) - c.time0,
		# Même durée en temps RÉEL (images, gel compris) : seule mesure comparable entre gel global
		# (le temps de sim s'arrête) et gel local (il continue).
		"realCombatSeconds": (D6Js.nz(c.clearTick, game.tick) - c.tick0) * DT,
	})
	rec.current = null

static func _consume_events(game: Dictionary, rec: Dictionary) -> void:
	var counts: Dictionary = rec.events
	for ev in game.events:
		counts[ev.type] = counts.get(ev.type, 0.0) + 1.0
		if ev.type == "floorEnter":
			_close_room(rec, game)
			_open_room(rec, game, ev)
		elif ev.type == "roomClear" and rec.current != null:
			rec.current.clearTime = game.time
			rec.current.clearTick = game.tick
		elif ev.type == "attackStart" and D6Js.truthy(ev.get("strike")):
			rec.strikes += 1.0
	game.events.clear()

# ---------------------------------------------------------------- audit contrefactuel des dash

## Dégâts subis pendant `ticks` pas, depuis un clone, en jouant `first` puis la politique.
static func _rollout(game: Dictionary, mem: Dictionary, first: Dictionary, policy_name: String, ticks: int) -> float:
	var g: Dictionary = D6Js.clone(game)
	g.run.items = g.meta.equipment # même objet des deux côtés, comme dans la partie d'origine
	var m := Bots.clone_memory(mem)
	g.events.clear()
	var before: float = g.telemetry.damageTaken
	D6Game.step_game(g, first)
	var i := 1
	while i < ticks and g.mode == "play":
		D6Game.step_game(g, Bots.play(policy_name, g, m))
		g.events.clear()
		i += 1
	return g.telemetry.damageTaken - before

## Classe le dash que le bot s'apprête à faire : décisif, nuisible, inutile, ou coup inévitable.
static func _audit_dash(game: Dictionary, mem: Dictionary, input: Dictionary, policy_name: String, audit: Dictionary) -> void:
	var ticks := int(D6Js.jround(DASH_AUDIT_SECONDS / DT))
	var with_dash := _rollout(game, mem, input, policy_name, ticks)
	var walk: Dictionary = input.duplicate()
	walk.dashPressed = false
	var without_dash := _rollout(game, mem, walk, COUNTERFACTUAL_POLICY, ticks)
	audit.dashes += 1.0
	if without_dash > 0.0 and with_dash == 0.0:
		audit.decisive += 1.0
	elif with_dash > without_dash:
		audit.harmful += 1.0
	elif with_dash > 0.0:
		audit.bothHit += 1.0
	else:
		audit.idle += 1.0

static func _any_open(doors: Array) -> bool:
	for d in doors:
		if D6Js.truthy(d.get("open")):
			return true
	return false

## Blocage : salle nettoyée depuis STALL_SECONDS sans sortie. Rend un diagnostic (disposition,
## objet d'interaction inaccessible ?) ou null si la partie avance.
static func _detect_stall(game: Dictionary, rec: Dictionary):
	var room: Dictionary = game.room
	if not is_same(rec.stallRoom, room):
		rec.stallRoom = room
		rec.stallTick = -1.0
	if not D6Js.truthy(room.get("cleared")):
		return null
	if rec.stallTick < 0.0:
		rec.stallTick = game.tick
	if (game.tick - rec.stallTick) * DT < STALL_SECONDS:
		return null
	var it = room.get("interact")
	var interact = null
	if it != null:
		interact = {"kind": it.get("kind"), "used": it.get("used"), "x": it.x, "y": it.y, "blocked": D6Physics.point_blocked(room, it.x, it.y, 0.0)}
	return {
		"floor": game.run.floor,
		"layout": room.get("layout"),
		"doorsOpen": _any_open(room.doors),
		"interact": interact,
		"player": {"x": D6Js.jround(game.player.x), "y": D6Js.jround(game.player.y)},
	}

## Résout le menu ouvert ; rend false si le bot n'arrive pas à en sortir.
static func _settle_choice(game: Dictionary, policy_name: String) -> bool:
	var i := 0
	while i < MAX_CHOICE_ATTEMPTS and game.mode == "choice":
		if not Bots.resolve_choice(game, policy_name):
			return false
		i += 1
	return game.mode != "choice"

## Issue de la partie si elle est finie avant de jouer l'image, "" sinon.
static func _outcome_now(game: Dictionary, policy_name: String, target_floor: float, max_ticks: float) -> String:
	if game.mode == "choice" and not _settle_choice(game, policy_name):
		return "stuck"
	if game.mode == "town":
		return "town"
	if game.run.floor >= target_floor:
		return "section"
	if game.mode == "dead":
		return "dead"
	if game.mode == "victory":
		return "victory"
	if game.mode != "play":
		return "stuck"
	if game.tick >= max_ticks:
		return "timeout"
	return ""

## Boucle de jeu jusqu'à l'issue ; rend 'section' | 'town' | 'dead' | 'victory' | 'timeout' |
## 'stuck' | 'softlock'. 'town' : le héros a pris le portail de la Ville (sur demande seulement) —
## la partie ne bouge plus, l'épisode s'arrête au lieu de tourner sans fin.
static func _play_until_outcome(game: Dictionary, policy_name: String, rec: Dictionary, target_floor: float, max_ticks: float, dash_audit: bool, mem: Dictionary) -> String:
	while true:
		var outcome := _outcome_now(game, policy_name, target_floor, max_ticks)
		if outcome != "":
			return outcome
		rec.stall = _detect_stall(game, rec)
		if rec.stall != null:
			return "softlock"
		var input := Bots.play(policy_name, game, mem)
		if dash_audit and D6Js.truthy(input.get("dashPressed")) and game.player.dashCharges >= 1.0:
			_audit_dash(game, mem, input, policy_name, rec.audit)
		if game.hitstop > 0.0 or game.player.freeze > 0.0:
			rec.frozenTicks += 1.0
		D6Game.step_game(game, input)
		_consume_events(game, rec)
	return "stuck"

## Réglages de la partie : options.tuning, plus les variantes du labo (options.lab) fusionnées.
static func _episode_tuning(options: Dictionary):
	var tuning = options.get("tuning")
	var lab = options.get("lab")
	if not (lab is Dictionary):
		return tuning
	var out: Dictionary = tuning.duplicate() if tuning is Dictionary else {}
	var merged: Dictionary = out.lab.duplicate() if out.get("lab") is Dictionary else {}
	merged.merge(lab, true)
	out.lab = merged
	return out

## Joue une partie complète avec une politique. Rend le résumé mesuré de la partie.
## options : { floors, minutes, tuning, meta, lab, dashAudit, town, dashAttack }
##   meta       — profil permanent de départ (classe, arme, kit : outils/classes.gd) ; absent = profil neuf ;
##   lab        — variantes du labo ({hitstop: 'local'}…), fusionnées dans le tuning ;
##   dashAudit  — (défaut false) n'audite que la politique skilled ;
##   town       — le bot prend le portail de la Ville après le Gardien (fin d'épisode 'town') ;
##   dashAttack — habitude « dash puis frappe » du bot (mesure D5).
static func run_episode(policy_name: String, seed_n: float, options: Dictionary = {}) -> Dictionary:
	var floors: float = D6Js.nz(options.get("floors"), DEFAULT_FLOORS)
	var minutes: float = D6Js.nz(options.get("minutes"), DEFAULT_MINUTES)
	assert(Bots.has_policy(policy_name), "politique inconnue : %s" % policy_name)
	var opts := {"seed": seed_n}
	var tuning = _episode_tuning(options)
	if tuning != null:
		opts.tuning = tuning
	if options.get("meta") != null:
		opts.meta = options.meta
	var game: Dictionary = D6Game.create_game(opts)
	var rec := _new_recorder()
	_consume_events(game, rec)
	var max_ticks := D6Js.jround((minutes * SECONDS_PER_MINUTE) / DT)
	var dash_audit: bool = D6Js.truthy(options.get("dashAudit")) and policy_name == AUDITED_POLICY
	var mem := {"wantTown": D6Js.truthy(options.get("town")), "dashAttack": D6Js.truthy(options.get("dashAttack"))}
	var outcome := _play_until_outcome(game, policy_name, rec, floors + 1.0, max_ticks, dash_audit, mem)
	_close_room(rec, game)
	var lab: Dictionary = game.tuning.lab.duplicate() if game.tuning.get("lab") is Dictionary else {}
	return summarize(game, rec, {"policy": policy_name, "seed": seed_n, "outcome": outcome, "floors": floors, "dashAudit": dash_audit, "lab": lab})

# ---------------------------------------------------------------- résumé

static func _sum(rooms: Array, key: String) -> float:
	var s := 0.0
	for r in rooms:
		s += r[key]
	return s

static func _has_number(arr: Array, v: float) -> bool:
	for x in arr:
		if float(x) == v:
			return true
	return false

static func _boss_time(room_times: Array):
	for r in room_times:
		if r.kind == "boss":
			return r.get("time")
	return null

## Mesures de rythme, rapportées à la minute de partie.
static func _rates(game: Dictionary, rec: Dictionary) -> Dictionary:
	var tel: Dictionary = game.telemetry
	var minutes := maxf(1e-9, (game.tick * DT) / SECONDS_PER_MINUTE)
	var actions: float = tel.attacks + tel.dashes + tel.skillCasts + tel.gadgetUses + tel.superUses
	var events := 0.0
	for n in rec.events.values():
		events += n
	return {
		"hitsTakenPerMin": tel.hitsTaken / minutes,
		"dodges": tel.dodges,
		"dodgesPerMin": tel.dodges / minutes,
		"dashesPerMin": tel.dashes / minutes,
		"actionsPerMin": actions / minutes,
		"hitsToKill": tel.hitsLanded / tel.kills if tel.kills != 0.0 else null,
		"eventsPerMin": events / minutes,
	}

## Mesures des salles de combat JOUÉES (étage <= floors).
static func _combat(played: Array) -> Dictionary:
	var combat_rooms: Array = played.filter(func(r): return COMBAT_KINDS.has(r.kind))
	var damage := _sum(combat_rooms, "damage")
	var n := float(combat_rooms.size())
	return {
		"combatRooms": n,
		"combatDamage": damage,
		"combatSeconds": _sum(combat_rooms, "combatSeconds"),
		"realCombatSeconds": _sum(combat_rooms, "realCombatSeconds"),
		"realRoomSeconds": combat_rooms.filter(func(r): return r.kind != "boss").map(func(r): return r.realCombatSeconds),
		"combatHits": _sum(combat_rooms, "hits"),
		"damagePerRoom": damage / n if n != 0.0 else null,
	}

## Le résumé d'une partie (mêmes clés que summarize de playtest.mjs).
static func summarize(game: Dictionary, rec: Dictionary, meta: Dictionary) -> Dictionary:
	var tel: Dictionary = game.telemetry
	# Salles jouées seulement : l'étage floors + 1 (atteint = section battue) n'a pas été joué.
	var played: Array = rec.rooms.filter(func(r): return r.floor <= meta.floors)
	# Section battue = étage floors + 1 atteint, ou Gardien vaincu puis portail de la Ville pris
	# (son checkpoint, floors + 1, est alors ouvert : la partie part d'un profil neuf).
	var checkpoint_open := _has_number(game.meta.checkpoints, meta.floors + 1.0)
	var out: Dictionary = meta.duplicate()
	out.merge({
		"sectionCleared": game.run.floor > meta.floors or (meta.outcome == "town" and checkpoint_open),
		"checkpoints": game.meta.checkpoints.duplicate(),
		"floorReached": game.run.floor,
		"simSeconds": game.tick * DT,
		"hpLeft": game.player.hp,
		"deaths": tel.deaths,
		"deathCauses": tel.deathCauses.duplicate(),
		"attacks": tel.attacks,
		"strikes": rec.strikes,
		"frozenShare": rec.frozenTicks / game.tick if game.tick != 0.0 else 0.0,
		"damageTaken": tel.damageTaken,
		"kills": tel.kills,
		"superUses": tel.superUses,
		"gadgetUses": tel.gadgetUses,
		"skillCasts": tel.skillCasts,
		"wallSlams": tel.wallSlams,
		"deflects": tel.deflects,
		"roomTimes": tel.roomTimes.filter(func(r): return r.kind != "boss").map(func(r): return r.time),
		"bossFightSeconds": _boss_time(tel.roomTimes),
		"killTimes": tel.killTimes.map(func(k): return {"kind": k.kind, "life": k.life}),
		"eventCounts": rec.events,
		"rooms": played, # détail par salle jouée : dégâts, coups reçus, durées
		"stall": rec.stall,
		"dashAudit": rec.audit.duplicate() if meta.dashAudit else null,
	}, true)
	out.merge(_combat(played), true)
	out.merge(_rates(game, rec), true)
	return out
