extends Node2D

enum State { STAY, GO_PLACE, APPROACH, RETREAT, ATTEND }

var p_self_other: float = 0.5
var p_impulse: float = 0.5
var p_adapt: float = 0.5
var p_esteem: float = 0.5
var p_empathy: float = 0.5

var char_name: String = "?"
var pattern: String = "?"
var color: Color = Color.WHITE
var sprite_tex = null   # AtlasTexture（main がセット）

var others: Array = []
var places: Array = []
var home: Vector2 = Vector2.ZERO
var bounds: Rect2 = Rect2(0, 0, 1280, 720)

var state: int = State.STAY
var target_pos: Vector2 = Vector2.ZERO
var target_char = null

var rel: Dictionary = {}
var _rel_band: Dictionary = {}
var _act_counts: Dictionary = {}

var _decide_timer: float = 0.0
var _event_active: bool = false
var _event_pos: Vector2 = Vector2.ZERO
var logs: Array[String] = []

var _t: float = 0.0
var _phase: float = 0.0

const RADIUS: float = 13.0
const SOCIAL_DIST: float = 80.0

func setup(params: Dictionary, pos: Vector2, place_list: Array) -> void:
	char_name = params.get("name", "?")
	pattern = params.get("pattern", "?")
	p_self_other = params.get("self_other", 0.5)
	p_impulse = params.get("impulse", 0.5)
	p_adapt = params.get("adapt", 0.5)
	p_esteem = params.get("esteem", 0.5)
	p_empathy = params.get("empathy", 0.5)
	color = params.get("color", Color.WHITE)
	position = pos
	home = pos
	target_pos = pos
	places = place_list
	_phase = randf() * TAU
	var lbl := Label.new()
	lbl.text = char_name
	lbl.position = Vector2(-16, -40)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	var jp = load("res://assets/NotoSansJP.ttf")
	if jp != null:
		lbl.add_theme_font_override("font", jp)
	add_child(lbl)

func set_event(active: bool, pos: Vector2) -> void:
	_event_active = active
	_event_pos = pos

func is_relating() -> bool:
	return state == State.APPROACH or state == State.RETREAT

func affinity_to(o) -> float:
	return rel.get(o, 0.0)

func incoming_affinity() -> float:
	if others.size() == 0:
		return 0.0
	var s: float = 0.0
	for o in others:
		s += float(o.rel.get(self, 0.0))
	return s / float(others.size())

func _process(delta: float) -> void:
	_t += delta
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide()
		_decide_timer = lerp(3.6, 1.1, p_impulse) + randf() * 0.4
	if state != State.STAY:
		var speed: float = lerp(16.0, 62.0, p_impulse)
		var to_t := target_pos - position
		if to_t.length() > 3.0:
			position += to_t.normalized() * speed * delta
		elif state == State.APPROACH and target_char != null:
			target_pos = target_char.position
	_update_relationships(delta)
	_clamp_bounds()
	queue_redraw()

func _update_relationships(delta: float) -> void:
	for o in others:
		var d := position.distance_to(o.position)
		var cur: float = rel.get(o, 0.0)
		if d < SOCIAL_DIST:
			var crowded: bool = (o.state == State.APPROACH and o.target_char == self and o.p_self_other >= 0.6)
			if crowded:
				cur -= 0.12 * delta * (1.2 - p_esteem)
			elif target_char == o:
				cur += 0.09 * delta
			else:
				var openness: float = clampf((1.0 - p_self_other) * 0.6 + (1.0 - p_esteem) * 0.3, 0.0, 1.0)
				cur += 0.02 * delta * openness
		else:
			cur = move_toward(cur, 0.0, 0.004 * delta)
		cur = clampf(cur, -1.0, 1.0)
		rel[o] = cur
		_check_rel_log(o, cur)

func _check_rel_log(o, v: float) -> void:
	var band := ""
	if v > 0.4:
		band = "like"
	elif v < -0.4:
		band = "dislike"
	var prev = _rel_band.get(o, "")
	if band != prev:
		_rel_band[o] = band
		if band == "like":
			_log_action("%sは%sと打ち解けてきた" % [char_name, o.char_name])
		elif band == "dislike":
			_log_action("%sは%sを避けるようになってきた" % [char_name, o.char_name])

