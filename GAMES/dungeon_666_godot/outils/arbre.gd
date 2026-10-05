extends SceneTree
## Mesure de la PUISSANCE apportée par l'ARBRE DE COMPÉTENCES (combat V3, étape 3) : le même bot
## (habile), la même section 1, les mêmes graines, les mêmes trois emplacements — arbre VIDE (tout au
## rang 1, aucun passif) contre arbre PLEIN (tous les points d'un héros au niveau maximum qui a
## vaincu tous les Gardiens, dépensés dans l'ordre de l'arbre ; première amélioration exclusive de
## chaque compétence). Écrit _dev/rapports/arbre.md.
##
##   <godot> --headless --path . --script res://outils/arbre.gd -- [graines=10] [--no-md]
##
## Ce n'est PAS un oracle (aucun seuil, sortie 0) : c'est une mesure pour juger si l'arbre plein
## écrase le jeu. Les oracles de jouabilité (outils/jouabilite.sh) mesurent, eux, le niveau de départ.
## Les bots mesurent des conséquences, pas le plaisir : l'équilibrage se juge en main.

const Episode = preload("res://outils/bots/episode.gd")
const Classes = preload("res://outils/classes.gd")
const Arbre = preload("res://sim/tree.gd")

const DEFAULT_SEEDS := 10
const MD := "_dev/rapports/arbre.md"
const POLICY := "skilled"
const MAX_MINUTES := 30.0
const SECONDS_PER_MINUTE := 60.0

func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var seeds := DEFAULT_SEEDS
	for a in argv:
		if a.is_valid_int():
			seeds = int(a)
	var tuning: Dictionary = D6Data.create_tuning()
	var rows: Array = []
	for class_id in tuning.classes:
		for full in [false, true]:
			rows.append(_measure(tuning, class_id, full, seeds))
			print("  %s, arbre %s : mesuré" % [class_id, "plein" if full else "vide"])
	var text := _markdown(tuning, rows, seeds)
	print(text)
	if not argv.has("--no-md"):
		var f := FileAccess.open("res://" + MD, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("écrit : %s" % MD)
	quit(0)

## Les trois emplacements joués dans les deux cas : compétence de départ, compétence à charges de
## départ, seconde compétence.
static func slots_of(tuning: Dictionary, class_id: String) -> Array:
	var c: Dictionary = tuning.classes[class_id]
	return [c.skills[0], c.gadgets[0], c.skills[1]]

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

static func _mean(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / xs.size() if not xs.is_empty() else 0.0

## Une classe, un arbre (vide ou plein), `seeds` graines : les moyennes.
static func _measure(tuning: Dictionary, class_id: String, full: bool, seeds: int) -> Dictionary:
	var meta: Dictionary = full_profile(tuning, class_id) if full else Classes.kit_profile(tuning, class_id, null, slots_of(tuning, class_id))
	var cleared := 0.0
	var damage: Array = []
	var room_seconds: Array = []
	var boss: Array = []
	var minutes: Array = []
	for seed_n in range(1, seeds + 1):
		var r: Dictionary = Episode.run_episode(POLICY, float(seed_n), {"meta": D6Js.clone(meta), "minutes": MAX_MINUTES})
		cleared += 1.0 if r.sectionCleared else 0.0
		if r.damagePerRoom != null:
			damage.append(r.damagePerRoom)
		room_seconds.append_array(r.roomTimes)
		if r.bossFightSeconds != null:
			boss.append(r.bossFightSeconds)
		minutes.append(r.simSeconds / SECONDS_PER_MINUTE)
	return {
		"classId": class_id, "full": full, "spent": Arbre.spent(meta, class_id), "cleared": cleared / seeds,
		"damagePerRoom": _mean(damage), "roomSeconds": _mean(room_seconds), "bossSeconds": _mean(boss), "minutes": _mean(minutes),
	}

static func _ratio(a: float, b: float) -> String:
	return "—" if b == 0.0 else "×%.2f" % (a / b)

static func _markdown(tuning: Dictionary, rows: Array, seeds: int) -> String:
	var out: Array = [
		"# Dungeon 666 — puissance de l'arbre de compétences (bots)",
		"",
		"Généré par `outils/arbre.gd %d` : %d graines par classe, bot habile, section 1 (18 étages), arme de départ," % [seeds, seeds],
		"trois emplacements (compétence de départ, compétence à charges de départ, seconde compétence).",
		"**Arbre vide** : tout au rang 1, aucun passif. **Arbre plein** : tous les points d'un héros au niveau",
		"maximum qui a vaincu tous les Gardiens, première amélioration exclusive de chaque compétence.",
		"Ce sont des conséquences mesurées par un bot, pas un jugement d'équilibrage : **cela se juge en main**.",
		"",
		"| Classe | Arbre | Points dépensés | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Durée |",
		"|---|---|---|---|---|---|---|---|",
	]
	for r in rows:
		out.append("| %s | %s | %d | %d %% | %.1f | %.1f s | %.1f s | %.1f min |" % [tuning.classes[r.classId].name, "plein" if r.full else "vide", int(r.spent), int(round(r.cleared * 100.0)), r.damagePerRoom, r.roomSeconds, r.bossSeconds, r.minutes])
	out.append("")
	out.append("## Arbre plein rapporté à l'arbre vide")
	out.append("")
	out.append("| Classe | Dégâts reçus / salle | Temps par salle | Combat du Gardien |")
	out.append("|---|---|---|---|")
	for i in range(0, rows.size(), 2):
		var a: Dictionary = rows[i]
		var b: Dictionary = rows[i + 1]
		out.append("| %s | %s | %s | %s |" % [tuning.classes[a.classId].name, _ratio(b.damagePerRoom, a.damagePerRoom), _ratio(b.roomSeconds, a.roomSeconds), _ratio(b.bossSeconds, a.bossSeconds)])
	out.append("")
	out.append("Lecture : ×0,50 en temps par salle = les salles tombent deux fois plus vite avec l'arbre plein.")
	out.append("")
	return "\n".join(out)
