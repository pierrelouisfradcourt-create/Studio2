extends SceneTree
## MESURE EN PROFONDEUR du combat V3 (étape 5) : tout l'équilibrage de l'arbre, des ultimes et des
## compétences neuves a été mesuré en section 1 ; le joueur, lui, joue à l'étage 126. Ici le même bot
## (habile) joue chaque classe à TROIS profondeurs — les sections SECTIONS, chacune de son premier
## étage (un checkpoint) à son Gardien — avec l'arbre VIDE puis l'arbre PLEIN, et une fois SANS son
## déplacement de classe (arbre vide). Écrit _dev/rapports/profondeur_mesures.md (les tableaux) ; la
## lecture est dans _dev/rapports/profondeur.md et design/COMBAT_V3.md, « Étape 5 ».
##
## COMMENT LA PROFONDEUR EST ATTEINTE (honnêtement, comme une reprise depuis un point) : la partie
## commence au premier étage de la section, sans bénédiction. Section 1 : le héros neuf des oracles
## (arme de départ, aucune amélioration de la Ville). Plus bas : toutes les améliorations de la
## Ville achetées, et trois objets de rareté RARETE du niveau de l'étage qui précède (arme de la
## classe, armure, talisman), fabriqués par les règles (D6Loot) — ce qu'un joueur porte en y arrivant.
##
## ARBRE PLEIN « raisonnable » (33 points, la politique écrite dans full_tree) : niveau maximum,
## tous les Gardiens vaincus ; on achète toujours le premier rang achetable de cette liste — 1. les
## trois compétences JOUÉES, 2. les passifs, 3. le déplacement et l'ultime, 4. les autres
## compétences, dans l'ordre de l'arbre — et la première amélioration de chaque compétence jouée.
##
##   <godot> --headless --path . --script res://outils/profondeur.gd -- [graines=12] [--no-md]
##   … -- [graines] --tranche i/n --sortie <fichier.json>     une part des mesures (un processus)
##   … -- [graines] --agreger <dossier>                       réunit les parts, écrit le rapport
##   bash outils/profondeur.sh [graines]                      les trois, sur plusieurs processus
##
## Ce n'est PAS un oracle (aucun seuil, sortie 0) : ce sont des mesures pour juger. Un bot mesure
## des conséquences, pas le plaisir ; et il n'est pas un joueur : il ne construit pas son héros.

const Episode = preload("res://outils/bots/episode.gd")
const Classes = preload("res://outils/classes.gd")
const Arbre = preload("res://sim/tree.gd")
const Bots = preload("res://outils/bots/bots.gd")

const DEFAULT_SEEDS := 12
const MD := "_dev/rapports/profondeur_mesures.md"
const POLICY := "skilled"
const NO_MOVE_POLICY := "noDash"
const SECTIONS := [1.0, 7.0, 19.0] # premiers étages 1, 109 et 325
const RARETE := "rare"
const MAX_MINUTES := 30.0
const SECONDS_PER_MINUTE := 60.0
const GRAINE_OBJETS := 666.0
const PCT := 100.0
const PLANCHER_RAPPORT := 0.2 # % des PV par salle : en dessous, « avec le geste » est presque zéro et le rapport ne veut plus rien dire
## Source d'un coup (`hit.kind`) -> ce qu'elle mesure. Pendant la Forme du Damné, les coups d'arme
## (les griffes) comptent pour l'ULTIME.
const PARTS := {"melee": "base", "strike": "base", "skill": "competences", "gadget": "competences", "super": "ultime", "ally": "ultime"}
const MODES := ["vide", "plein", "sansGeste"]
const MODE_NAMES := {"vide": "arbre vide", "plein": "arbre plein", "sansGeste": "arbre vide, sans déplacement"}

