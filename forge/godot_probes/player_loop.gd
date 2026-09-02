extends SceneTree
# player_loop — sonde Forge HORS projet (bot-joueur GENERIQUE, lancee `--path <jeu>
# --script <chemin absolu>` en fenetre GPU, meme patron que runtime_alive.gd).
# Rejoue la sequence de `res://03_WORLD/loop.json` (projection DETERMINISTE du
# Prisme, jamais une source de verite en elle-meme — decision Pierre 2026-08-22)
# avec les SEULES entrees d'un joueur : InputEvent sur des affordances (groupe
# "affordance") + lecture de Label (groupe "hud"). PAUVRE ET GENERIQUE : cette
# sonde n'a AUCUNE connaissance d'un jeu particulier : aucun appel a l'economie
# interne, aucune API systeme, aucun script de regles (garde anti-contournement V4,
# non negociable).
#
# Predicats supportes (observe.predicate) : nonempty | increases | changes |
# contains:<txt> | new_distinct | decreases | resets | increases_more_than:<ref>.
# En plus, observe.appears:<group> exige que get_nodes_in_group(<group>).size()
# strictement augmente entre avant et apres (nouvel element du groupe "affordance"
# ou "hud" — toujours un groupe generique, jamais un nom de noeud du jeu).
# role REPEAT porte `replay: [refs]` : rejoue, dans l'ordre, les steps B..F deja
# definis plus haut dans `loop.json` (identifies par leur `ref`), sans jamais
# reconnaitre le jeu — seule la structure loop.json est lue.
#
# target_frames (Lot B T4, 2026-08-23) : un step peut porter `target_frames:
# {min, max, ref}` (projete par loop_spec.mjs depuis exigence.target, valide
# min < max) — la sonde compte les frames de CHAQUE step (du before a
# l'evaluate inclus ; pour REPEAT, chemin principal = ses rejeux, seule
# execution qu'il a ; pour DECISION, chemin principal = la continuation finale
# SEULEMENT, les trajectoires contre-factuelles exploratoires sont exclues) et
# emet `data.steps[].frames` + `data.targets[]` (une entree par step portant
# target_frames). Si target_frames present, le step PASS ssi le predicat PASS
# ET min <= frames <= max, sinon raison "target_frames : <frames> hors
# [min, max] (ref <ref>)".
#
# role DECISION (options/policies/metric/horizon_frames) : point de decision
# significative (6 preuves — INFORMATION, CHOICE, IMMEDIATE, FUTURE, NON-DOMINANCE,
# PLAYER GOAL). La sonde libere/reinstancie la scene principale (`_reset_scene`) pour
# rejouer le meme prefixe depuis le meme etat initial, une fois par option et une fois
# par (option x policy) — jamais de nouvel acces au jeu que InputEvent + groupes
# `affordance`/`hud` (meme garde anti-contournement que le reste de la sonde).
#
# KC_LOOP_JSON_OVERRIDE (variable d'environnement) : UNIQUEMENT pour les tests —
# permet de pointer un loop.json temporaire hors du jeu, sans jamais ecrire sous
# GAMES/**. En production la sonde lit strictement res://03_WORLD/loop.json.

const SETTLE_FRAMES := 60
const DEFAULT_WAIT_FRAMES := 30
const FRAMES_BETWEEN_CLICKS := 2

var _num_re := RegEx.new()
var _frames := 0
var _steps: Array = []
var _run_queue: Array = []      # taches aplaties (normal | replay_item | replay_end)
var _step_idx := 0
var _phase := "settle"          # settle -> before -> inject -> wait -> done (+ decision_running)
var _click_count := 0
var _click_target := 0
var _click_subframe := 0
var _wait_elapsed := 0
var _before_text := ""
var _cur_affordance: Node = null
var _appears_group := ""
var _appears_before := -1
var _results: Array = []
var _fails: Array[String] = []
var _reached_role := "NONE"
var _step_frame_start := -1   # frame ou le step (ou le REPEAT en cours) a commence, -1 = aucun step ouvert
var _targets: Array = []      # data.targets : une entree par step portant target_frames

var _seen: Dictionary = {}      # hud -> Array[String] : toutes les valeurs before/after vues
var _initial: Dictionary = {}   # hud -> String : premiere valeur jamais vue sur ce hud
var _deltas: Dictionary = {}    # ref (ou "<ref>@replay") -> float : delta after-before du dernier PASS
var _replay_acc: Dictionary = {}  # parent_ref (REPEAT) -> Array de {ref, pass, before, after}
var _replayed_from := ""        # FUITE 1 (Lot D) : ref du step dont l'affordance/repeat
                                 # ont ete rejoues pour le step COURANT (cf. _do_before),
                                 # remis a "" a chaque nouveau step (_advance_task).

