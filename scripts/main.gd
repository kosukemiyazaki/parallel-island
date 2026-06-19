extends Node2D

const W: int = 1280
const H: int = 720
const TILE: int = 32
const COLS: int = 25   # 床の部屋: 25x22 タイル = 800x704
const ROWS: int = 22

const CharacterScript := preload("res://scripts/character.gd")

# 図鑑（設計書 §2）対応。tile=[col,row] は Tiny Dungeon タイルシート上の位置。
const ROSTER: Array = [
	{"name": "カエデ", "pattern": "渇望爆発型（つきまとう）", "self_other": 0.5, "impulse": 0.85, "adapt": 0.5, "esteem": 0.2, "empathy": 0.4, "color": Color(0.91, 0.36, 0.36), "tile": [1, 9]},
	{"name": "ソラ", "pattern": "持続燃焼型（我が道）", "self_other": 0.65, "impulse": 0.85, "adapt": 0.6, "esteem": 0.85, "empathy": 0.4, "color": Color(0.96, 0.73, 0.27), "tile": [4, 7]},
	{"name": "ナギ", "pattern": "善意搾取型（人に詰める）", "self_other": 0.8, "impulse": 0.5, "adapt": 0.45, "esteem": 0.6, "empathy": 0.85, "color": Color(0.45, 0.78, 0.5), "tile": [0, 7]},
	{"name": "イオ", "pattern": "不動の人（動かない）", "self_other": 0.5, "impulse": 0.35, "adapt": 0.15, "esteem": 0.85, "empathy": 0.4, "color": Color(0.45, 0.6, 0.9), "tile": [0, 8]},
	{"name": "ミオ", "pattern": "全部中間（流される）", "self_other": 0.5, "impulse": 0.5, "adapt": 0.5, "esteem": 0.5, "empathy": 0.5, "color": Color(0.72, 0.72, 0.78), "tile": [3, 8]},
]

var characters: Array = []
var places: Array = []
var selected = null
var log_label: RichTextLabel = null
var portrait: TextureRect = null
var ticker: RichTextLabel = null
var feed: Array = []
var _flash: Dictionary = {}
var _ui_font = null

var _sheet = null
var _floor_a = null
var _floor_b = null
var _wall_t = null
var _props: Array = []

var _event_active: bool = false
var _event_pos: Vector2 = Vector2.ZERO
var _event_timer: float = 0.0
var _t: float = 0.0
var _probe: bool = OS.has_environment("PI_PROBE")
var _probe_t: float = 0.0

func _ready() -> void:
	_apply_font()
	_load_tiles()
	_make_places()
	_spawn_characters()
	_build_ui()

func _apply_font() -> void:
	_ui_font = load("res://assets/NotoSansJP.ttf")
	if _ui_font == null:
		return
	var th := Theme.new()
	th.default_font = _ui_font
	th.default_font_size = 16
	var w := get_window()
	if w != null:
		w.theme = th

func _apply_ui_font(ctrl: Control) -> void:
	if _ui_font == null:
		return
	if ctrl is RichTextLabel:
		ctrl.add_theme_font_override("normal_font", _ui_font)
		ctrl.add_theme_font_override("bold_font", _ui_font)
		ctrl.add_theme_font_override("italics_font", _ui_font)
		ctrl.add_theme_font_override("bold_italics_font", _ui_font)
		ctrl.add_theme_font_override("mono_font", _ui_font)
	else:
		ctrl.add_theme_font_override("font", _ui_font)

func _load_tiles() -> void:
	_sheet = load("res://assets/tiny-dungeon/Tilemap/tilemap_packed.png")
	_floor_a = _atlas(0, 4)   # 砂床
	_floor_b = _atlas(1, 4)   # 砂床（粒）
	_wall_t = _atlas(10, 4)   # 石レンガ壁
	_props = [_atlas(5, 8), _atlas(5, 2)]  # 宝箱 / かがり火

func _atlas(col: int, row: int):
	if _sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = _sheet
	at.region = Rect2(col * 16, row * 16, 16, 16)
	return at

func _make_places() -> void:
	places = [
		Vector2(140, 150),
		Vector2(660, 150),
		Vector2(140, 560),
		Vector2(660, 560),
	]