func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var seeds := DEFAULT_SEEDS
	var slice := 0
	var slices := 1
	var out_path := ""
	var merge_dir := ""
	for i in argv.size():
		if argv[i].is_valid_int() and (i == 0 or not argv[i - 1].begins_with("--")):
			seeds = int(argv[i])
		elif argv[i] == "--tranche" and i + 1 < argv.size():
			slice = int(argv[i + 1].get_slice("/", 0))
			slices = maxi(1, int(argv[i + 1].get_slice("/", 1)))
		elif argv[i] == "--sortie" and i + 1 < argv.size():
			out_path = argv[i + 1]
		elif argv[i] == "--agreger" and i + 1 < argv.size():
			merge_dir = argv[i + 1]
	var tuning: Dictionary = D6Data.create_tuning()
	var all_tasks := tasks(tuning, seeds)
	var rows := {}
	if merge_dir != "":
		rows = _load(merge_dir)
	else:
		for i in all_tasks.size():
			if i % slices == slice:
				rows[str(i)] = run_one(tuning, all_tasks[i])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows))
		f.close()
		quit(0)
		return
	if rows.size() < all_tasks.size():
		print("mesure incomplète : %d parties sur %d" % [rows.size(), all_tasks.size()])
		quit(1)
		return
	var text := _markdown(tuning, all_tasks, rows, seeds)
	print(text)
	if not argv.has("--no-md"):
		var f := FileAccess.open("res://" + MD, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("écrit : %s" % MD)
	quit(0)

static func _load(dir: String) -> Dictionary:
	var rows := {}
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".json"):
			rows.merge(JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(name))))
	return rows

## Une PARTIE par tâche (les graines sont réparties entre les processus) : {classId, section, mode, seed}.
static func tasks(tuning: Dictionary, seeds: int) -> Array:
	var out: Array = []
	for class_id in tuning.classes:
		for section in SECTIONS:
			for mode in MODES:
				for seed_n in range(1, seeds + 1):
					out.append({"classId": class_id, "section": section, "mode": mode, "seed": float(seed_n)})
	return out

## Les trois emplacements joués : compétence de départ, compétence à charges de départ, seconde compétence.
static func slots_of(tuning: Dictionary, class_id: String) -> Array:
	var c: Dictionary = tuning.classes[class_id]
	return [c.skills[0], c.gadgets[0], c.skills[1]]

# ---------------------------------------------------------------- le héros d'une mesure

## Le profil du héros qui ARRIVE au premier étage de la section (voir l'en-tête).
static func profile_for(tuning: Dictionary, class_id: String, section: float, full: bool) -> Dictionary:
	var slots := slots_of(tuning, class_id)
	var m: Dictionary = Classes.kit_profile(tuning, class_id, null, slots)
	if section > 1.0:
		_equip(tuning, m, class_id, D6Floors.section_bounds(tuning, section).first - 1.0)
	if full:
		full_tree(tuning, m, class_id, slots)
	return m

## Ville entière achetée, et trois objets RARETE du niveau `floor` (fabriqués par les règles).
static func _equip(tuning: Dictionary, m: Dictionary, class_id: String, floor: float) -> void:
	for id in tuning.town.upgrades:
		m.souls = 1e9
		while D6Js.truthy(D6Profile.buy_upgrade(m, tuning, id).get("ok")):
			m.souls = 1e9
	m.souls = 0.0
	var jetable: Dictionary = D6Game.create_game({"seed": GRAINE_OBJETS, "startFloor": 1.0, "meta": m, "sandbox": true})
	for slot in m.equipment:
		var voeu := {"slot": slot, "rarity": RARETE, "floor": floor}
		if slot == "arme":
			voeu.weaponType = tuning.classes[class_id].weapons[0]
		var objet: Dictionary = D6Loot.generate_item(jetable, voeu)
		D6Profile.ensure_uid(m, objet)
		m.equipment[slot] = objet

## Arbre PLEIN raisonnable : la politique de l'en-tête. Rend les points dépensés.
static func full_tree(tuning: Dictionary, m: Dictionary, class_id: String, slots: Array) -> float:
	var st: Dictionary = Arbre.state(m, class_id)
	st.level = tuning.tree.maxLevel
	st.guardians = tuning.boss.keys()
	var nodes: Array = Arbre.nodes(tuning, class_id)
	var order: Array = slots.map(func(id): return Arbre.skill_node(tuning, class_id, id).id)
	for kinds in [["passive"], ["move", "ultimate"], ["skill"]]:
		for n in nodes:
			if kinds.has(n.kind) and not order.has(n.id):
				order.append(n.id)
	var bought := true
	while bought:
		bought = false
		for id in order:
			if D6Js.truthy(Arbre.buy(m, tuning, class_id, id).ok):
				bought = true
				break
	for id in slots:
		var n: Dictionary = Arbre.skill_node(tuning, class_id, id)
		Arbre.choose(m, tuning, class_id, n.id, n.choices[0].id)
	return Arbre.spent(m, class_id)