# --- etat DECISION (trajectoires contre-factuelles) ---------------------------
var _scene_packed: PackedScene = null   # scene principale, memorisee pour _reset_scene()
var _root_inst: Node = null             # instance courante de la scene principale
var _boot_vector_initial: Dictionary = {}  # hud_vector() capture au tout premier boot
var _dec_boot_frames := SETTLE_FRAMES      # frames d'attente apres chaque reinstanciation
var _decision_result: Dictionary = {}      # data.decision emis (vide si aucun step DECISION)


func _init() -> void:
	_num_re.compile("[-+]?\\d+(?:[.,]\\d+)?")

	var scene_path: String = ProjectSettings.get_setting("run/main_scene", "res://main.tscn")
	var packed = load(scene_path)
	if packed == null or not (packed is PackedScene):
		_fails.append("scene principale introuvable : %s" % scene_path)
		_emit(); return
	_scene_packed = packed
	var inst: Node = packed.instantiate()
	get_root().add_child(inst)
	_root_inst = inst

	var text := _read_loop_json()
	if text == "":
		_fails.append("loop.json absent du jeu")
		_emit(); return

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary) or not (parsed.get("steps") is Array) or (parsed["steps"] as Array).is_empty():
		_fails.append("loop.json illisible/mal forme")
		_emit(); return
	_steps = parsed["steps"]
	_build_run_queue()


func _read_loop_json() -> String:
	# Test seulement : une variable d'environnement pointe un loop.json temporaire
	# hors de GAMES/** (jamais lue en production — la sonde reste generique).
	var override := OS.get_environment("KC_LOOP_JSON_OVERRIDE")
	var path := override if override != "" else "res://03_WORLD/loop.json"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


# Aplatit `_steps` en une file d'execution lineaire : un step REPEAT devient N
# taches "replay_item" (une par ref rejouee, config recopiee du step d'origine
# identifie par son `ref`) suivies d'une tache "replay_end" qui agrege le resultat.
# Les refs REPEAT doivent pointer un step deja rencontre plus haut dans `_steps`
# (role B..F) — resolu ici par un dictionnaire construit en un seul passage avant.
func _build_run_queue() -> void:
	var by_ref := {}
	for step in _steps:
		if typeof(step) != TYPE_DICTIONARY:
			_run_queue.append({"task_kind": "normal", "orig_step": step})
			continue
		var role := String(step.get("role", ""))
		if role == "REPEAT":
			var parent_ref := String(step.get("ref", ""))
			var replay_refs: Array = step.get("replay", []) if step.get("replay") is Array else []
			for r in replay_refs:
				var rr := String(r)
				_run_queue.append({
					"task_kind": "replay_item", "parent_ref": parent_ref,
					"orig_ref": rr, "orig_step": by_ref.get(rr),
				})
			_run_queue.append({"task_kind": "replay_end", "parent_ref": parent_ref, "orig_step": step})
		else:
			_run_queue.append({"task_kind": "normal", "orig_step": step})
			var ref := String(step.get("ref", ""))
			if ref != "":
				by_ref[ref] = step


func _process(_delta: float) -> bool:
	_frames += 1

	if _phase == "settle":
		if _frames >= SETTLE_FRAMES:
			_boot_vector_initial = _hud_vector()
			_phase = "before"
		return false

	if _phase == "decision_running":
		# _run_decision() est une coroutine (async) qui pilote elle-meme ses propres
		# frames via `await` ; ce _process ne fait rien tant qu'elle n'a pas rendu la
		# main (avance vers "before" ou stoppe le run vers "done").
		return false

	if _phase == "done":
		return false

	if _step_idx >= _run_queue.size():
		_phase = "done"
		_emit()
		return false

	var task: Dictionary = _run_queue[_step_idx]
	var kind := String(task.get("task_kind", ""))

	if kind == "replay_end":
		_do_replay_end(task)
		return false

	var step = task.get("orig_step")
	if typeof(step) != TYPE_DICTIONARY:
		var reason := ("replay ref '%s' introuvable" % String(task.get("orig_ref", "")) if kind == "replay_item"
			else "step #%d n'est pas un objet" % _step_idx)
		_fail_current_task(task, reason)
		return false

	if _phase == "before":
		if String(step.get("role", "")) == "DECISION":
			_phase = "decision_running"
			_run_decision(step)
			return false
		_do_before(step, task)
		return false
	if _phase == "inject":
		_do_inject(step)
		return false
	if _phase == "wait":
		_do_wait(step, task)
		return false
	return false


