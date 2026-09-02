# debug_receipt.test.gd — ligne proof.debug_probe. Le recu se serialise (Vector2 -> [x,y]),
# se prefixe, et se re-parse EXACTEMENT (round-trip) ; une ligne mal formee -> null.
extends RefCounted

const DebugProbe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")

func run(h) -> void:
	var obs := {"balle_pos": Vector2(1.5, 2.5), "vies": 3, "statut": 0}

	# --- serialisation : Vector2 -> [x, y] ---
	var ser: Dictionary = DebugProbe.serialisable(obs)
	h.eq(ser["balle_pos"], [1.5, 2.5], "Vector2 serialise en [x, y]")
	h.eq(ser["vies"], 3, "entier inchange")

	# --- format prefixe ---
	var ligne: String = DebugProbe.formater(obs)
	h.ok(ligne.begins_with(DebugProbe.PREFIXE), "recu prefixe par le marqueur")

	# --- round-trip parse ---
	var d = DebugProbe.parser(ligne)
	h.ok(d != null, "recu bien forme -> parse OK")
	h.eq(d["vies"], 3, "round-trip : vies")
	h.eq(d["balle_pos"], [1.5, 2.5], "round-trip : balle_pos [x, y]")

	# --- ligne mal formee -> null ---
	h.eq(DebugProbe.parser("bruit sans prefixe"), null, "ligne sans prefixe -> null")