func _spawn_characters() -> void:
	var i := 0
	for d in ROSTER:
		var c = CharacterScript.new()
		add_child(c)
		var pos: Vector2 = places[i % places.size()] + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		c.setup(d, pos, places)
		c.bounds = Rect2(56, 56, 688, 592)
		c.sprite_tex = _atlas(d["tile"][0], d["tile"][1])
		c.world = self
		characters.append(c)
		i += 1
	for c in characters:
		c.others = characters.filter(func(x): return x != c)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# 左上HUDの読みやすさ用の半透明バナー
	var hud := Panel.new()
	hud.position = Vector2(6, 4)
	hud.size = Vector2(474, 102)
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0, 0, 0, 0.45)
	hsb.set_corner_radius_all(6)
	hud.add_theme_stylebox_override("panel", hsb)
	layer.add_child(hud)
	var panel := Panel.new()
	panel.position = Vector2(W - 440, 44)
	panel.size = Vector2(424, H - 72)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.20, 0.96)
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 1, 1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12
	sb.content_margin_top = 10
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var title := Label.new()
	title.text = "PARALLEL ISLAND"
	title.position = Vector2(18, 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 5)
	layer.add_child(title)
	_apply_ui_font(title)
	var hint := Label.new()
	hint.text = "ボタン: 島に“出来事”を起こす  /  キャラをタップ: ログと関係"
	hint.position = Vector2(18, 34)
	hint.modulate = Color(1, 1, 1, 0.85)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 4)
	layer.add_child(hint)
	_apply_ui_font(hint)
	var ev_btn := Button.new()
	ev_btn.text = "出来事を起こす"
	ev_btn.position = Vector2(18, 60)
	ev_btn.size = Vector2(180, 42)
	ev_btn.pressed.connect(_trigger_event)
	layer.add_child(ev_btn)
	_apply_ui_font(ev_btn)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.position = Vector2(W - 424, 56)
	log_label.size = Vector2(404, H - 96)
	layer.add_child(log_label)
	_apply_ui_font(log_label)
	portrait = TextureRect.new()
	portrait.position = Vector2(W - 80, 54)
	portrait.size = Vector2(52, 52)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.add_child(portrait)
	# 島の出来事ティッカー（画面下）
	var tbg := Panel.new()
	tbg.position = Vector2(8, H - 96)
	tbg.size = Vector2(816, 84)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0, 0, 0, 0.42)
	tsb.set_corner_radius_all(6)
	tbg.add_theme_stylebox_override("panel", tsb)
	layer.add_child(tbg)
	ticker = RichTextLabel.new()
	ticker.bbcode_enabled = true
	ticker.position = Vector2(20, H - 90)
	ticker.size = Vector2(796, 76)
	layer.add_child(ticker)
	_apply_ui_font(ticker)
	_update_ticker()
	_refresh_log()

func _process(delta: float) -> void:
	_t += delta
	for k in _flash.keys():
		_flash[k] = float(_flash[k]) - delta
		if float(_flash[k]) <= 0.0:
			_flash.erase(k)
	if _probe:
		_probe_t += delta
		if _probe_t >= 8.0:
			_probe_t = 0.0
			_dump_relationships()
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

func _trigger_event() -> void:
	var p := Vector2(randf_range(120, 680), randf_range(120, 600))
	_event_timer = 7.0
	_set_event(true, p)

func report_event(text: String, a, b) -> void:
	feed.append("[t+%ds] %s" % [int(_t), text])
	if feed.size() > 8:
		feed = feed.slice(feed.size() - 8)
	if a != null and b != null:
		_flash[str(a.get_instance_id()) + "_" + str(b.get_instance_id())] = 1.0
		_flash[str(b.get_instance_id()) + "_" + str(a.get_instance_id())] = 1.0
	_update_ticker()

func _update_ticker() -> void:
	if ticker == null:
		return
	var lines := ""
	var start: int = maxi(0, feed.size() - 3)
	for idx in range(start, feed.size()):
		lines += String(feed[idx]) + "\n"
	ticker.text = "[b]島の出来事[/b]\n" + lines

func _dump_relationships() -> void:
	for c in characters:
		var inc: float = c.incoming_affinity()
		var parts := ""
		for o in c.others:
			parts += "%s=%+.2f " % [o.char_name, float(c.rel.get(o, 0.0))]
		print("PROBE %s inc=%+.2f acts=%s | %s" % [c.char_name, inc, str(c._act_counts), parts])
	print("PROBE ----")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_trigger_event()
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
		if nearest != null and best < 42.0:
			selected = nearest
			_refresh_log()