# Resout un `ref` dans la liste ORIGINALE `_steps` (jamais `_run_queue`), null si
# aucun step ne le porte. Utilise par le rejeu `replay_ref` (FUITE 1, Lot D).
func _find_step_by_ref(ref: String) -> Variant:
	for st in _steps:
		if typeof(st) == TYPE_DICTIONARY and String(st.get("ref", "")) == ref:
			return st
	return null


func _do_before(step: Dictionary, task: Dictionary) -> void:
	if _step_frame_start < 0:
		_step_frame_start = _frames
	_replayed_from = ""
	var observe = step.get("observe", {})
	var hud_name := String(observe.get("hud", "")) if typeof(observe) == TYPE_DICTIONARY else ""
	var label := _find_hud(hud_name)
	if label == null:
		_fail_current_task(task, "hud '%s' introuvable" % hud_name)
		return
	_before_text = label.text

	_appears_group = String(observe.get("appears", "")) if typeof(observe) == TYPE_DICTIONARY else ""
	_appears_before = get_nodes_in_group(_appears_group).size() if _appears_group != "" else -1

	var affordance_name := String(step.get("affordance", ""))
	var repeat_source: Dictionary = step

	# FUITE 1 (Lot D, 2026-08-23, GO Pierre) : un step SANS affordance mais avec
	# `replay_ref` (typiquement ADVANTAGE, ex. run 9 `j_advantage`) doit rejouer
	# l'affordance ET le `repeat` du step REFERENCE (resolu par `ref` dans
	# `_steps`), puis evaluer SON PROPRE `observe` — jamais mesurer la seule
	# production passive du wait_frames (mesure : run 9 j_advantage sans
	# affordance -> delta passif 96.0 ; run 8b avec affordance -> vrai clic).
	if affordance_name == "":
		var replay_ref := String(step.get("replay_ref", ""))
		if replay_ref != "":
			var ref_step = _find_step_by_ref(replay_ref)
			if ref_step == null:
				_fail_current_task(task, "replay_ref '%s' introuvable" % replay_ref)
				return
			var ref_affordance := String(ref_step.get("affordance", ""))
			if ref_affordance == "":
				_fail_current_task(task, "replay_ref '%s' resolu mais sans affordance (production non rejouable)" % replay_ref)
				return
			affordance_name = ref_affordance
			repeat_source = ref_step
			_replayed_from = replay_ref

	if affordance_name != "":
		var node := _find_affordance(affordance_name)
		if node == null:
			_fail_current_task(task, "affordance '%s' introuvable" % affordance_name)
			return
		if not (node is Control):
			_fail_current_task(task, "affordance '%s' n'est pas un Control" % affordance_name)
			return
		_cur_affordance = node
		_click_target = maxi(1, int(repeat_source.get("repeat", 1)))
		_click_count = 0
		_click_subframe = 0
		_phase = "inject"
	else:
		_cur_affordance = null
		_wait_elapsed = 0
		_phase = "wait"


func _do_inject(step: Dictionary) -> void:
	if _click_subframe == 0:
		_click(_cur_affordance)
		_click_count += 1
	_click_subframe += 1
	if _click_subframe >= FRAMES_BETWEEN_CLICKS:
		_click_subframe = 0
		if _click_count >= _click_target:
			_wait_elapsed = 0
			_phase = "wait"


func _do_wait(step: Dictionary, task: Dictionary) -> void:
	_wait_elapsed += 1
	var target := int(step.get("wait_frames", DEFAULT_WAIT_FRAMES))
	if target <= 0:
		target = DEFAULT_WAIT_FRAMES
	if _wait_elapsed >= target:
		_evaluate(step, task)


func _click(node: Control) -> void:
	var center: Vector2 = node.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	Input.parse_input_event(press)
	Input.parse_input_event(release)


func _find_hud(name: String) -> Label:
	if name == "":
		return null
	for n in get_nodes_in_group("hud"):
		if n is Label and n.name == name:
			return n
	return null


func _find_affordance(name: String) -> Node:
	if name == "":
		return null
	for n in get_nodes_in_group("affordance"):
		if n.name == name:
			return n
	return null


