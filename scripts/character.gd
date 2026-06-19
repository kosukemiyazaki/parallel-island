extends Node2D

# 行動の「型」。状態が動き方として画面に出る。
enum State { STAY, GO_PLACE, APPROACH, RETREAT, ATTEND }

# 5軸パラメータ（0.0〜1.0）。クリックでログ枠に開示。
var p_self_other: float = 0.5   # 高=自分優先 / 低=他者寄り
var p_impulse: float = 0.5      # 高=即動く・速い / 低=間がある
var p_adapt: float = 0.5        # 高=新しい場所へ / 低=いつもの場所に固執
var p_esteem: float = 0.5       # 高=他者に左右されない / 低=確認が多い
var p_empathy: float = 0.5      # 高=「わかってる」確信（思い込み）

var char_name: String = "?"
var pattern: String = "?"
var color: Color = Color.WHITE

var others: Array = []
var places: Array = []
var home: Vector2 = Vector2.ZERO
var bounds: Rect2 = Rect2(0, 0, 1280, 720)

var state: int = State.STAY
var target_pos: Vector2 = Vector2.ZERO
var target_char = null

# 関係性レイヤー：相手(Character)ごとの好意(-1.0=嫌悪 .. +1.0=好意)。接触で増減し蓄積する。
var rel: Dictionary = {}
var _rel_band: Dictionary = {}   # 相手 -> 直近ログ済みの帯("like"/"dislike"/"")

var _decide_timer: float = 0.0
var _event_active: bool = false
var _event_pos: Vector2 = Vector2.ZERO
var logs: Array[String] = []

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
	var lbl := Label.new()
	lbl.text = char_name
	lbl.position = Vector2(-RADIUS, -RADIUS - 20.0)
	add_child(lbl)

func set_event(active: bool, pos: Vector2) -> void:
	_event_active = active
	_event_pos = pos

func is_relating() -> bool:
	return state == State.APPROACH or state == State.RETREAT

func affinity_to(o) -> float:
	return rel.get(o, 0.0)

# 周りから自分への好意の平均（社会的立ち位置）
func incoming_affinity() -> float:
	if others.size() == 0:
		return 0.0
	var s: float = 0.0
	for o in others:
		s += float(o.rel.get(self, 0.0))
	return s / float(others.size())

func _process(delta: float) -> void:
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
				# 詰められると好意が下がる。自己肯定が低いほど効く。
				cur -= 0.12 * delta * (1.2 - p_esteem)
			else:
				# 穏やかに同席すると少しずつ打ち解ける。
				cur += 0.06 * delta
		else:
			# 離れていると非常にゆっくり中立へ戻る（≒関係は基本持続する）。
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
	# 0) 押しの強い相手が近い → 距離を取る（柔軟な人だけ。不動の人は耐える）
	for o in others:
		if o.target_char == self and o.p_self_other >= 0.7 and p_adapt >= 0.3 and position.distance_to(o.position) < 46.0:
			state = State.RETREAT
			target_char = null
			var away: Vector2 = (position - o.position).normalized()
			target_pos = position + away * 140.0
			_log_action("%sはそっと距離を取った" % char_name)
			return
	# 0.5) 蓄積した嫌悪：嫌いな相手が近いと、それとなく離れる
	if p_adapt >= 0.3:
		var hated = _disliked_near(78.0)
		if hated != null:
			state = State.RETREAT
			target_char = null
			var away2: Vector2 = (position - hated.position).normalized()
			target_pos = position + away2 * 130.0
			_log_action("%sは%sからそれとなく離れた" % [char_name, hated.char_name])
			return
	# 1) 島に「出来事」がある → 性格で反応が割れる
	if _event_active:
		var attend: float = _attend_probability()
		if randf() < attend:
			state = State.ATTEND
			target_pos = _event_pos + Vector2(randf_range(-24, 24), randf_range(-24, 24))
			_log_action("%sは“何か”の方へ向かった" % char_name)
			return
		elif p_adapt < 0.3:
			state = State.STAY
			_log_action("%sはそちらを見たが、動かなかった" % char_name)
			return
	# 2) 変化に乏しい人（低適応）→ いつもの場所にとどまる＝「不動」
	if p_adapt < 0.3:
		if position.distance_to(home) > 28.0:
			state = State.GO_PLACE
			target_pos = home
			_log_action("%sはいつもの場所へ戻ろうとした" % char_name)
		else:
			state = State.STAY
			_log_action("%sはその場にとどまっている" % char_name)
		return
	# 3) 押しが強く思い込みが強い人 → 近くの誰かに詰める（相手は離れていく）
	if p_self_other > 0.7 and p_empathy > 0.7 and others.size() > 0:
		target_char = _nearest_other()
		state = State.APPROACH
		target_pos = target_char.position
		if randf() < 0.3:
			_log_claim("%sは「力になれると思う」と言った" % char_name)
		else:
			_log_action("%sは%sの方へ寄っていった" % [char_name, target_char.char_name])
		return
	# 4) 自己肯定感が低い人 → 好きな相手（いなければ近くの相手）に寄る
	if p_esteem < 0.4 and others.size() > 0:
		target_char = _most_liked_or_nearest()
		state = State.APPROACH
		target_pos = target_char.position
		_log_action("%sは%sの様子をうかがいに近づいた" % [char_name, target_char.char_name])
		return
	# 5) 自分本位な人 → 自分の用で場所を巡る＝「我が道」
	if p_self_other > 0.6:
		target_char = null
		state = State.GO_PLACE
		target_pos = _random_place()
		_log_action("%sは自分の用のために歩き出した" % char_name)
		return
	# 6) 中間の人 → 好きな人が多い方へ流される
	target_char = null
	state = State.GO_PLACE
	target_pos = _liked_center()
	_log_action("%sは人の集まる方へ流れた" % char_name)
	if p_impulse < 0.35 and randf() < 0.5:
		_log_action("%sは一歩踏み出す前に少し止まった" % char_name)

func _attend_probability() -> float:
	var v: float = p_impulse * 0.7 + p_empathy * 0.2 - (1.0 - p_adapt) * 0.3
	return clampf(v, 0.0, 0.95)

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
		var w: float = 1.0 + maxf(0.0, float(rel.get(o, 0.0)))
		sum += o.position * w
		wsum += w
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
	logs.append("［行動］" + s)
	_trim()

func _log_claim(s: String) -> void:
	logs.append("［自己申告］" + s)
	_trim()

func _trim() -> void:
	if logs.size() > 80:
		logs = logs.slice(logs.size() - 80)

func _draw() -> void:
	# 社会的立ち位置：周りからの好意/嫌悪を外周リングで（暖=好かれ / 寒=避けられ）
	var inc: float = incoming_affinity()
	if absf(inc) > 0.15:
		var a: float = clampf(absf(inc), 0.0, 1.0) * 0.85
		var rc := (Color(1.0, 0.6, 0.3, a) if inc > 0.0 else Color(0.4, 0.7, 1.0, a))
		draw_arc(Vector2.ZERO, RADIUS + 6.0, 0.0, TAU, 28, rc, 3.0)
	draw_circle(Vector2.ZERO, RADIUS, color)
	if state == State.STAY:
		draw_arc(Vector2.ZERO, RADIUS + 3.0, 0.0, TAU, 24, Color(1, 1, 1, 0.45), 2.0)
	else:
		var dir := target_pos - position
		if dir.length() > 1.0:
			draw_line(Vector2.ZERO, dir.normalized() * (RADIUS + 9.0), Color(1, 1, 1, 0.6), 2.0)