func _draw() -> void:
	# 背景（部屋の外＝暗）
	draw_rect(Rect2(0, 0, W, H), Color(0.07, 0.07, 0.09))
	# 床＋壁
	for cy in range(ROWS):
		for cx in range(COLS):
			var px := cx * TILE
			var py := cy * TILE
			if cx == 0 or cy == 0 or cx == COLS - 1 or cy == ROWS - 1:
				if _wall_t != null:
					draw_texture_rect(_wall_t, Rect2(px, py, TILE, TILE), false)
			else:
				var t = _floor_b if ((cx * 7 + cy * 13) % 5 == 0) else _floor_a
				if t != null:
					draw_texture_rect(t, Rect2(px, py, TILE, TILE), false)
	# ランドマーク
	var pi := 0
	for pl in places:
		var prop = _props[pi % _props.size()]
		if prop != null:
			draw_texture_rect(prop, Rect2(pl.x - 16, pl.y - 8, 32, 32), false)
		pi += 1
	# 関係線（暖=好意 / 寒=嫌悪、太さ=強さ）
	for i in range(characters.size()):
		for j in range(i + 1, characters.size()):
			var a = characters[i]
			var b = characters[j]
			var avg: float = (float(a.rel.get(b, 0.0)) + float(b.rel.get(a, 0.0))) * 0.5
			var mag: float = absf(avg)
			var fl: float = float(_flash.get(str(a.get_instance_id()) + "_" + str(b.get_instance_id()), 0.0))
			if mag > 0.22 or fl > 0.0:
				var alpha: float = clampf(0.28 + mag * 0.5 + fl * 0.6, 0.0, 1.0)
				var col := (Color(1.0, 0.62, 0.3, alpha) if avg >= 0.0 else Color(0.45, 0.7, 1.0, alpha))
				draw_line(a.position, b.position, col, 1.0 + mag * 3.0 + fl * 4.0)
	# 出来事
	if _event_active:
		var r: float = 18.0 + sin(_t * 4.0) * 6.0
		draw_arc(_event_pos, r, 0.0, TAU, 32, Color(1.0, 0.85, 0.3, 0.95), 3.0)
	# 選択中のキャラを強調
	if selected != null:
		draw_arc(selected.position + Vector2(0, 2), 22.0, 0.0, TAU, 28, Color(1.0, 0.95, 0.4, 0.9), 2.5)

func _refresh_log() -> void:
	if log_label == null:
		return
	if portrait != null:
		portrait.texture = (selected.sprite_tex if selected != null else null)
	if selected == null:
		log_label.text = "（キャラをタップすると、その人の関係・行動ログ・自己申告ログが出ます）"
		return
	var c = selected
	var head := "[b]%s[/b]　手がかり: %s\n" % [c.char_name, c.pattern]
	head += "5軸  自己中心 %.2f / 衝動 %.2f / 適応 %.2f / 自己肯定 %.2f / 共感 %.2f\n" % [c.p_self_other, c.p_impulse, c.p_adapt, c.p_esteem, c.p_empathy]
	var gap_o = null
	var gap_v: float = 0.3
	for o in c.others:
		var mine: float = float(c.rel.get(o, 0.0))
		var theirs: float = float(o.rel.get(c, 0.0))
		if mine > 0.3 and (mine - theirs) > gap_v:
			gap_v = mine - theirs
			gap_o = o
	if gap_o != null:
		head += "[color=#ff6b6b]※ズレ: %s は %s を好き(%+.2f) けれど %s は %+.2f（一方通行）[/color]\n" % [c.char_name, gap_o.char_name, float(c.rel.get(gap_o, 0.0)), gap_o.char_name, float(gap_o.rel.get(c, 0.0))]
	var rels := ""
	for o in c.others:
		var v: float = float(c.rel.get(o, 0.0))
		if absf(v) > 0.15:
			var mark := "♥" if v > 0.0 else "✕"
			var cc := "#e0884a" if v > 0.0 else "#5aa0e0"
			rels += "[color=%s]%s%s%+.2f[/color]　" % [cc, o.char_name, mark, v]
	if rels == "":
		rels = "（まだ関係は薄い）"
	head += "関係: " + rels + "\n\n"
	var body := ""
	for line in c.logs:
		if line.find("［自己申告］") != -1:
			body += "[color=#d4af37]" + line + "[/color]\n"
		else:
			body += line + "\n"
	log_label.text = head + body