func _evaluate(step: Dictionary, task: Dictionary) -> void:
	var observe = step.get("observe", {})
	var hud_name := String(observe.get("hud", "")) if typeof(observe) == TYPE_DICTIONARY else ""
	var predicate := String(observe.get("predicate", "")) if typeof(observe) == TYPE_DICTIONARY else ""
	var label := _find_hud(hud_name)
	var after_text := label.text if label != null else ""
	var role := String(step.get("role", ""))
	var ref := String(step.get("ref", ""))

	if hud_name != "" and not _initial.has(hud_name):
		_initial[hud_name] = _before_text

	var predicate_pass := _eval_predicate(predicate, hud_name, _before_text, after_text)

	var appears_after := -1
	var appears_pass := true
	if _appears_group != "":
		appears_after = get_nodes_in_group(_appears_group).size()
		appears_pass = appears_after > _appears_before

	var passed: bool = predicate_pass and appears_pass

	var reason := ""
	if not passed:
		if not predicate_pass:
			reason = _predicate_fail_reason(predicate, _before_text, after_text)
		else:
			reason = "appears '%s' : %d -> %d, aucun nouvel element" % [_appears_group, _appears_before, appears_after]

	if hud_name != "":
		var seen_list: Array = _seen.get(hud_name, [])
		if not seen_list.has(_before_text):
			seen_list.append(_before_text)
		if not seen_list.has(after_text):
			seen_list.append(after_text)
		_seen[hud_name] = seen_list

	var kind := String(task.get("task_kind", ""))
	var delta_key := (String(task.get("orig_ref", "")) + "@replay") if kind == "replay_item" else ref
	if passed:
		var bnum := _extract_number(_before_text)
		var anum := _extract_number(after_text)
		if not is_nan(bnum) and not is_nan(anum):
			_deltas[delta_key] = anum - bnum

	if kind == "replay_item":
		var entry := {"ref": String(task.get("orig_ref", "")), "pass": passed,
			"before": _before_text, "after": after_text}
		if reason != "":
			entry["reason"] = reason
		var parent_ref := String(task.get("parent_ref", ""))
		var acc: Array = _replay_acc.get(parent_ref, [])
		acc.append(entry)
		_replay_acc[parent_ref] = acc
		_advance_task()
		return

	var step_frames := _frames - _step_frame_start + 1
	_step_frame_start = -1

	var target_frames = step.get("target_frames", {})
	if typeof(target_frames) == TYPE_DICTIONARY and target_frames.has("min") and target_frames.has("max"):
		var tmin := int(target_frames.get("min", 0))
		var tmax := int(target_frames.get("max", 0))
		var tref := String(target_frames.get("ref", ""))
		var target_pass: bool = step_frames >= tmin and step_frames <= tmax
		_targets.append({"ref": ref, "metric_ref": tref, "frames": step_frames,
			"min": tmin, "max": tmax, "pass": target_pass})
		if not target_pass and passed:
			passed = false
			reason = "target_frames : %d hors [%d, %d] (ref %s)" % [step_frames, tmin, tmax, tref]

	var result := {
		"role": role, "ref": ref, "affordance": String(step.get("affordance", "")),
		"before": _before_text, "after": after_text, "pass": passed, "reason": reason,
		"frames": step_frames,
	}
	if _appears_group != "":
		result["appears_before"] = _appears_before
		result["appears_after"] = appears_after
	if _replayed_from != "":
		result["replayed_from"] = _replayed_from
	_results.append(result)

	if not passed:
		_fails.append("step %s (%s) : %s" % [ref, role, reason])
		_phase = "done"
		_emit()
		return

	_reached_role = role
	_advance_task()