# ---------------------------------------------------------------- une partie mesurée

static func _new_counts() -> Dictionary:
	return {"base": 0.0, "competences": 0.0, "ultime": 0.0, "autres": 0.0, "formTicks": 0.0, "fightTicks": 0.0, "formDamage": 0.0, "formHurt": 0.0, "hurt": 0.0, "healed": 0.0}

## Ce que les événements d'un pas disent, avant qu'ils soient vidés : dégâts par source, coups reçus.
static func _count(game: Dictionary, c: Dictionary) -> void:
	var in_form: bool = D6KitSupers.form_of(game) != null
	if not D6Js.truthy(game.room.get("cleared")):
		c.fightTicks += 1.0
		if in_form:
			c.formTicks += 1.0
	for ev in game.events:
		if ev.type == "hit":
			var part: String = PARTS.get(ev.get("kind"), "autres")
			if in_form and part == "base":
				part = "ultime"
			c[part] += ev.amount
			if in_form:
				c.formDamage += ev.amount
		elif ev.type == "playerHurt":
			c.hurt += ev.amount
			if in_form:
				c.formHurt += ev.amount
		elif ev.type == "heal":
			c.healed += ev.amount

## Joue une partie : la section `task.section`, de son premier étage à son Gardien. Rend ses mesures.
static func run_one(tuning: Dictionary, task: Dictionary) -> Dictionary:
	var bounds: Dictionary = D6Floors.section_bounds(tuning, task.section)
	var meta := profile_for(tuning, task.classId, task.section, task.mode == "plein")
	var policy: String = NO_MOVE_POLICY if task.mode == "sansGeste" else POLICY
	var game: Dictionary = D6Game.create_game({"seed": task.seed, "startFloor": bounds.first, "meta": meta})
	var max_hp: float = game.player.maxHp
	var rec: Dictionary = Episode._new_recorder()
	var counts := _new_counts()
	Episode._consume_events(game, rec)
	var max_ticks: float = D6Js.jround(MAX_MINUTES * SECONDS_PER_MINUTE / Episode.DT)
	var mem := {"wantTown": false, "dashAttack": false}
	var outcome := ""
	while outcome == "":
		outcome = Episode._outcome_now(game, policy, bounds.guardian + 1.0, max_ticks)
		if outcome != "":
			break
		rec.stall = Episode._detect_stall(game, rec)
		if rec.stall != null:
			outcome = "softlock"
			break
		D6Game.step_game(game, Bots.play(policy, game, mem))
		_count(game, counts)
		Episode._consume_events(game, rec)
	Episode._close_room(rec, game)
	var r: Dictionary = Episode.summarize(game, rec, {"policy": policy, "seed": task.seed, "outcome": outcome, "floors": bounds.guardian, "dashAudit": false, "lab": {}})
	return _digest(r, counts, max_hp, Arbre.spent(meta, task.classId), bounds)

## Les mesures gardées d'une partie (nombres seulement : elles voyagent en JSON entre processus).
static func _digest(r: Dictionary, c: Dictionary, max_hp: float, spent: float, bounds: Dictionary) -> Dictionary:
	var dealt: float = maxf(1.0, c.base + c.competences + c.ultime + c.autres)
	var fight_s: float = maxf(Episode.DT, c.fightTicks * Episode.DT)
	var form_s: float = c.formTicks * Episode.DT
	var out_s: float = maxf(Episode.DT, fight_s - form_s)
	return {
		"cleared": 1.0 if r.sectionCleared else 0.0, "outcome": r.outcome, "spent": spent, "maxHp": max_hp,
		"dead": 1.0 if r.outcome == "dead" else 0.0, "stuck": 1.0 if ["stuck", "softlock", "timeout"].has(r.outcome) else 0.0,
		"cause": ", ".join(r.deathCauses.keys()) if r.deathCauses is Dictionary else str(r.deathCauses), "lastFloor": r.floorReached, "stall": JSON.stringify(r.stall) if r.stall != null else "",
		"rooms": r.combatRooms, "floorsDone": r.floorReached - bounds.first,
		"hurtPerRoomPct": PCT * r.damagePerRoom / max_hp if r.damagePerRoom != null else -1.0,
		"roomSeconds": _mean(r.roomTimes) if not r.roomTimes.is_empty() else -1.0,
		"bossSeconds": r.bossFightSeconds if r.bossFightSeconds != null else -1.0,
		"shareBase": PCT * c.base / dealt, "shareSkills": PCT * c.competences / dealt, "shareUlt": PCT * c.ultime / dealt, "shareOther": PCT * c.autres / dealt,
		"supers": r.superUses, "casts": r.skillCasts + r.gadgetUses,
		"formUptimePct": PCT * form_s / fight_s,
		"formDps": c.formDamage / form_s if form_s > 0.0 else -1.0, "outDps": (dealt - c.formDamage) / out_s,
		"formHurtPctPerMin": PCT * c.formHurt / max_hp / form_s * SECONDS_PER_MINUTE if form_s > 0.0 else -1.0,
		"outHurtPctPerMin": PCT * (c.hurt - c.formHurt) / max_hp / out_s * SECONDS_PER_MINUTE,
		"healedPct": PCT * c.healed / max_hp,
	}

