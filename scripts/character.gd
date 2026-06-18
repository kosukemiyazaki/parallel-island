extends Node2D
class_name Character

# 5軸パラメータ（0.0〜1.0）。本来は非公開。PHASE 1 ではログ枠に開示する。
var p_self_other: float = 0.5   # 高=自分優先 / 低=他者寄り
var p_impulse: float = 0.5      # 高=即動く・速い / 低=間がある
var p_adapt: float = 0.5        # 高=新しい場所へ / 低=いつもの場所へ固執
var p_esteem: float = 0.5       # 高=他者の反応に左右されない / 低=確認が多い
var p_empathy: float = 0.5      # 高=「わかってる」確信（思い込み）

var char_name: String = "?"
var pattern: String = "?"
var color: Color = Color.WHITE

var others: Array = []
var bounds: Rect2 = Rect2(0, 0, 1280, 720)

var _target: Vector2 = Vector2.ZERO
var _home: Vector2 = Vector2.ZERO
var _decide_timer: float = 0.0
var logs: Array[String] = []

const RADIUS: float = 14.0

func setup(params: Dictionary, pos: Vector2) -> void:
	char_name = params.get("name", "?")
	pattern = params.get("pattern", "?")
	p_self_other = params.get("self_other", 0.5)
	p_impulse = params.get("impulse", 0.5)
	p_adapt = params.get("adapt", 0.5)
	p_esteem = params.get("esteem", 0.5)
	p_empathy = params.get("empathy", 0.5)
	color = params.get("color", Color.WHITE)
	position = pos
	_home = pos
	_target = pos
	var lbl := Label.new()
	lbl.text = char_name
	lbl.position = Vector2(-RADIUS, -RADIUS - 20.0)
	add_child(lbl)

func _process(delta: float) -> void:
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide()
		# 衝動性が高いほど次の判断までが短い（＝即動く）。低いほど「間」が空く。
		_decide_timer = lerp(2.2, 0.5, p_impulse) + randf() * 0.3
	# 移動：衝動性が速度に出る。
	var speed: float = lerp(20.0, 95.0, p_impulse)
	var to_t := _target - position
	if to_t.length() > 2.0:
		position += to_t.normalized() * speed * delta
	_clamp_bounds()
	queue_redraw()

func _decide() -> void:
	var roll := randf()
	# 自己肯定感が低いほど、他者の様子を確認しに行く頻度が高い。
	var check_freq: float = lerp(0.15, 0.7, 1.0 - p_esteem)
	if others.size() > 0 and roll < check_freq:
		var o = others[randi() % others.size()]
		_target = o.position + Vector2(randf_range(-40, 40), randf_range(-40, 40))
		_log_action("%sは%sの様子をうかがいに近づいた" % [char_name, o.char_name])
		return
	# 自己中心性：高→自分の用事 / 低→誰かのそば / 中間→適応性で分岐
	if p_self_other > 0.6:
		_target = _random_point()
		_log_action("%sは自分の用事のために歩き出した" % char_name)
	elif p_self_other < 0.4 and others.size() > 0:
		var o = others[randi() % others.size()]
		_target = o.position
		_log_action("%sは誰かのそばへ向かった" % char_name)
	else:
		if p_adapt > 0.55:
			_target = _random_point()
			_log_action("%sはまだ行っていない方へ足を向けた" % char_name)
		else:
			_target = _home
			_log_action("%sはいつもの場所に戻ろうとした" % char_name)
	# 衝動性が低い → 踏み出す前の「間」
	if p_impulse < 0.35 and randf() < 0.45:
		_log_action("%sは一歩踏み出す前に少し止まった" % char_name)
	# 共感性が高い →「わかってる」前提の自己申告（実際とズレる種）
	if p_empathy > 0.6 and randf() < 0.25:
		_log_claim("%sは「あの人の気持ちは分かってる」と言った" % char_name)
	# 記憶の歪みの種：自己像のズレた自己申告
	if randf() < 0.07:
		_log_claim("%sは自分を中間値の人間だと言った" % char_name)

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
	var dir := _target - position
	if dir.length() > 1.0:
		draw_line(Vector2.ZERO, dir.normalized() * (RADIUS + 7.0), Color(1, 1, 1, 0.7), 2.0)