func _do_replay_end(task: Dictionary) -> void:
	var parent_ref := String(task.get("parent_ref", ""))
	var orig_step = task.get("orig_step", {})
	var role := String(orig_step.get("role", "REPEAT")) if typeof(orig_step) == TYPE_DICTIONARY else "REPEAT"
	var replays: Array = _replay_acc.get(parent_ref, [])
	var all_pass := not replays.is_empty()
	var failed_refs: Array[String] = []
	for r in replays:
		if not bool(r.get("pass", false)):
			all_pass = false
			failed_refs.append(String(r.get("ref", "")))

	var reason := ""
	if replays.is_empty():
		reason = "replay vide"
	elif not all_pass:
		reason = "replay(s) en echec : %s" % ", ".join(failed_refs)

	# chemin principal de REPEAT = les rejeux effectivement executes (sa seule
	# execution, contrairement a DECISION qui a un chemin principal distinct
	# de ses trajectoires exploratoires) : du before du 1er rejeu (deja
	# capture dans _step_frame_start par _do_before) a cette agregation.
	var step_frames := _frames - _step_frame_start + 1
	_step_frame_start = -1

	var target_frames = orig_step.get("target_frames", {}) if typeof(orig_step) == TYPE_DICTIONARY else {}
	if typeof(target_frames) == TYPE_DICTIONARY and target_frames.has("min") and target_frames.has("max"):
		var tmin := int(target_frames.get("min", 0))
		var tmax := int(target_frames.get("max", 0))
		var tref := String(target_frames.get("ref", ""))
		var target_pass: bool = step_frames >= tmin and step_frames <= tmax
		_targets.append({"ref": parent_ref, "metric_ref": tref, "frames": step_frames,
			"min": tmin, "max": tmax, "pass": target_pass})
		if not target_pass and all_pass:
			all_pass = false
			reason = "target_frames : %d hors [%d, %d] (ref %s)" % [step_frames, tmin, tmax, tref]

	_results.append({
		"role": role, "ref": parent_ref, "affordance": "",
		"before": "", "after": "", "pass": all_pass, "reason": reason,
		"replays": replays, "frames": step_frames,
	})

	if not all_pass:
		_fails.append("step %s (%s) : %s" % [parent_ref, role, reason])
		_phase = "done"
		_emit()
		return

	_reached_role = role
	_advance_task()


func _advance_task() -> void:
	_step_idx += 1
	if _step_idx >= _run_queue.size():
		_phase = "done"
		_emit()
	else:
		_phase = "before"


# Une seule tache en echec avant l'evaluation (hud/affordance introuvable, ref de
# replay non resolue, step malforme). Pour un "replay_item", n'interrompt PAS le
# run global : consignee dans l'accumulateur du REPEAT parent, qui echouera a son
# tour a "replay_end" (agregation), seul point qui arrete la file dans ce cas.
func _fail_current_task(task: Dictionary, reason: String) -> void:
	var kind := String(task.get("task_kind", ""))
	if kind == "replay_item":
		var entry := {"ref": String(task.get("orig_ref", "")), "pass": false,
			"before": _before_text, "after": "", "reason": reason}
		var parent_ref := String(task.get("parent_ref", ""))
		var acc: Array = _replay_acc.get(parent_ref, [])
		acc.append(entry)
		_replay_acc[parent_ref] = acc
		_advance_task()
		return

	var orig_step = task.get("orig_step")
	var role := String(orig_step.get("role", "")) if typeof(orig_step) == TYPE_DICTIONARY else ""
	var ref := String(orig_step.get("ref", "")) if typeof(orig_step) == TYPE_DICTIONARY else ""
	var affordance := String(orig_step.get("affordance", "")) if typeof(orig_step) == TYPE_DICTIONARY else ""
	_results.append({
		"role": role, "ref": ref, "affordance": affordance,
		"before": _before_text, "after": "", "pass": false, "reason": reason,
	})
	_fails.append(reason)
	_phase = "done"
	_emit()


func _predicate_fail_reason(predicate: String, before: String, after: String) -> String:
	if predicate.begins_with("increases_more_than:"):
		var ref := predicate.substr("increases_more_than:".length())
		if not _deltas.has(ref):
			return "delta de %s inconnu" % ref
	return "predicat '%s' non satisfait (avant='%s' apres='%s')" % [predicate, before, after]


func _eval_predicate(predicate: String, hud: String, before: String, after: String) -> bool:
	if predicate == "nonempty":
		return after.strip_edges() != ""
	if predicate == "increases":
		var b := _extract_number(after)
		if is_nan(b):
			return false
		var a := _extract_number(before)
		if is_nan(a):
			a = 0.0
		return b > a
	if predicate == "changes":
		return after != before
	if predicate.begins_with("contains:"):
		var txt := predicate.substr("contains:".length())
		return after.find(txt) != -1
	if predicate == "new_distinct":
		if after.strip_edges() == "":
			return false
		var seen_list: Array = _seen.get(hud, [])
		return not seen_list.has(after)
	if predicate == "decreases":
		var a := _extract_number(after)
		var b := _extract_number(before)
		if is_nan(a) or is_nan(b):
			return false
		return a < b
	if predicate == "resets":
		if not _initial.has(hud):
			return false
		var init_text := String(_initial[hud])
		if before == init_text:
			return false
		var init_num := _extract_number(init_text)
		var after_num := _extract_number(after)
		if is_nan(init_num) or is_nan(after_num):
			return false
		return after_num == init_num
	if predicate.begins_with("increases_more_than:"):
		var ref := predicate.substr("increases_more_than:".length())
		if not _deltas.has(ref):
			return false
		var a := _extract_number(after)
		var b := _extract_number(before)
		if is_nan(a) or is_nan(b):
			return false
		return (a - b) > float(_deltas[ref])
	return false


