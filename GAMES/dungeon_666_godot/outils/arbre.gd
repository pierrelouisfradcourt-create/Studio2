extends SceneTree
## Deux MESURES de l'ARBRE DE COMPÉTENCES, par le même bot (habile), sur la même section 1 et les
## mêmes graines. Écrit _dev/rapports/arbre.md.
##
## 1. PUISSANCE de l'arbre (étape 3) : les trois emplacements de départ — arbre VIDE (tout au rang
##    1, aucun passif) contre arbre PLEIN (tous les points d'un héros au niveau maximum qui a vaincu
##    tous les Gardiens, dépensés dans l'ordre de l'arbre ; première amélioration de chaque compétence).
## 2. VALEUR de chaque compétence NEUVE (étape 4) : le kit de DÉPART (compétence et compétence à
##    charges de départ, troisième emplacement VIDE) contre le même kit avec la compétence neuve
##    dans le troisième emplacement, au rang 1 puis au rang 5 (sans amélioration, aucun autre
##    point). Une compétence qui ne change rien ne sert pas ; une qui divise tout par deux écrase.
##
##   <godot> --headless --path . --script res://outils/arbre.gd -- [graines=10] [--no-md]
##   … -- [graines] --tranche i/n --sortie <fichier.json>     une part des mesures (un processus)
##   … -- [graines] --agreger <dossier>                       réunit les parts, écrit le rapport
##   bash outils/arbre.sh [graines]                           les trois, sur un processus par cœur
##
## Ce n'est PAS un oracle (aucun seuil, sortie 0) : ce sont des mesures pour juger. Les oracles de
## jouabilité (outils/jouabilite.sh) mesurent, eux, le niveau de départ. Les bots mesurent des
## conséquences, pas le plaisir : l'équilibrage se juge en main.

const Episode = preload("res://outils/bots/episode.gd")
const Classes = preload("res://outils/classes.gd")
const Arbre = preload("res://sim/tree.gd")
const Neuves = preload("res://sim/kit_neuves.gd")

const DEFAULT_SEEDS := 10
const MD := "_dev/rapports/arbre.md"
const POLICY := "skilled"
const MAX_MINUTES := 30.0
const SECONDS_PER_MINUTE := 60.0

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
	var all_tasks := tasks(tuning)
	var rows := {}
	if merge_dir != "":
		rows = _load(merge_dir)
	else:
		for i in all_tasks.size():
			if i % slices == slice:
				rows[str(i)] = _measure(tuning, all_tasks[i], seeds)
				print("  %s : mesuré" % all_tasks[i].label)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows))
		f.close()
		quit(0)
		return
	if rows.size() < all_tasks.size():
		print("mesure incomplète : %d parts sur %d" % [rows.size(), all_tasks.size()])
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

## Les trois emplacements joués par la mesure de puissance : compétence de départ, compétence à
## charges de départ, seconde compétence.
static func slots_of(tuning: Dictionary, class_id: String) -> Array:
	var c: Dictionary = tuning.classes[class_id]
	return [c.skills[0], c.gadgets[0], c.skills[1]]

## Les compétences NEUVES d'une classe (étapes 4 et 5), dans l'ordre de l'arbre.
static func new_skills(tuning: Dictionary, class_id: String) -> Array:
	var out: Array = []
	for n in Arbre.nodes(tuning, class_id):
		if n.kind == "skill" and (Neuves.SKILLS + Neuves.GADGETS + Neuves.SKILLS_2).has(tuning[Arbre.table_of(tuning, n.skill)][n.skill].kind):
			out.append(n.skill)
	return out