func _decide() -> void:
	for o in others:
		if o.target_char == self and o.p_self_other >= 0.7 and p_adapt >= 0.3 and position.distance_to(o.position) < 46.0:
			_count("retreat")
			state = State.RETREAT
			target_char = null
			var away: Vector2 = (position - o.position).normalized()
			target_pos = position + away * 140.0
			_log_action("%sはそっと距離を取った" % char_name)
			return
	if p_adapt >= 0.3:
		var hated = _disliked_near(78.0)
		if hated != null:
			_count("retreat")
			state = State.RETREAT
			target_char = null
			var away2: Vector2 = (position - hated.position).normalized()
			target_pos = position + away2 * 130.0
			_log_action("%sは%sからそれとなく離れた" % [char_name, hated.char_name])
			return
	if _event_active:
		if randf() < _attend_probability():
			_count("attend")
			state = State.ATTEND
			target_pos = _event_pos + Vector2(randf_range(-24, 24), randf_range(-24, 24))
			_log_action("%sは“何か”の方へ向かった" % char_name)
			return
		elif p_adapt < 0.3:
			_count("stay")
			state = State.STAY
			_log_action("%sはそちらを見たが、動かなかった" % char_name)
			return
	var w := {}
	w["stay"] = clampf((1.0 - p_impulse) * 0.6 + (1.0 - p_adapt) * 1.5, 0.04, 6.0)
	w["wander"] = clampf(p_self_other * 1.1 + p_impulse * 0.5, 0.04, 6.0)
	w["approach"] = clampf((1.0 - p_esteem) * 1.8 + _best_liked_value() * 0.6, 0.0, 6.0)
	w["crowd"] = (2.6 if (p_self_other > 0.7 and p_empathy > 0.7) else 0.0)
	w["follow"] = clampf((_midness() - 0.4) * 2.6, 0.0, 6.0)
	if others.size() == 0:
		w["approach"] = 0.0
		w["crowd"] = 0.0
		w["follow"] = 0.0
	var pick := _weighted_pick(w)
	_count(pick)
	match pick:
		"stay":
			_do_stay()
		"wander":
			_do_wander()
		"approach":
			_do_approach(false)
		"crowd":
			_do_approach(true)
		"follow":
			_do_follow()
		_:
			_do_stay()
	_maybe_self_claim()

func _do_stay() -> void:
	target_char = null
	if position.distance_to(home) > 28.0:
		state = State.GO_PLACE
		target_pos = home
		_log_action("%sはいつもの場所へ戻ろうとした" % char_name)
	else:
		state = State.STAY
		_log_action("%sはその場にとどまっている" % char_name)

func _do_wander() -> void:
	target_char = null
	state = State.GO_PLACE
	target_pos = _random_place()
	_log_action("%sは自分の用のために歩き出した" % char_name)
	if p_impulse < 0.35 and randf() < 0.4:
		_log_action("%sは一歩踏み出す前に少し止まった" % char_name)

func _do_approach(pushy: bool) -> void:
	if others.size() == 0:
		_do_wander()
		return
	target_char = _nearest_other() if pushy else _most_liked_or_nearest()
	state = State.APPROACH
	target_pos = target_char.position
	if pushy:
		_log_action("%sは%sの方へ寄っていった" % [char_name, target_char.char_name])
	else:
		_log_action("%sは%sの様子をうかがいに近づいた" % [char_name, target_char.char_name])

func _do_follow() -> void:
	target_char = null
	state = State.GO_PLACE
	target_pos = _liked_center()
	_log_action("%sは人の集まる方へ流れた" % char_name)

func _maybe_self_claim() -> void:
	if randf() > 0.22:
		return
	if p_empathy > 0.6 and incoming_affinity() < -0.05:
		_log_claim("%sは「みんなとうまくやれている」と言った" % char_name)
		return
	var liked = _most_liked_or_nearest()
	if liked != null and float(rel.get(liked, 0.0)) > 0.3 and float(liked.rel.get(self, 0.0)) < 0.1 and p_empathy > 0.5:
		_log_claim("%sは「%sとは分かり合えている」と言った" % [char_name, liked.char_name])
		return
	if randf() < 0.4:
		_log_claim("%sは自分を中間くらいの人間だと言った" % char_name)

func _attend_probability() -> float:
	var v: float = p_impulse * 0.7 + p_empathy * 0.2 - (1.0 - p_adapt) * 0.3
	return clampf(v, 0.0, 0.95)

