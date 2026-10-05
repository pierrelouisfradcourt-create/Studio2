extends RefCounted
## ARBRE DE COMPÉTENCES (combat V3, étape 3) — chargé par preload (D6Profile, D6Game, D6Stats,
## D6Combat, D6Run), sans class_name. Les nombres et les nœuds : data/arbres.json (tuning.tree).
##
## PERMANENT, un arbre par classe, dans le profil :
##   profile.tree[classe] = {xp, level, ranks: {nœud: rangs ACHETÉS}, choices: {nœud: amélioration},
##                           guardians: [modèles de Gardien vaincus avec cette classe]}
## RANG d'un nœud = rangs achetés + 1 rang OFFERT si c'est une compétence que le profil possède
## d'office (profile.unlocked.skills / gadgets : le kit de départ de la classe, et tout ce qu'un
## ancien profil avait débloqué en Âmes). Un rang offert ne coûte aucun point et survit à la
## respécialisation. Le rang 1 d'une compétence la DÉBLOQUE (elle devient plaçable).
## POINTS = niveaux gagnés + Gardiens vaincus pour la première fois − rangs achetés.
##
## EN PARTIE (apply, une fois à la création) : les rangs et l'amélioration exclusive de chaque
## compétence sont écrits dans la copie de réglages de la partie (game.tuning) ; les passifs
## s'ajoutent aux statistiques à chaque calcul (add_stats, add_procs). Un arbre vide ne change rien.
## L'expérience est versée au profil (game.meta) à chaque ennemi tué, comme les Âmes.

const TREE_SCHEMA := 5.0 # version du profil qui porte l'arbre : une sauvegarde plus ancienne est migrée
const FIRST_RANKED := {"skill": 2.0} # `ranks` d'une compétence commence au rang 2 (le rang 1 = classes.json)
const TABLES := ["skills", "gadgets"]
const HUNDRED := 100.0
const ROUND := 100.0 # un nombre affiché garde deux décimales au plus
## Nombres qu'une amélioration exclusive peut AJOUTER à une compétence (lus par kit_*, player,
## projectiles) ; tout autre champ d'un `set` doit déjà exister dans la compétence (donnees.gd).
const EXTRA_FIELDS := [
	"blastRadius", "blastDamage", "pullGap", "pullMass", "fireDuration", "fireDps", "vuln", "vulnMult", "noPull", "pierce", "count", "spread",
	"healPerHit", "rebound", "surge", "surgeMult", "chill", "chillMult", "ringDist", "ward", "stun", "duration", "strikes",
	"targets", "interval", "damage", "damagePerTick", "damageMult", "knockback",
]

# ---------------------------------------------------------------- lecture des données

static func cfg(tuning: Dictionary) -> Dictionary:
	var c = tuning.get("tree")
	return c if c is Dictionary else {}

## Les nœuds de l'arbre d'une classe, dans l'ordre des données ([] : classe sans arbre).
static func nodes(tuning: Dictionary, class_id) -> Array:
	var classes = cfg(tuning).get("classes")
	var c = classes.get(class_id) if classes is Dictionary else null
	return c.nodes if c is Dictionary else []

static func node(tuning: Dictionary, class_id, node_id):
	for n in nodes(tuning, class_id):
		if n.id == node_id:
			return n
	return null

## Le nœud de compétence qui porte l'action `action_id`, ou null.
static func skill_node(tuning: Dictionary, class_id, action_id):
	for n in nodes(tuning, class_id):
		if n.kind == "skill" and n.skill == action_id:
			return n
	return null

## Table de réglages ("skills" | "gadgets") de l'action d'un nœud de compétence ; "" si inconnue.
static func table_of(tuning: Dictionary, action_id) -> String:
	for table in TABLES:
		if tuning[table].get(action_id) is Dictionary:
			return table
	return ""

static func max_rank(tuning: Dictionary, n: Dictionary) -> float:
	return D6Js.nz(n.get("maxRank"), cfg(tuning).skillRanks if n.kind == "skill" else 1.0)

## Expérience demandée pour passer du niveau `level` au suivant.
static func xp_need(tuning: Dictionary, level: float) -> float:
	var curve: Dictionary = cfg(tuning).curve
	return curve.base + curve.perLevel * (level - 1.0)

