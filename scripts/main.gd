extends Node2D

const W: int = 1280
const H: int = 720

# class_name は初回ロード時に未登録のことがあるため、preload で明示参照する。
const CharacterScript := preload("res://scripts/character.gd")

# 初期キャラ。図鑑（設計書 §2）のパターンに対応。性格の差が動きで出るよう値を強めに振っている。
const ROSTER: Array = [
	{"name": "カエデ", "pattern": "渇望爆発型（つきまとう）", "self_other": 0.5, "impulse": 0.85, "adapt": 0.5, "esteem": 0.2, "empathy": 0.4, "color": Color(0.91, 0.36, 0.36)},
	{"name": "ソラ", "pattern": "持続燃焼型（我が道）", "self_other": 0.65, "impulse": 0.85, "adapt": 0.6, "esteem": 0.85, "empathy": 0.4, "color": Color(0.96, 0.73, 0.27)},
	{"name": "ナギ", "pattern": "善意搾取型（人に詰める）", "self_other": 0.8, "impulse": 0.5, "adapt": 0.45, "esteem": 0.6, "empathy": 0.85, "color": Color(0.45, 0.78, 0.5)},
	{"name": "イオ", "pattern": "不動の人（動かない）", "self_other": 0.5, "impulse": 0.35, "adapt": 0.15, "esteem": 0.85, "empathy": 0.4, "color": Color(0.45, 0.6, 0.9)},
	{"name": "ミオ", "pattern": "全部中間（流される）", "self_other": 0.5, "impulse": 0.5, "adapt": 0.5, "esteem": 0.5, "empathy": 0.5, "color": Color(0.72, 0.72, 0.78)},
]

var characters: Array = []
var places: Array = []
var selected = null
var log_label: RichTextLabel = null

var _event_active: bool = false
var _event_pos: Vector2 = Vector2.ZERO
var _event_timer: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	_make_places()
	_spawn_characters()
	_build_ui()

func _make_places() -> void:
	places = [
		Vector2(220, 230),
		Vector2(640, 220),
		Vector2(260, 520),
		Vector2(600, 500),
	]

func _spawn_characters() -> void:
	var i := 0
	for d in ROSTER:
		var c = CharacterScript.new()
		add_child(c)
		var pos: Vector2 = places[i % places.size()] + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		c.setup(d, pos, places)
		c.bounds = Rect2(70, 120, 720, 520)  # 右のログパネルに被らない範囲
		characters.append(c)
		i += 1
	for c in characters:
		c.others = characters.filter(func(x): return x != c)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "PARALLEL ISLAND — PHASE 1"
	title.position = Vector2(16, 8)
	layer.add_child(title)
	var hint := Label.new()
	hint.text = "SPACE: 島に“出来事”を起こす  /  キャラをクリック: ログを見る"
	hint.position = Vector2(16, 30)
	hint.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(hint)
	var panel := Panel.new()
	panel.position = Vector2(W - 440, 44)
	panel.size = Vector2(424, H - 72)
	layer.add_child(panel)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.position = Vector2(W - 428, 54)
	log_label.size = Vector2(400, H - 92)
	layer.add_child(log_label)
	_refresh_log()

func _process(delta: float) -> void:
	_t += delta
	if _event_active:
		_event_timer -= delta
		if _event_timer <= 0.0:
			_set_event(false, Vector2.ZERO)
	if selected != null:
		_refresh_log()
	queue_redraw()

func _set_event(active: bool, pos: Vector2) -> void:
	_event_active = active
	_event_pos = pos
	for c in characters:
		c.set_event(active, pos)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		var p := Vector2(randf_range(160, 690), randf_range(190, 560))
		_event_timer = 7.0
		_set_event(true, p)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_global_mouse_position()
		var nearest = null
		var best: float = 1.0e9
		for c in characters:
			var dist := m.distance_to(c.position)
			if dist < best:
				best = dist
				nearest = c
		if nearest != null and best < 30.0:
			selected = nearest
			_refresh_log()

func _draw() -> void:
	# 島のランドマーク（場所）
	for pl in places:
		draw_rect(Rect2(pl - Vector2(7, 7), Vector2(14, 14)), Color(1, 1, 1, 0.18), false, 2.0)
	# 関係線：誰が誰に向かっている / 誰から離れているか
	for c in characters:
		if c.is_relating() and c.target_char != null:
			draw_line(c.position, c.target_char.position, Color(1, 1, 1, 0.12), 1.0)
	# 出来事（脈打つリング）
	if _event_active:
		var r: float = 18.0 + sin(_t * 4.0) * 6.0
		draw_arc(_event_pos, r, 0.0, TAU, 32, Color(1.0, 0.85, 0.3, 0.9), 3.0)
		draw_circle(_event_pos, 4.0, Color(1.0, 0.85, 0.3, 0.9))

func _refresh_log() -> void:
	if log_label == null:
		return
	if selected == null:
		log_label.text = "（キャラをクリックすると、その人の［行動ログ］と［自己申告ログ］が出ます）"
		return
	var c = selected
	var head := "[b]%s[/b]　手がかり: %s\n" % [c.char_name, c.pattern]
	head += "5軸  自己中心 %.2f / 衝動 %.2f / 適応 %.2f / 自己肯定 %.2f / 共感 %.2f\n\n" % [c.p_self_other, c.p_impulse, c.p_adapt, c.p_esteem, c.p_empathy]
	var body := ""
	for line in c.logs:
		if line.begins_with("［自己申告］"):
			body += "[color=#d4af37]" + line + "[/color]\n"
		else:
			body += line + "\n"
	log_label.text = head + body