static func _mean(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / xs.size() if not xs.is_empty() else 0.0

# ---------------------------------------------------------------- agrégat et rapport

## Moyenne et écart-type ENTRE GRAINES d'une mesure (les parties où elle n'existe pas, −1, sont écartées).
static func _stat(games: Array, key: String) -> Dictionary:
	var xs: Array = []
	for g in games:
		if float(g[key]) >= 0.0:
			xs.append(float(g[key]))
	if xs.is_empty():
		return {"n": 0, "mean": 0.0, "sd": 0.0}
	var m := _mean(xs)
	var v := 0.0
	for x in xs:
		v += (x - m) * (x - m)
	return {"n": xs.size(), "mean": m, "sd": sqrt(v / maxf(1.0, xs.size() - 1.0))}

static func _pm(games: Array, key: String, unit: String = "", digits: int = 1) -> String:
	var s := _stat(games, key)
	if s.n == 0:
		return "—"
	return ("%." + str(digits) + "f ± %." + str(digits) + "f%s") % [s.mean, s.sd, unit]

## Les parties d'une case du rapport.
static func _cell(all_tasks: Array, rows: Dictionary, class_id: String, section: float, mode: String) -> Array:
	var out: Array = []
	for i in all_tasks.size():
		var t: Dictionary = all_tasks[i]
		if t.classId == class_id and t.section == section and t.mode == mode:
			out.append(rows[str(i)])
	return out

static func _markdown(tuning: Dictionary, all_tasks: Array, rows: Dictionary, seeds: int) -> String:
	var out: Array = [
		"# Dungeon 666 — mesure en profondeur du combat V3 (bots)",
		"",
		"Généré par `outils/profondeur.gd %d` : %d graines par case, bot habile, une section entière (18 étages, Gardien compris)" % [seeds, seeds],
		"depuis son premier étage. Sections %s : étages %s. Héros : voir l'en-tête de `outils/profondeur.gd`" % [", ".join(SECTIONS.map(func(s): return str(int(s)))), ", ".join(SECTIONS.map(func(s): return str(int(D6Floors.section_bounds(tuning, s).first))))],
		"(section 1 : héros neuf ; plus bas : Ville achetée, trois objets « %s » du niveau de l'étage précédent ; aucune bénédiction au départ)." % RARETE,
		"Chaque nombre est une MOYENNE ± l'ÉCART-TYPE entre graines (le bruit d'une partie à l'autre) ; l'incertitude sur la",
		"moyenne est cet écart divisé par √%d ≈ %.1f. Ce sont des conséquences mesurées par un bot : **l'équilibrage se juge en main**." % [seeds, sqrt(float(seeds))],
		"",
	]
	out.append_array(_md_main(tuning, all_tasks, rows))
	out.append_array(_md_shares(tuning, all_tasks, rows))
	out.append_array(_md_form(tuning, all_tasks, rows))
	out.append_array(_md_move(tuning, all_tasks, rows))
	out.append_array(_md_scale(tuning))
	return "\n".join(out)

## Tableau 1 : section battue, dégâts reçus, temps, Gardien — arbre vide contre arbre plein.
static func _md_main(tuning: Dictionary, all_tasks: Array, rows: Dictionary) -> Array:
	var out: Array = [
		"## 1. Arbre vide contre arbre plein, à trois profondeurs", "",
		"« Dégâts reçus » : en % des PV max du héros, par salle de combat. « Étages faits » : sur 18. « Morts » : parties finies par la mort",
		"du héros (une partie s'arrête à la première mort) ; « bloquées » : ni mort ni section battue (salle sans issue, temps écoulé).", "",
		"| Classe | Départ | Arbre | Points | PV max | Section battue | Morts | Bloquées | Étages faits | Dégâts reçus / salle | Temps par salle | Combat du Gardien |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|",
	]
	for class_id in tuning.classes:
		for section in SECTIONS:
			for mode in ["vide", "plein"]:
				var g := _cell(all_tasks, rows, class_id, section, mode)
				out.append("| %s | étage %d | %s | %d | %d | %d %% (%d / %d) | %d | %d | %s | %s | %s | %s |" % [
					tuning.classes[class_id].name, int(D6Floors.section_bounds(tuning, section).first), mode, int(_stat(g, "spent").mean), int(_stat(g, "maxHp").mean),
					int(round(_stat(g, "cleared").mean * PCT)), int(round(_stat(g, "cleared").mean * g.size())), g.size(),
					int(round(_stat(g, "dead").mean * g.size())), int(round(_stat(g, "stuck").mean * g.size())),
					_pm(g, "floorsDone"), _pm(g, "hurtPerRoomPct", " %"), _pm(g, "roomSeconds", " s"), _pm(g, "bossSeconds", " s"),
				])
	out.append("")
	return out

## Tableau 2 : d'où viennent les dégâts infligés, et combien d'ultimes par section.
static func _md_shares(tuning: Dictionary, all_tasks: Array, rows: Dictionary) -> Array:
	var out: Array = [
		"## 2. Part des dégâts infligés : attaque de base, compétences, ultime", "",
		"« Base » : coups d'arme et frappes de déplacement. « Compétences » : à recharge et à charges. « Ultime » : ses",
		"dégâts propres, les morsures des limiers et, pendant la Forme du Damné, les griffes. « Autres » : brûlure,",
		"éclairs et explosions des bénédictions, chocs de mur. Les coups comptent à leur montant affiché (le dernier coup d'un ennemi compris).", "",
		"| Classe | Départ | Arbre | Base | Compétences | Ultime | Autres | Ultimes lancés / section | Compétences lancées / section |",
		"|---|---|---|---|---|---|---|---|---|",
	]
	for class_id in tuning.classes:
		for section in SECTIONS:
			for mode in ["vide", "plein"]:
				var g := _cell(all_tasks, rows, class_id, section, mode)
				out.append("| %s | étage %d | %s | %s | %s | %s | %s | %s | %s |" % [
					tuning.classes[class_id].name, int(D6Floors.section_bounds(tuning, section).first), mode,
					_pm(g, "shareBase", " %"), _pm(g, "shareSkills", " %"), _pm(g, "shareUlt", " %"), _pm(g, "shareOther", " %"), _pm(g, "supers"), _pm(g, "casts", "", 0),
				])
	out.append("")
	return out

## Tableau 3 : la Forme du Damné (Revenant) — présence, dégâts, coups reçus pendant et hors de la forme.
static func _md_form(tuning: Dictionary, all_tasks: Array, rows: Dictionary) -> Array:
	var out: Array = [
		"## 3. La Forme du Damné (Revenant)", "",
		"« En forme » : part du temps de combat passée transformé. Dégâts par seconde de combat, en forme et hors forme.",
		"Coups reçus : en % des PV max par MINUTE de combat, en forme et hors forme. Soins : tout ce qui a été soigné dans la section, en % des PV max.", "",
		"| Départ | Arbre | En forme | Dégâts / s en forme | Dégâts / s hors forme | Rapport | Reçus / min en forme | Reçus / min hors forme | Soins sur la section |",
		"|---|---|---|---|---|---|---|---|---|",
	]
	for section in SECTIONS:
		for mode in ["vide", "plein"]:
			var g := _cell(all_tasks, rows, "revenant", section, mode)
			var f := _stat(g, "formDps")
			var o := _stat(g, "outDps")
			out.append("| étage %d | %s | %s | %s | %s | ×%.2f | %s | %s | %s |" % [
				int(D6Floors.section_bounds(tuning, section).first), mode, _pm(g, "formUptimePct", " %"), _pm(g, "formDps", "", 0), _pm(g, "outDps", "", 0),
				f.mean / maxf(1e-9, o.mean), _pm(g, "formHurtPctPerMin", " %"), _pm(g, "outHurtPctPerMin", " %"), _pm(g, "healedPct", " %", 0),
			])
	out.append("")
	return out

## Tableau 4 : ce que vaut le déplacement de classe (le saut du Bourreau en tête) — avec contre sans.
static func _md_move(tuning: Dictionary, all_tasks: Array, rows: Dictionary) -> Array:
	var out: Array = [
		"## 4. Le déplacement de classe compte-t-il encore en profondeur ?", "",
		"Arbre vide, le même bot avec son déplacement (dash, saut, roulade) puis sans (il esquive à pied). « Valeur » : dégâts reçus",
		"par salle sans le geste ÷ avec (l'oracle de jouabilité exige ×%.1f en section 1, sur les kits et les graines de `outils/classes.gd`)." % 2.0, "",
		"| Classe | Départ | Section battue avec | … sans | Dégâts reçus / salle avec | … sans | Valeur du geste |",
		"|---|---|---|---|---|---|---|",
	]
	for class_id in tuning.classes:
		for section in SECTIONS:
			var a := _cell(all_tasks, rows, class_id, section, "vide")
			var b := _cell(all_tasks, rows, class_id, section, "sansGeste")
			var avec: float = _stat(a, "hurtPerRoomPct").mean
			var valeur := "×%.1f" % (_stat(b, "hurtPerRoomPct").mean / avec) if avec >= PLANCHER_RAPPORT else "plus de ×%.0f" % (_stat(b, "hurtPerRoomPct").mean / PLANCHER_RAPPORT)
			out.append("| %s (%s) | étage %d | %d %% | %d %% | %s | %s | %s |" % [
				tuning.classes[class_id].name, tuning.classes[class_id].move, int(D6Floors.section_bounds(tuning, section).first),
				int(round(_stat(a, "cleared").mean * PCT)), int(round(_stat(b, "cleared").mean * PCT)),
				_pm(a, "hurtPerRoomPct", " %"), _pm(b, "hurtPerRoomPct", " %"), valeur,
			])
	out.append("")
	return out

## Tableau 5 : les échelles lues dans les règles (aucune partie jouée) — ennemis et héros, par profondeur.
static func _md_scale(tuning: Dictionary) -> Array:
	var out: Array = [
		"## 5. Les échelles, lues dans les règles", "",
		"Tout coup du héros — arme, compétence à n'importe quel rang, ultime, morsure d'un limier, brûlure — est multiplié par",
		"`dégâts de l'arme portée ÷ weaponBase` (D6Combat._scaled_amount) : un nombre de dégâts « fixe » des données suit donc l'arme.",
		"Les PV des ennemis montent plus vite que l'arme (c'est voulu : les bénédictions de la descente comblent l'écart).", "",
		"| Départ | PV des ennemis | Dégâts des ennemis | Arme du héros | PV max du héros | Un coup de 30 (Lance, rang 1) | … en % d'un diablotin | Un soin de 6 PV, en % des PV max |",
		"|---|---|---|---|---|---|---|---|",
	]
	for section in SECTIONS:
		var first: float = D6Floors.section_bounds(tuning, section).first
		var m := profile_for(tuning, "revenant", section, false)
		var g: Dictionary = D6Game.create_game({"seed": 5.0, "startFloor": first, "meta": m})
		var sc: Dictionary = D6Floors.floor_scaling(g.tuning, first)
		var imp: Dictionary = D6Enemies.create_enemy(g, "imp", 100.0, 100.0, {"spawnT": 0.0})
		var weapon: float = g.player.stats.damageMult * g.player.stats.weaponDamage / g.tuning.weaponBase
		out.append("| étage %d | ×%.1f | ×%.1f | ×%.1f | %d | %d | %.0f %% | %.1f %% |" % [
			int(first), sc.hp, sc.damage, weapon, int(g.player.maxHp), int(round(30.0 * weapon)), PCT * 30.0 * weapon / imp.maxHp, PCT * 6.0 / g.player.maxHp,
		])
	out.append("")
	return out