# ---------------------------------------------------------------- état dans le profil

static func new_state() -> Dictionary:
	return {"xp": 0.0, "level": 1.0, "ranks": {}, "choices": {}, "guardians": []}

## L'état de l'arbre d'une classe dans le profil (créé à la demande).
static func state(profile: Dictionary, class_id) -> Dictionary:
	if not (profile.get("tree") is Dictionary):
		profile.tree = {}
	if not (profile.tree.get(class_id) is Dictionary):
		profile.tree[class_id] = new_state()
	return profile.tree[class_id]

## Le rang 1 de ce nœud est-il OFFERT ? (compétence possédée d'office : profile.unlocked)
static func is_free(profile: Dictionary, tuning: Dictionary, n: Dictionary) -> bool:
	if n.kind != "skill":
		return false
	var table := table_of(tuning, n.skill)
	return table != "" and profile.unlocked[table].has(n.skill)

static func bought(profile: Dictionary, class_id, n: Dictionary) -> float:
	return D6Js.nz(state(profile, class_id).ranks.get(n.id), 0.0)

static func rank(profile: Dictionary, tuning: Dictionary, class_id, n: Dictionary) -> float:
	return bought(profile, class_id, n) + (1.0 if is_free(profile, tuning, n) else 0.0)

## La classe possède-t-elle l'action `id` de la table `table` ? Par l'arbre (rang 1 au moins) ; une
## action sans nœud (contenu sans arbre) : par les déblocages du profil, comme avant.
static func owns(profile: Dictionary, tuning: Dictionary, class_id, table: String, id) -> bool:
	var n = skill_node(tuning, class_id, id)
	if n == null:
		return profile.unlocked[table].has(id)
	return rank(profile, tuning, class_id, n) >= 1.0

static func spent(profile: Dictionary, class_id) -> float:
	var total := 0.0
	for v in state(profile, class_id).ranks.values():
		total += v
	return total

## Points gagnés par la classe : ses niveaux, et ses Gardiens vaincus pour la première fois.
static func earned(profile: Dictionary, tuning: Dictionary, class_id) -> float:
	var st := state(profile, class_id)
	var c := cfg(tuning)
	return (st.level - 1.0) * c.pointsPerLevel + float(st.guardians.size()) * c.pointsPerGuardian

static func points(profile: Dictionary, tuning: Dictionary, class_id) -> float:
	return earned(profile, tuning, class_id) - spent(profile, class_id)

static func tier_open(profile: Dictionary, tuning: Dictionary, class_id, tier) -> bool:
	return spent(profile, class_id) >= cfg(tuning).tiers[int(tier)].need

static func respec_cost(profile: Dictionary, tuning: Dictionary, class_id) -> float:
	var r: Dictionary = cfg(tuning).respec
	return r.base + r.perPoint * spent(profile, class_id)

# ---------------------------------------------------------------- opérations de la Ville

## Raison pour laquelle un rang du nœud ne s'achète pas ("" : il s'achète).
static func buy_block(profile: Dictionary, tuning: Dictionary, class_id, n: Dictionary) -> String:
	if rank(profile, tuning, class_id, n) >= max_rank(tuning, n):
		return "rang maximal"
	if not tier_open(profile, tuning, class_id, n.tier):
		var tier: Dictionary = cfg(tuning).tiers[int(n.tier)]
		return "étage %s fermé : %s points à dépenser d'abord" % [tier.name, D6Js.num_str(tier.need)]
	if points(profile, tuning, class_id) < 1.0:
		return "aucun point à dépenser"
	return ""

static func buy(profile: Dictionary, tuning: Dictionary, class_id, node_id) -> Dictionary:
	var n = node(tuning, class_id, node_id)
	if n == null or not profile.unlocked.classes.has(class_id):
		return {"ok": false, "reason": "inconnu"}
	var block := buy_block(profile, tuning, class_id, n)
	if block != "":
		return {"ok": false, "reason": block}
	state(profile, class_id).ranks[n.id] = bought(profile, class_id, n) + 1.0
	return {"ok": true}

static func _choice(n: Dictionary, choice_id):
	var list = n.get("choices")
	if list is Array:
		for ch in list:
			if ch.id == choice_id:
				return ch
	return null