func _extract_number(s: String) -> float:
	var m := _num_re.search(s)
	if m == null:
		return NAN
	return m.get_string().replace(",", ".").to_float()


func _emit() -> void:
	var ok: bool = _fails.is_empty()
	var data := {
		"steps": _results, "reached_role": _reached_role, "frames": _frames,
		"deltas": _deltas, "seen": _seen, "targets": _targets,
	}
	if not _decision_result.is_empty():
		data["decision"] = _decision_result
	print("FORGE_ORACLE player_loop " + JSON.stringify({"ok": ok, "fails": _fails, "data": data}))
	quit(0 if ok else 1)


# =====================================================================================
# DECISION — trajectoires contre-factuelles (6 preuves). AUCUNE connaissance du jeu :
# uniquement InputEvent (via `_click`), groupe "affordance" (via `_find_affordance`) et
# groupe "hud" (via `_find_hud` / `_hud_vector`), exactement comme le reste de la sonde.
# =====================================================================================


func _hud_vector() -> Dictionary:
	var out := {}
	for n in get_nodes_in_group("hud"):
		if n is Label:
			out[String(n.name)] = n.text
	return out


func _affordance_names() -> Array:
	var names: Array = []
	for n in get_nodes_in_group("affordance"):
		names.append(String(n.name))
	names.sort()
	return names


func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k) or b[k] != a[k]:
			return false
	return true


func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


# Le PREFIXE d'un step DECISION = tous les steps qui le precedent dans `_steps` (la
# liste ORIGINALE, jamais `_run_queue`), a l'exclusion des steps REPEAT (« hors taches
# de replay » — un REPEAT n'a pas la mecanique before/inject/wait simple qu'on rejoue
# ici silencieusement).
func _decision_prefix(step: Dictionary) -> Array:
	var target_ref := String(step.get("ref", ""))
	var prefix: Array = []
	for st in _steps:
		if typeof(st) != TYPE_DICTIONARY:
			continue
		if String(st.get("ref", "")) == target_ref and String(st.get("role", "")) == "DECISION":
			break
		if String(st.get("role", "")) != "REPEAT":
			prefix.append(st)
	return prefix


# Les `options` d'un step DECISION sont des refs vers des steps B/F qui portent une
# `affordance` — resout la ref vers le nom d'affordance a cliquer.
func _option_affordance(option_ref: String) -> String:
	for st in _steps:
		if typeof(st) == TYPE_DICTIONARY and String(st.get("ref", "")) == option_ref:
			return String(st.get("affordance", ""))
	return ""


func _wait_frames(n: int) -> void:
	for _i in range(maxi(0, n)):
		await process_frame


# Libere l'enfant racine courant, attend >= 1 frame, `seed(0)`, reinstancie la
# PackedScene principale, attend `_dec_boot_frames` (memorise = frames ecoulees entre
# l'init et le premier step de la premiere trajectoire, cf. `SETTLE_FRAMES` : meme
# duree que le settle initial du run, puisque c'est la meme scene qui reboote).
func _reset_scene() -> void:
	if _root_inst != null and is_instance_valid(_root_inst):
		_root_inst.queue_free()
	_root_inst = null
	await _wait_frames(1)
	seed(0)
	var inst: Node = _scene_packed.instantiate()
	get_root().add_child(inst)
	_root_inst = inst
	await _wait_frames(_dec_boot_frames)


# Rejoue, dans l'ordre, le PREFIXE (memes clics, memes attentes que before/inject/wait)
# SANS jamais toucher `_results` / `_seen` / `_deltas` / `_initial` de la trajectoire
# principale, et sans reevaluer aucun predicat (mode « replay silencieux »).
func _replay_prefix_silent(prefix: Array) -> void:
	for st in prefix:
		var affordance_name := String(st.get("affordance", ""))
		if affordance_name != "":
			var node := _find_affordance(affordance_name)
			var repeat := maxi(1, int(st.get("repeat", 1)))
			for _i in range(repeat):
				if node != null and node is Control:
					_click(node)
				await _wait_frames(FRAMES_BETWEEN_CLICKS)
		var wf := int(st.get("wait_frames", DEFAULT_WAIT_FRAMES))
		if wf <= 0:
			wf = DEFAULT_WAIT_FRAMES
		await _wait_frames(wf)


func _click_affordance_once(affordance_name: String) -> void:
	var node := _find_affordance(affordance_name)
	if node != null and node is Control:
		_click(node)
	await _wait_frames(FRAMES_BETWEEN_CLICKS)