## Tout ce qui se mesure, dans l'ordre du rapport : {classId, group ("arbre" | "valeur"), label,
## slots, full, skill, rank}.
static func tasks(tuning: Dictionary) -> Array:
	var out: Array = []
	for class_id in tuning.classes:
		var c: Dictionary = tuning.classes[class_id]
		for full in [false, true]:
			out.append({"classId": class_id, "group": "arbre", "label": "%s, arbre %s" % [class_id, "plein" if full else "vide"], "slots": slots_of(tuning, class_id), "full": full})
		out.append({"classId": class_id, "group": "valeur", "label": "%s, kit de départ" % class_id, "slots": [c.skills[0], c.gadgets[0], null], "skill": null, "rank": 0.0})
		for id in new_skills(tuning, class_id):
			for rank in [1.0, tuning.tree.skillRanks]:
				out.append({"classId": class_id, "group": "valeur", "label": "%s, %s rang %d" % [class_id, id, int(rank)], "slots": [c.skills[0], c.gadgets[0], id], "skill": id, "rank": rank})
	return out

## Profil à l'arbre PLEIN : niveau maximum, tous les Gardiens vaincus, chaque point dépensé dans
## l'ordre de l'arbre (un rang par nœud et par passe), première amélioration de chaque compétence.
static func full_profile(tuning: Dictionary, class_id: String) -> Dictionary:
	var m: Dictionary = Classes.kit_profile(tuning, class_id, null, slots_of(tuning, class_id))
	var st: Dictionary = Arbre.state(m, class_id)
	st.level = tuning.tree.maxLevel
	st.guardians = tuning.boss.keys()
	var bought := true
	while bought:
		bought = false
		for n in Arbre.nodes(tuning, class_id):
			if D6Js.truthy(Arbre.buy(m, tuning, class_id, n.id).ok):
				bought = true
	for n in Arbre.nodes(tuning, class_id):
		if n.get("choices") is Array:
			Arbre.choose(m, tuning, class_id, n.id, n.choices[0].id)
	return m

## Le profil d'une mesure : arbre plein, ou le kit demandé avec la compétence mesurée à son rang.
static func profile_of(tuning: Dictionary, task: Dictionary) -> Dictionary:
	if D6Js.truthy(task.get("full")):
		return full_profile(tuning, task.classId)
	var m: Dictionary = Classes.kit_profile(tuning, task.classId, null, task.slots)
	if task.get("skill") != null and task.rank > 1.0:
		var st: Dictionary = Arbre.state(m, task.classId)
		st.level = tuning.tree.maxLevel
		var n: Dictionary = Arbre.skill_node(tuning, task.classId, task.skill)
		st.ranks[n.id] = task.rank - (1.0 if Arbre.is_free(m, tuning, n) else 0.0)
	return m

