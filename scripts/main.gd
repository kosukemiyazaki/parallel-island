extends Node2D

const W: int = 1280
const H: int = 720

# class_name は初回ロード時に未登録のことがあるため、preload で明示参照する。
const CharacterScript := preload("res://scripts/character.gd")

# 初期キャラ。図鑑（設計書 §2）のパターンに対応させてある。
const ROSTER: Array = [
	{"name": "カエデ", "pattern": "渇望爆発型", "self_other": 0.5, "impulse": 0.85, "adapt": 0.5, "esteem": 0.2, "empathy": 0.4, "color": Color(0.91, 0.36, 0.36)},
	{"name": "ソラ", "pattern": "持続燃焼型", "self_other": 0.55, "impulse": 0.85, "adapt": 0.6, "esteem": 0.85, "empathy": 0.4, "color": Color(0.96, 0.73, 0.27)},
	{"name": "ナギ", "pattern": "善意搾取型", "self_other": 0.8, "impulse": 0.5, "adapt": 0.45, "esteem": 0.6, "empathy": 0.85, "color": Color(0.45, 0.78, 0.5)},
	{"name": "イオ", "pattern": "不動の人", "self_other": 0.5, "impulse": 0.35, "adapt": 0.15, "esteem": 0.85, "empathy": 0.4, "color": Color(0.45, 0.6, 0.9)},
	{"name": "ミオ", "pattern": "全部中間", "self_other": 0.5, "impulse": 0.5, "adapt": 0.5, "esteem": 0.5, "empathy": 0.5, "color": Color(0.72, 0.72, 0.78)},
]

var characters: Array = []
var selected = null
var log_label: RichTextLabel = null

func _ready() -> void:
	_spawn_characters()
	_build_ui()

func _spawn_characters() -> void:
	for d in ROSTER:
		var c = CharacterScript.new()
		add_child(c)
		var pos := Vector2(randf_range(140, W - 140), randf_range(160, H - 160))
		c.setup(d, pos)
		c.bounds = Rect2(60, 110, W - 120, H - 170)
		characters.append(c)
	for c in characters:
		c.others = characters.filter(func(x): return x != c)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "PARALLEL ISLAND — PHASE 1  /  キャラをクリックすると行動ログ・自己申告ログが見える"
	title.position = Vector2(16, 10)
	layer.add_child(title)
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

func _process(_delta: float) -> void:
	if selected != null:
		_refresh_log()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_global_mouse_position()
		var nearest = null
		var best := 1.0e9
		for c in characters:
			var dist := m.distance_to(c.position)
			if dist < best:
				best = dist
				nearest = c
		if nearest != null and best < 30.0:
			selected = nearest
			_refresh_log()

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