# Politique de jeu appliquee pendant `horizon` frames : si `policy.click` n'est pas
# null, injecte un clic sur cette affordance toutes les `policy.every_frames` frames.
func _run_policy(horizon: int, policy: Dictionary) -> void:
	var click_name := String(policy.get("click", "")) if policy.get("click") != null else ""
	var every := int(policy.get("every_frames", 0))
	for f in range(1, horizon + 1):
		if click_name != "" and every > 0 and f % every == 0:
			var node := _find_affordance(click_name)
			if node != null and node is Control:
				_click(node)
		await process_frame


# Coroutine principale du step DECISION : reset -> prefixe -> (INFORMATION, IMMEDIATE,
# etat) par option, puis reset -> prefixe -> clic -> politique -> metric par
# (option x policy), evalue les 6 preuves, emet `data.decision`, puis (si PASS) rejoue
# une derniere fois reset -> prefixe -> clic(options[0]) et rend la main a la file
# normale pour que les steps suivants (F...J) restent mesurables.
func _run_decision(step: Dictionary) -> void:
	var ref := String(step.get("ref", ""))
	var options: Array = step.get("options", []) if step.get("options") is Array else []
	var ref_a := String(options[0]) if options.size() > 0 else ""
	var ref_b := String(options[1]) if options.size() > 1 else ""
	var policies: Array = step.get("policies", []) if step.get("policies") is Array else []
	var metric := String(step.get("metric", ""))
	var horizon := int(step.get("horizon_frames", 60))
	var wait_frames := int(step.get("wait_frames", DEFAULT_WAIT_FRAMES))
	if wait_frames <= 0:
		wait_frames = DEFAULT_WAIT_FRAMES

	var prefix := _decision_prefix(step)
	var affordance_a := _option_affordance(ref_a)
	var affordance_b := _option_affordance(ref_b)

	var boot_reproducible := true
	var information := {"A": false, "B": false}
	var states := {}
	var immediate := {"A": false, "B": false}
	var matrix := {ref_a: {}, ref_b: {}}
	var objectif_before := ""
	var reasons: Array[String] = []

	var option_defs := [["A", ref_a, affordance_a], ["B", ref_b, affordance_b]]

	# --- trajectoires 1..2 : INFORMATION / etat pour CHOICE·IMMEDIATE·FUTURE·PLAYER_GOAL
	for def in option_defs:
		var key := String(def[0])
		var oref := String(def[1])
		var aff := String(def[2])

		await _reset_scene()
		var boot_vec := _hud_vector()
		if not _dicts_equal(boot_vec, _boot_vector_initial):
			boot_reproducible = false
		await _replay_prefix_silent(prefix)

		var node := _find_affordance(aff)
		var visible: bool = node != null and node.is_visible_in_tree()
		var enabled := true
		if node is BaseButton:
			enabled = not (node as BaseButton).disabled
		var cout_label := _find_hud("cout_" + aff)
		var effet_label := _find_hud("effet_" + aff)
		var info_ok: bool = (visible and enabled and cout_label != null
			and cout_label.text.strip_edges() != "" and effet_label != null
			and effet_label.text.strip_edges() != "")
		information[key] = info_ok
		if not info_ok:
			reasons.append(("DECISION %s : INFORMATION — option %s (%s/%s) incomplete " +
				"(visible=%s enabled=%s cout=%s effet=%s)") % [ref, key, oref, aff,
				visible, enabled, cout_label != null, effet_label != null])

		var hud_before := _hud_vector()
		if objectif_before == "":
			objectif_before = String(hud_before.get("objectif", ""))

		await _click_affordance_once(aff)
		await _wait_frames(wait_frames)

		var hud_after := _hud_vector()
		var affordances := _affordance_names()
		var objectif_after := String(hud_after.get("objectif", ""))
		states[oref] = {"hud": hud_after, "affordances": affordances, "objectif": objectif_after}

		var imm: bool = not _dicts_equal(hud_after, hud_before)
		immediate[key] = imm
		if not imm:
			reasons.append("DECISION %s : IMMEDIATE — %s (%s) hud inchange apres %d frames" %
				[ref, key, oref, wait_frames])

	var s_a: Dictionary = states.get(ref_a, {})
	var s_b: Dictionary = states.get(ref_b, {})

	var choice_ok: bool = not (_dicts_equal(s_a.get("hud", {}), s_b.get("hud", {}))
		and _arrays_equal(s_a.get("affordances", []), s_b.get("affordances", [])))
	if not choice_ok:
		reasons.append("DECISION %s : CHOICE — S_A == S_B" % ref)

	var aff_a: Array = s_a.get("affordances", [])
	var aff_b: Array = s_b.get("affordances", [])
	var future_ok: bool = not _arrays_equal(aff_a, aff_b)
	if not future_ok:
		var hud_a: Dictionary = s_a.get("hud", {})
		var hud_b: Dictionary = s_b.get("hud", {})
		for k in hud_a.keys():
			if String(k).begins_with("cout_") and hud_b.has(k) and hud_a[k] != hud_b[k]:
				future_ok = true
				break
	if not future_ok:
		reasons.append("DECISION %s : FUTURE — affordances identiques %s" % [ref, str(aff_a)])

	var obj_a := String(s_a.get("objectif", ""))
	var obj_b := String(s_b.get("objectif", ""))
	var player_goal_ok: bool = (obj_a != obj_b and obj_a != objectif_before and obj_b != objectif_before)
	if not player_goal_ok:
		reasons.append("DECISION %s : PLAYER_GOAL — objectifs indistincts (avant='%s' A='%s' B='%s')" %
			[ref, objectif_before, obj_a, obj_b])

	# --- trajectoires 3..N : NON-DOMINANCE (2 x |policies|) -----------------------
	for def in option_defs:
		var key2 := String(def[0])
		var oref2 := String(def[1])
		var aff2 := String(def[2])
		for p in policies:
			var pname := String(p.get("name", ""))
			await _reset_scene()
			await _replay_prefix_silent(prefix)
			await _click_affordance_once(aff2)
			await _run_policy(horizon, p)
			var metric_label := _find_hud(metric)
			var value: float = _extract_number(metric_label.text) if metric_label != null else NAN
			if is_nan(value):
				reasons.append("DECISION %s : NONDOMINANCE — metric '%s' illisible pour %s/%s" %
					[ref, metric, key2, pname])
				value = 0.0
			matrix[oref2][pname] = value

	var policy_names: Array = []
	for p in policies:
		policy_names.append(String(p.get("name", "")))
	var nondominance_ok := false
	for pn in policy_names:
		for qn in policy_names:
			var a_p: float = matrix[ref_a].get(pn, 0.0)
			var b_p: float = matrix[ref_b].get(pn, 0.0)
			var a_q: float = matrix[ref_a].get(qn, 0.0)
			var b_q: float = matrix[ref_b].get(qn, 0.0)
			if a_p > b_p and b_q > a_q:
				nondominance_ok = true
				break
		if nondominance_ok:
			break
	if not nondominance_ok:
		reasons.append("DECISION %s : NONDOMINANCE — aucune paire de politiques ne diverge (matrice %s)" %
			[ref, str(matrix)])

	if not boot_reproducible:
		reasons.append("DECISION %s : etat initial non reproductible" % ref)

	var overall: bool = (bool(information["A"]) and bool(information["B"]) and choice_ok
		and bool(immediate["A"]) and bool(immediate["B"]) and future_ok and nondominance_ok
		and player_goal_ok and boot_reproducible)

	_decision_result = {
		"ref": ref, "options": [ref_a, ref_b], "boot_reproducible": boot_reproducible,
		"information": information, "states": states, "immediate": immediate,
		"future": future_ok, "nondominance": {"matrix": matrix, "pass": nondominance_ok},
		"player_goal": player_goal_ok, "pass": overall, "reasons": reasons,
	}

	# frames (Lot B T4) : chemin principal de DECISION = la continuation finale
	# SEULEMENT (les trajectoires INFORMATION/IMMEDIATE/NONDOMINANCE ci-dessus
	# sont exploratoires, explicitement exclues) ; 0 si DECISION echoue avant
	# d'y arriver (pas de continuation jouee).
	var decision_entry := {
		"role": "DECISION", "ref": ref, "affordance": "",
		"before": "", "after": "", "pass": overall,
		"reason": (String(reasons[0]) if not overall and reasons.size() > 0 else ""),
		"frames": 0,
	}
	_results.append(decision_entry)

	if not overall:
		for r in reasons:
			_fails.append(r)
		_phase = "done"
		_emit()
		return

	_reached_role = "DECISION"

	# continuation : la sequence reprend sur la trajectoire de options[0] (convention).
	var continuation_frame_start := _frames
	await _reset_scene()
	await _replay_prefix_silent(prefix)
	await _click_affordance_once(affordance_a)
	await _wait_frames(wait_frames)
	decision_entry["frames"] = _frames - continuation_frame_start + 1

	_advance_task()