## Raison pour laquelle l'amélioration `ch` ne se prend pas ("" : elle se prend).
static func choose_block(profile: Dictionary, tuning: Dictionary, class_id, n: Dictionary, ch: Dictionary) -> String:
	var need: float = cfg(tuning).choiceRank
	var taken = state(profile, class_id).choices.get(n.id)
	if taken == ch.id:
		return "déjà prise"
	if taken != null:
		return "l'autre amélioration est prise"
	if rank(profile, tuning, class_id, n) < need:
		return "rang %s requis" % D6Js.num_str(need)
	return ""

static func choose(profile: Dictionary, tuning: Dictionary, class_id, node_id, choice_id) -> Dictionary:
	var n = node(tuning, class_id, node_id)
	var ch = _choice(n, choice_id) if n != null else null
	if ch == null or not profile.unlocked.classes.has(class_id):
		return {"ok": false, "reason": "inconnu"}
	var block := choose_block(profile, tuning, class_id, n, ch)
	if block != "":
		return {"ok": false, "reason": block}
	state(profile, class_id).choices[n.id] = ch.id
	return {"ok": true}

## Rend TOUS les points de la classe contre de l'or : rangs achetés et améliorations exclusives
## s'effacent (les rangs offerts restent). Les emplacements : à l'appelant (D6Profile.tree_respec).
static func respec(profile: Dictionary, tuning: Dictionary, class_id) -> Dictionary:
	if not profile.unlocked.classes.has(class_id) or nodes(tuning, class_id).is_empty():
		return {"ok": false, "reason": "inconnu"}
	var st := state(profile, class_id)
	if spent(profile, class_id) <= 0.0 and st.choices.is_empty():
		return {"ok": false, "reason": "rien à rendre"}
	var cost := respec_cost(profile, tuning, class_id)
	if profile.gold < cost:
		return {"ok": false, "reason": "or insuffisant"}
	profile.gold -= cost
	st.ranks = {}
	st.choices = {}
	return {"ok": true}

# ---------------------------------------------------------------- expérience

## Ajoute de l'expérience à un état d'arbre ; rend le nombre de niveaux passés.
static func add_xp(st: Dictionary, tuning: Dictionary, amount: float) -> float:
	var top: float = cfg(tuning).maxLevel
	var gained := 0.0
	st.xp += amount
	while st.level < top and st.xp >= xp_need(tuning, st.level):
		st.xp -= xp_need(tuning, st.level)
		st.level += 1.0
		gained += 1.0
	if st.level >= top:
		st.xp = 0.0
	return gained

## La partie verse-t-elle de l'expérience ? Jamais en arène d'essai ni à l'entraînement.
static func _counts(game: Dictionary) -> bool:
	return not D6Js.truthy(game.get("sandbox")) and not D6Js.truthy(game.get("practice")) and not cfg(game.tuning).is_empty()

## Expérience d'une mise à mort (`kind` : "kill" | "elite" | "guardian"), à l'échelle bornée de la
## profondeur, versée à la classe jouée. Chaque niveau passé émet `levelUp`.
static func gain(game: Dictionary, kind: String) -> void:
	if not _counts(game):
		return
	var c := cfg(game.tuning)
	var depth: float = minf(c.xp.depthCap, 1.0 + c.xp.depthStep * (game.info.section - 1.0))
	var amount: float = D6Js.jround(c.xp[kind] * depth)
	var class_id = D6Loadout.class_id_of(game)
	var st := state(game.meta, class_id)
	var levels := add_xp(st, game.tuning, amount)
	game.telemetry.xpEarned += amount
	game.telemetry.levelsGained += levels
	if levels > 0.0:
		D6State.emit(game, "levelUp", {"classId": class_id, "level": st.level, "levels": levels, "points": points(game.meta, game.tuning, class_id)})

## Gardien `model` vaincu : la première fois avec cette classe, un point de plus.
static func guardian_down(game: Dictionary, model) -> void:
	if not _counts(game):
		return
	var class_id = D6Loadout.class_id_of(game)
	var st := state(game.meta, class_id)
	if st.guardians.has(model):
		return
	st.guardians.append(model)
	D6State.emit(game, "treePoint", {"classId": class_id, "guardian": model, "points": points(game.meta, game.tuning, class_id)})

