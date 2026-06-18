extends Node2D

# 行動の「型」。説明テキストではなく、この状態が動き方として画面に出る。
enum State { STAY, GO_PLACE, APPROACH, RETREAT, ATTEND }

# 5軸パラメータ（0.0〜1.0）。本来は非公開。PHASE 1 ではクリックでログ枠に開示。
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

var _decide_timer: float = 0.0
var _event_active: bool = false
var _event_pos: Vector2 = Vector2.ZERO
var logs: Array[String] = []

const RADIUS: float = 13.0

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

func _process(delta: float) -> void:
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide()
		# 衝動性が高いほど判断が速い。全体はゆっくりめ＝観察しやすく。
		_decide_timer = lerp(3.6, 1.1, p_impulse) + randf() * 0.4
	if state != State.STAY:
		var speed: float = lerp(16.0, 62.0, p_impulse)
		var to_t := target_pos - position
		if to_t.length() > 3.0:
			position += to_t.normalized() * speed * delta
		elif state == State.APPROACH and target_char != null:
			target_pos = target_char.position  # 相手が動けば付いていく
	_clamp_bounds()
	queue_redraw()

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
	# 4) 自己肯定感が低い人 → 誰かを確認しに、そばへ（つきまとい）
	if p_esteem < 0.4 and others.size() > 0:
		target_char = _nearest_other()
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
	# 6) 中間の人 → 人が集まる方へ流される
	target_char = null
	state = State.GO_PLACE
	target_pos = _center_of_others()
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

func _center_of_others() -> Vector2:
	if others.size() == 0:
		return home
	var sum := Vector2.ZERO
	for o in others:
		sum += o.position
	return sum / float(others.size())

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
	draw_circle(Vector2.ZERO, RADIUS, color)
	# 止まっている人は輪っかで「静止」を際立たせる
	if state == State.STAY:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 2.0)
	else:
		var dir := target_pos - position
		if dir.length() > 1.0:
			draw_line(Vector2.ZERO, dir.normalized() * (RADIUS + 8.0), Color(1, 1, 1, 0.7), 2.0)