static func _mean(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / xs.size() if not xs.is_empty() else 0.0

## Une mesure, `seeds` graines : les moyennes.
static func _measure(tuning: Dictionary, task: Dictionary, seeds: int) -> Dictionary:
	var meta := profile_of(tuning, task)
	var cleared := 0.0
	var damage: Array = []
	var room_seconds: Array = []
	var boss: Array = []
	var minutes: Array = []
	var uses: Array = []
	for seed_n in range(1, seeds + 1):
		var r: Dictionary = Episode.run_episode(POLICY, float(seed_n), {"meta": D6Js.clone(meta), "minutes": MAX_MINUTES})
		cleared += 1.0 if r.sectionCleared else 0.0
		if r.damagePerRoom != null:
			damage.append(r.damagePerRoom)
		room_seconds.append_array(r.roomTimes)
		if r.bossFightSeconds != null:
			boss.append(r.bossFightSeconds)
		minutes.append(r.simSeconds / SECONDS_PER_MINUTE)
		uses.append(r.skillCasts + r.gadgetUses)
	return {
		"spent": Arbre.spent(meta, task.classId), "cleared": cleared / seeds, "damagePerRoom": _mean(damage), "roomSeconds": _mean(room_seconds),
		"bossSeconds": _mean(boss), "minutes": _mean(minutes), "uses": _mean(uses),
	}

static func _ratio(a: float, b: float) -> String:
	return "—" if b == 0.0 else "×%.2f" % (a / b)

static func _markdown(tuning: Dictionary, all_tasks: Array, rows: Dictionary, seeds: int) -> String:
	var out: Array = [
		"# Dungeon 666 — puissance de l'arbre de compétences (bots)",
		"",
		"Généré par `outils/arbre.gd %d` : %d graines par mesure, bot habile, section 1 (18 étages), arme de départ." % [seeds, seeds],
		"Ce sont des conséquences mesurées par un bot, pas un jugement d'équilibrage : **cela se juge en main**.",
		"",
		"## 1. Arbre vide contre arbre plein",
		"",
		"Trois emplacements (compétence de départ, compétence à charges de départ, seconde compétence).",
		"**Arbre vide** : tout au rang 1, aucun passif. **Arbre plein** : tous les points d'un héros au niveau",
		"maximum qui a vaincu tous les Gardiens, première amélioration exclusive de chaque compétence.",
		"",
		"| Classe | Arbre | Points dépensés | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Durée |",
		"|---|---|---|---|---|---|---|---|",
	]
	var ratios: Array = []
	for i in all_tasks.size():
		var t: Dictionary = all_tasks[i]
		var r: Dictionary = rows[str(i)]
		if t.group != "arbre":
			continue
		out.append("| %s | %s | %d | %d %% | %.1f | %.1f s | %.1f s | %.1f min |" % [tuning.classes[t.classId].name, "plein" if t.full else "vide", int(r.spent), int(round(r.cleared * 100.0)), r.damagePerRoom, r.roomSeconds, r.bossSeconds, r.minutes])
		if t.full:
			var a: Dictionary = rows[str(i - 1)]
			ratios.append("| %s | %s | %s | %s |" % [tuning.classes[t.classId].name, _ratio(r.damagePerRoom, a.damagePerRoom), _ratio(r.roomSeconds, a.roomSeconds), _ratio(r.bossSeconds, a.bossSeconds)])
	out.append_array(["", "Arbre plein rapporté à l'arbre vide :", "", "| Classe | Dégâts reçus / salle | Temps par salle | Combat du Gardien |", "|---|---|---|---|"])
	out.append_array(ratios)
	out.append_array(["", "Lecture : ×0,50 en temps par salle = les salles tombent deux fois plus vite avec l'arbre plein.", ""])
	out.append_array(_md_value(tuning, all_tasks, rows))
	return "\n".join(out)

## Section 2 du rapport : la valeur de chaque compétence neuve, rapportée au kit de départ.
static func _md_value(tuning: Dictionary, all_tasks: Array, rows: Dictionary) -> Array:
	var out: Array = [
		"## 2. Valeur de chaque compétence neuve",
		"",
		"Kit de départ (deux emplacements, le troisième vide) contre le même kit avec la compétence neuve dans le",
		"troisième emplacement, au rang 1 puis au rang 5, sans amélioration ni autre point. « Lancers » : compétences",
		"lancées et charges dépensées par section, tous emplacements confondus (le kit de départ sert de repère).",
		"Entre parenthèses : rapporté au kit de départ (×1,00 = ne change rien ; ×0,50 = moitié moins).",
		"",
		"| Classe | Compétence | Rang | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Lancers |",
		"|---|---|---|---|---|---|---|---|",
	]
	var base := {}
	for i in all_tasks.size():
		var t: Dictionary = all_tasks[i]
		var r: Dictionary = rows[str(i)]
		if t.group != "valeur":
			continue
		if t.skill == null:
			base = r
			out.append("| %s | (kit de départ) | — | %d %% | %.1f | %.1f s | %.1f s | %.0f |" % [tuning.classes[t.classId].name, int(round(r.cleared * 100.0)), r.damagePerRoom, r.roomSeconds, r.bossSeconds, r.uses])
			continue
		var def: Dictionary = tuning[Arbre.table_of(tuning, t.skill)][t.skill]
		out.append("| %s | %s | %d | %d %% | %.1f (%s) | %.1f s (%s) | %.1f s (%s) | %.0f |" % [
			tuning.classes[t.classId].name, def.name, int(t.rank), int(round(r.cleared * 100.0)),
			r.damagePerRoom, _ratio(r.damagePerRoom, base.damagePerRoom), r.roomSeconds, _ratio(r.roomSeconds, base.roomSeconds),
			r.bossSeconds, _ratio(r.bossSeconds, base.bossSeconds), r.uses,
		])
	out.append("")
	return out