## Bilan de la descente pour l'affichage (écran de mort, de victoire) : expérience gagnée, niveaux
## passés, niveau et points de la classe jouée.
static func recap(game: Dictionary) -> Dictionary:
	var class_id = D6Loadout.class_id_of(game)
	var st := state(game.meta, class_id)
	return {
		"classId": class_id, "xpEarned": game.telemetry.xpEarned, "levelsGained": game.telemetry.levelsGained,
		"level": st.level, "points": points(game.meta, game.tuning, class_id),
	}

# ---------------------------------------------------------------- en partie

## Écrit dans les réglages de la partie les rangs et l'amélioration exclusive de chaque nœud de la
## classe jouée. Appelé UNE fois, à la création de la partie (l'arbre ne change pas en descente).
static func apply(game: Dictionary) -> void:
	var t: Dictionary = game.tuning
	var class_id = D6Loadout.class_id_of(game)
	for n in nodes(t, class_id):
		var r := rank(game.meta, t, class_id, n)
		var def = _target(t, class_id, n)
		if r < 1.0 or not (def is Dictionary):
			continue
		_write_rank(def, n, r)
		var ch = _choice(n, state(game.meta, class_id).choices.get(n.id))
		if ch != null and r >= cfg(t).choiceRank:
			def.merge(D6Js.clone(ch.set), true)

## Les réglages qu'un nœud modifie : sa compétence, ou l'ultime de la classe ; null pour un passif.
static func _target(t: Dictionary, class_id, n: Dictionary):
	if n.kind == "skill":
		var table := table_of(t, n.skill)
		return t[table][n.skill] if table != "" else null
	if n.kind == "ultimate":
		return t.supers.get(t.classes[class_id].get("super"))
	return null

## Valeur du nombre `field` d'un nœud au rang `r` ; null si ce rang garde le nombre de base.
static func rank_value(n: Dictionary, field: String, r: float):
	var i := int(r - FIRST_RANKED.get(n.kind, 1.0))
	var list: Array = n.ranks[field]
	return list[mini(i, list.size() - 1)] if i >= 0 else null

static func _write_rank(def: Dictionary, n: Dictionary, r: float) -> void:
	var ranks = n.get("ranks")
	if not (ranks is Dictionary):
		return
	for field in ranks:
		var v = rank_value(n, field, r)
		if v != null:
			def[field] = v

## PASSIFS de la classe jouée (nœuds à `stat`) : `add.call(stat, valeur)` pour chacun.
static func add_stats(game: Dictionary, add: Callable) -> void:
	var class_id = D6Loadout.class_id_of(game)
	for n in nodes(game.tuning, class_id):
		var r := rank(game.meta, game.tuning, class_id, n)
		if r > 0.0 and n.get("stat") != null:
			add.call(n.stat, n.perRank * r)

## Passifs à `proc` (lus par D6Combat comme ceux des bénédictions) : ajoutés à la liste.
static func add_procs(game: Dictionary, procs: Array) -> void:
	var class_id = D6Loadout.class_id_of(game)
	for n in nodes(game.tuning, class_id):
		var r := rank(game.meta, game.tuning, class_id, n)
		if r > 0.0 and n.get("proc") is Dictionary:
			var pr: Dictionary = n.proc.duplicate()
			pr.value = n.perRank * r
			procs.append(pr)

# ---------------------------------------------------------------- lecture pour l'affichage

## Nombre écrit pour le joueur : deux décimales au plus, virgule française.
static func fr(v) -> String:
	return D6Js.num_str(D6Js.jround(float(v) * ROUND) / ROUND).replace(".", ",")

static func _shown(tuning: Dictionary, field: String, v) -> String:
	if v is bool or not (v is float or v is int):
		return str(v)
	return fr(v * HUNDRED if cfg(tuning).pctFields.has(field) else v)

## Texte d'une amélioration exclusive : chaque {champ} est remplacé par le nombre de son `set`.
static func choice_text(tuning: Dictionary, ch: Dictionary) -> String:
	var text: String = ch.text
	for field in ch.set:
		text = text.replace("{%s}" % field, _shown(tuning, field, ch.set[field]))
	return text

