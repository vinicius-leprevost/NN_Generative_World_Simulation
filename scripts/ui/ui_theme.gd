class_name UiTheme
## UiTheme: code-built modern dark theme for the whole interface.
## Glassy rounded cards with soft shadows, a warm gold accent, hover and
## pressed feedback on every clickable control, slim scrollbars, and the
## OS system font (Segoe UI on Windows).

const BG := Color(0.075, 0.085, 0.105, 0.93)      # card background
const BG2 := Color(0.115, 0.125, 0.155, 0.97)     # popups / inputs
const BTN := Color(0.17, 0.19, 0.235, 0.9)
const BTN_HOVER := Color(0.235, 0.26, 0.32, 0.95)
const BTN_PRESS := Color(0.30, 0.26, 0.16, 0.95)
const ACCENT := Color(1.0, 0.78, 0.35)            # warm gold
const ACCENT_DIM := Color(1.0, 0.78, 0.35, 0.45)
const ACCENT_SOFT := Color(1.0, 0.78, 0.35, 0.14)
const TEXT := Color(0.93, 0.94, 0.96)
const TEXT_DIM := Color(0.62, 0.66, 0.72)
const LINE := Color(1, 1, 1, 0.07)

static func build() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = ["Segoe UI", "Arial"]
	t.default_font = font
	t.default_font_size = 15

	# ---- cards ----
	t.set_stylebox("panel", "PanelContainer", card())

	# ---- buttons ----
	t.set_stylebox("normal", "Button", flat(BTN, 8, LINE))
	t.set_stylebox("hover", "Button", flat(BTN_HOVER, 8, ACCENT_DIM))
	t.set_stylebox("pressed", "Button", flat(BTN_PRESS, 8, ACCENT))
	t.set_stylebox("disabled", "Button", flat(Color(0.12, 0.13, 0.15, 0.6), 8, LINE))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)

	# ---- option buttons (dropdowns) ----
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(style_name, "OptionButton", t.get_stylebox(style_name, "Button"))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", Color.WHITE)
	t.set_color("font_pressed_color", "OptionButton", ACCENT)

	# ---- popup menus ----
	t.set_stylebox("panel", "PopupMenu", flat(BG2, 10, LINE, 1, 6))
	t.set_stylebox("hover", "PopupMenu", flat(ACCENT_SOFT, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 6)

	# ---- sliders ----
	var track := flat(Color(1, 1, 1, 0.10), 3)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", flat(ACCENT_DIM, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(ACCENT, 3))
	t.set_icon("grabber", "HSlider", circle_icon(14, Color(0.9, 0.9, 0.95), LINE))
	t.set_icon("grabber_highlight", "HSlider", circle_icon(16, ACCENT, LINE))
	t.set_icon("grabber_disabled", "HSlider", circle_icon(12, TEXT_DIM, LINE))

	# ---- tabs ----
	t.set_stylebox("panel", "TabContainer", flat(Color(1, 1, 1, 0.025), 8))
	var tab_sel := flat(ACCENT_SOFT, 7)
	tab_sel.border_width_bottom = 2
	tab_sel.border_color = ACCENT
	tab_sel.set_content_margin_all(7.0)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	var tab_un := flat(Color(0, 0, 0, 0), 7)
	tab_un.set_content_margin_all(7.0)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	var tab_hov := flat(Color(1, 1, 1, 0.05), 7)
	tab_hov.set_content_margin_all(7.0)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font_size("font_size", "TabContainer", 14)

	# ---- lists ----
	t.set_stylebox("panel", "ItemList", flat(Color(0, 0, 0, 0.25), 8, LINE, 1, 6))
	t.set_stylebox("selected", "ItemList", flat(ACCENT_SOFT, 4))
	t.set_stylebox("selected_focus", "ItemList", flat(ACCENT_SOFT, 4))
	t.set_stylebox("hovered", "ItemList", flat(Color(1, 1, 1, 0.04), 4))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT_DIM)
	t.set_color("font_hovered_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", TEXT)
	t.set_constant("v_separation", "ItemList", 5)
	t.set_font_size("font_size", "ItemList", 13)

	# ---- text ----
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 2))

	# ---- separators ----
	var sep := StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = LINE
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	# ---- scrollbars (slim) ----
	t.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber", "VScrollBar", flat(Color(1, 1, 1, 0.14), 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(1, 1, 1, 0.25), 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(ACCENT_DIM, 3))
	t.set_stylebox("scroll", "HScrollBar", flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber", "HScrollBar", flat(Color(1, 1, 1, 0.14), 3))
	t.set_stylebox("grabber_highlight", "HScrollBar", flat(Color(1, 1, 1, 0.25), 3))
	t.set_stylebox("grabber_pressed", "HScrollBar", flat(ACCENT_DIM, 3))

	# ---- tooltips ----
	t.set_stylebox("panel", "TooltipPanel", flat(BG2, 8, LINE, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# ---- container spacing ----
	t.set_constant("separation", "VBoxContainer", 7)
	t.set_constant("separation", "HBoxContainer", 7)
	t.set_constant("h_separation", "GridContainer", 7)
	t.set_constant("v_separation", "GridContainer", 7)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)
	return t

static func flat(bg: Color, radius: int, border := Color(0, 0, 0, 0), border_w := 1, margin := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(float(margin))
	if border.a > 0.001:
		s.set_border_width_all(border_w)
		s.border_color = border
	s.anti_aliasing = true
	return s

static func card() -> StyleBoxFlat:
	var s := flat(BG, 12, LINE, 1, 12)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	return s

static func pill(bg: Color) -> StyleBoxFlat:
	var s := flat(bg, 18, LINE, 1, 8)
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	return s

static func circle_icon(diameter: int, fill: Color, ring: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := (diameter - 1) * 0.5
	for y in range(diameter):
		for x in range(diameter):
			var d := Vector2(x - c, y - c).length()
			if d <= c - 1.0:
				img.set_pixel(x, y, fill)
			elif d <= c:
				img.set_pixel(x, y, Color(ring.r, ring.g, ring.b, fill.a * (c - d + 1.0) * 0.5))
	return ImageTexture.create_from_image(img)