func _weighted_pick(w: Dictionary) -> String:
	var total: float = 0.0
	for k in w:
		total += float(w[k])
	if total <= 0.0:
		return "stay"
	var r: float = randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "stay"

func _midness() -> float:
	var s: float = absf(p_self_other - 0.5) + absf(p_impulse - 0.5) + absf(p_adapt - 0.5) + absf(p_esteem - 0.5) + absf(p_empathy - 0.5)
	return clampf(1.0 - (s / 5.0) * 2.0, 0.0, 1.0)

func _best_liked_value() -> float:
	var best: float = 0.0
	for o in others:
		best = maxf(best, float(rel.get(o, 0.0)))
	return best

func _count(a: String) -> void:
	_act_counts[a] = int(_act_counts.get(a, 0)) + 1

func _nearest_other():
	var best = null
	var bd: float = 1.0e9
	for o in others:
		var d := position.distance_to(o.position)
		if d < bd:
			bd = d
			best = o
	return best

func _most_liked_or_nearest():
	var best = null
	var bestv: float = 0.12
	for o in others:
		var v: float = rel.get(o, 0.0)
		if v > bestv:
			bestv = v
			best = o
	if best != null:
		return best
	return _nearest_other()

func _disliked_near(maxd: float):
	var worst = null
	var worstv: float = -0.45
	for o in others:
		var v: float = rel.get(o, 0.0)
		var d := position.distance_to(o.position)
		if d < maxd and v < worstv:
			worstv = v
			worst = o
	return worst

func _liked_center() -> Vector2:
	if others.size() == 0:
		return home
	var sum := Vector2.ZERO
	var wsum: float = 0.0
	for o in others:
		var ww: float = 1.0 + maxf(0.0, float(rel.get(o, 0.0)))
		sum += o.position * ww
		wsum += ww
	if wsum <= 0.0:
		return home
	return sum / wsum

func _random_place() -> Vector2:
	if places.size() == 0:
		return _random_point()
	return places[randi() % places.size()]

func _random_point() -> Vector2:
	return Vector2(
		randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		randf_range(bounds.position.y, bounds.position.y + bounds.size.y))

func _clamp_bounds() -> void:
	position.x = clamp(position.x, bounds.position.x, bounds.position.x + bounds.size.x)
	position.y = clamp(position.y, bounds.position.y, bounds.position.y + bounds.size.y)

func _log_action(s: String) -> void:
	logs.append("[t+%ds] ［行動］%s" % [int(_t), s])
	_trim()

func _log_claim(s: String) -> void:
	logs.append("[t+%ds] ［自己申告］%s" % [int(_t), s])
	_trim()

func _trim() -> void:
	if logs.size() > 80:
		logs = logs.slice(logs.size() - 80)

func _draw() -> void:
	# 生きている揺れ：上下のバウンド＋（衝動が高いほど）小刻みな横ジッター
	var bob: float = sin(_t * (2.0 + p_impulse * 4.0) + _phase) * (1.2 + p_impulse * 1.5)
	var jx: float = 0.0
	if p_impulse > 0.45:
		jx = sin(_t * 9.0 + _phase) * p_impulse * 1.2
	# 影（接地感）
	draw_circle(Vector2(0, 13), 9.0, Color(0, 0, 0, 0.30))
	# 社会的立ち位置リング（暖=好かれ / 寒=避けられ）
	var inc: float = incoming_affinity()
	if absf(inc) > 0.15:
		var a: float = clampf(absf(inc), 0.0, 1.0) * 0.85
		var rc := (Color(1.0, 0.6, 0.3, a) if inc > 0.0 else Color(0.4, 0.7, 1.0, a))
		draw_arc(Vector2(0, 2), 19.0, 0.0, TAU, 28, rc, 3.0)
	# 本体スプライト
	if sprite_tex != null:
		var sz: float = 34.0
		draw_texture_rect(sprite_tex, Rect2(-sz / 2.0 + jx, -sz + 14.0 + bob, sz, sz), false)
	else:
		draw_circle(Vector2.ZERO, RADIUS, color)
	if state == State.STAY:
		draw_arc(Vector2(0, 2), 16.0, 0.0, TAU, 20, Color(1, 1, 1, 0.18), 1.5)