## Les nombres d'un nœud à `ranks` au rang `r`, dits par les libellés des données.
static func ranks_text(tuning: Dictionary, class_id, n: Dictionary, r: float) -> String:
	var parts: Array = []
	var def = _base_target(tuning, class_id, n)
	for field in n.ranks:
		var v = rank_value(n, field, r)
		if v == null:
			v = def.get(field) if def is Dictionary else null
		if v != null:
			parts.append(String(cfg(tuning).labels.get(field, field + " {v}")).replace("{v}", _shown(tuning, field, v)))
	return ", ".join(parts)

## Les réglages de BASE (data/, sans arbre) qu'un nœud modifie.
static func _base_target(_tuning: Dictionary, class_id, n: Dictionary):
	return _target(D6Data.default_tuning(), class_id, n)

## Texte d'un nœud au rang `r` ("" au rang 0 d'un passif).
static func rank_text(tuning: Dictionary, class_id, n: Dictionary, r: float) -> String:
	if n.get("ranks") is Dictionary:
		if r < 1.0:
			return ""
		return "Rang %s : %s." % [D6Js.num_str(r), ranks_text(tuning, class_id, n, r)]
	if r < 1.0:
		return ""
	var v: float = absf(n.perRank * r) * (HUNDRED if D6Js.truthy(n.get("pct")) else 1.0)
	return String(n.text).replace("{v}", fr(v))

## Nom, pictogramme et description de base d'un nœud (ceux de sa compétence, de l'ultime, ou les siens).
static func _identity(tuning: Dictionary, class_id, n: Dictionary) -> Dictionary:
	var def = _base_target(tuning, class_id, n)
	var c: Dictionary = tuning.classes[class_id]
	if n.kind == "skill" and def is Dictionary:
		return {"name": def.name, "icon": D6Js.nz(def.get("icon"), "skill" if c.skills.has(n.skill) else "gadget"), "about": D6Js.nz(def.get("text"), "")}
	if n.kind == "ultimate" and def is Dictionary:
		return {"name": n.name, "icon": D6Js.nz(def.get("icon"), "super"), "about": def.name}
	var move = tuning.moves.get(c.get("move")) if n.kind == "move" else null
	return {"name": n.name, "icon": D6Js.nz(move.get("icon"), "dash") if move is Dictionary else "", "about": ""}

static func _node_view(profile: Dictionary, tuning: Dictionary, class_id, n: Dictionary) -> Dictionary:
	var r := rank(profile, tuning, class_id, n)
	var top := max_rank(tuning, n)
	var who := _identity(tuning, class_id, n)
	var now := rank_text(tuning, class_id, n, r)
	if r < 1.0 and n.kind == "skill":
		now = "Verrouillée. %s" % who.about
	var next := rank_text(tuning, class_id, n, r + 1.0) if r < top else ""
	if r < 1.0 and n.kind == "skill":
		next = "Rang 1 : débloque la compétence."
	var block := buy_block(profile, tuning, class_id, n)
	var choices: Array = []
	if n.get("choices") is Array:
		for ch in n.choices:
			var why := choose_block(profile, tuning, class_id, n, ch)
			choices.append({
				"id": ch.id, "name": ch.name, "text": choice_text(tuning, ch),
				"taken": state(profile, class_id).choices.get(n.id) == ch.id, "canTake": why == "", "reason": why,
			})
	return {
		"id": n.id, "kind": n.kind, "name": who.name, "icon": who.icon, "text": "\n".join([now, next].filter(func(s): return s != "")),
		"now": now, "next": next, "rank": r, "maxRank": top, "free": is_free(profile, tuning, n),
		"canBuy": block == "", "reason": block, "choices": choices,
	}

## Ce que l'affichage lit de l'arbre d'une classe (D6Profile.tree_view) : niveau, expérience,
## points, étages et nœuds avec leurs textes chiffrés, prix de la respécialisation.
static func view(profile: Dictionary, tuning: Dictionary, class_id) -> Dictionary:
	var st := state(profile, class_id)
	var c := cfg(tuning)
	var tiers: Array = []
	for i in c.tiers.size():
		var shown: Array = []
		for n in nodes(tuning, class_id):
			if int(n.tier) == i:
				shown.append(_node_view(profile, tuning, class_id, n))
		tiers.append({"name": c.tiers[i].name, "need": c.tiers[i].need, "open": tier_open(profile, tuning, class_id, i), "nodes": shown})
	return {
		"level": st.level, "maxLevel": c.maxLevel, "xp": st.xp, "xpNext": xp_need(tuning, st.level) if st.level < c.maxLevel else 0.0,
		"points": points(profile, tuning, class_id), "spent": spent(profile, class_id), "choiceRank": c.choiceRank,
		"tiers": tiers, "respecCost": respec_cost(profile, tuning, class_id),
	}

# ---------------------------------------------------------------- sauvegarde : relecture et migration

static func _int_in(v, lo: float, hi: float) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v)) and float(v) == floorf(float(v)) and v >= lo and v <= hi

## L'arbre d'un profil relu, classe par classe (celles qu'il possède) ; `schema` : la version de la
## sauvegarde. Une sauvegarde d'AVANT l'arbre est migrée (migrate).
static func sanitize(out: Dictionary, raw: Dictionary, tuning: Dictionary) -> void:
	var src = raw.get("tree")
	out.tree = {}
	for class_id in out.unlocked.classes:
		out.tree[class_id] = _clean(out, tuning, class_id, src.get(class_id) if src is Dictionary else null)
	var schema = raw.get("schema")
	if not ((typeof(schema) == TYPE_FLOAT or typeof(schema) == TYPE_INT) and schema >= TREE_SCHEMA):
		migrate(out, tuning)

## L'état d'arbre d'une classe, validé champ par champ. Des rangs qui coûtent plus de points que la
## classe n'en a gagné (réglage changé, fichier retouché) sont rendus : l'arbre repart vide.
static func _clean(out: Dictionary, tuning: Dictionary, class_id, raw) -> Dictionary:
	var st := new_state()
	out.tree[class_id] = st
	if not (raw is Dictionary) or cfg(tuning).is_empty():
		return st
	var c := cfg(tuning)
	st.level = float(raw.level) if _int_in(raw.get("level"), 1.0, c.maxLevel) else 1.0
	var xp = raw.get("xp")
	if (typeof(xp) == TYPE_FLOAT or typeof(xp) == TYPE_INT) and is_finite(float(xp)) and xp >= 0.0:
		add_xp(st, tuning, floorf(xp))
	if raw.get("guardians") is Array:
		for model in raw.guardians:
			if (model is String or model is StringName) and tuning.boss.has(model) and not st.guardians.has(model):
				st.guardians.append(model)
	var ranks = raw.get("ranks")
	var choices = raw.get("choices")
	for n in nodes(tuning, class_id):
		var room := max_rank(tuning, n) - (1.0 if is_free(out, tuning, n) else 0.0)
		if ranks is Dictionary and _int_in(ranks.get(n.id), 1.0, room):
			st.ranks[n.id] = float(ranks[n.id])
		var ch = _choice(n, choices.get(n.id)) if choices is Dictionary else null
		if ch != null and rank(out, tuning, class_id, n) >= c.choiceRank:
			st.choices[n.id] = ch.id
	if spent(out, class_id) > earned(out, tuning, class_id):
		st.ranks = {}
		st.choices = {}
	return st

## MIGRATION d'un profil d'avant l'arbre. Les compétences déjà débloquées gardent leur rang 1 (il
## est offert : profile.unlocked, rien à faire ici), les Âmes dépensées ne sont pas reprises.
## L'AVANCE : la classe portée reçoit l'expérience que le profil PROUVE — chaque ennemi tué
## (stats.kills) et chaque Gardien vaincu (guardians), au tarif de base, sans bonus de profondeur —
## et un point par modèle de Gardien déjà vaincu. Les autres classes partent du niveau 1 : le profil
## ne dit pas avec laquelle il a joué.
static func migrate(out: Dictionary, tuning: Dictionary) -> void:
	var c := cfg(tuning)
	if c.is_empty():
		return
	var st := state(out, out.loadout.classId)
	var xp: float = out.stats.kills * c.xp.kill
	for model in out.guardians:
		xp += out.guardians[model] * c.xp.guardian
		if out.guardians[model] > 0.0 and not st.guardians.has(model):
			st.guardians.append(model)
	add_xp(st, tuning, xp)
