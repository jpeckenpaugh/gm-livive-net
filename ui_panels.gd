extends Control

# Collapsible top HUD and bottom-right claim survey.
# Collapsing hides the panel content but leaves a small show button visible,
# so the panels can be shrunk without losing the way to bring them back.

const TOP_COLLAPSED_HALF_WIDTH: float = 100.0
const TOP_COLLAPSED_HEIGHT: float = 44.0
const NET_COLLAPSED_WIDTH: float = 200.0
const NET_COLLAPSED_HEIGHT: float = 44.0
const NET_RIGHT_MARGIN: float = 24.0
const NET_BOTTOM_MARGIN: float = 24.0

@onready var _top_panel: PanelContainer = $Panel
@onready var _top_title: Label = $Panel/VBoxContainer/TitleRow/TitleLabel
@onready var _top_toggle: Button = $Panel/VBoxContainer/TitleRow/TopToggle
@onready var _top_face_info: Label = $Panel/VBoxContainer/FaceInfoLabel
@onready var _top_stats: Label = $Panel/VBoxContainer/StatsLabel
@onready var _top_actions: HBoxContainer = $Panel/VBoxContainer/ActionRow

@onready var _net_panel: PanelContainer = $CubeNetPanel
@onready var _net_title: Label = $CubeNetPanel/VBox/TitleRow/NetTitleLabel
@onready var _net_toggle: Button = $CubeNetPanel/VBox/TitleRow/NetToggle
@onready var _net_canvas: Control = $CubeNetPanel/VBox/NetCanvas
@onready var _net_footer: Label = $CubeNetPanel/VBox/NetFooterLabel

var _top_expanded: Array[float] = []
var _net_expanded: Array[float] = []
var _top_collapsed: bool = false
var _net_collapsed: bool = false

func _ready() -> void:
	_top_expanded = _snapshot_offsets(_top_panel)
	_net_expanded = _snapshot_offsets(_net_panel)
	_top_toggle.pressed.connect(_toggle_top)
	_net_toggle.pressed.connect(_toggle_net)
	_apply_top()
	_apply_net()

func _snapshot_offsets(panel: Control) -> Array[float]:
	return [
		panel.offset_left,
		panel.offset_top,
		panel.offset_right,
		panel.offset_bottom,
	]

func _toggle_top() -> void:
	_top_collapsed = not _top_collapsed
	_apply_top()

func _toggle_net() -> void:
	_net_collapsed = not _net_collapsed
	_apply_net()

func _apply_top() -> void:
	_top_title.visible = not _top_collapsed
	_top_face_info.visible = not _top_collapsed
	_top_stats.visible = not _top_collapsed
	_top_actions.visible = not _top_collapsed

	if _top_collapsed:
		_top_panel.offset_left = -TOP_COLLAPSED_HALF_WIDTH
		_top_panel.offset_right = TOP_COLLAPSED_HALF_WIDTH
		_top_panel.offset_bottom = _top_panel.offset_top + TOP_COLLAPSED_HEIGHT
		_top_toggle.text = "Show HUD"
		_top_toggle.tooltip_text = "Expand the top panel"
	else:
		_top_panel.offset_left = _top_expanded[0]
		_top_panel.offset_top = _top_expanded[1]
		_top_panel.offset_right = _top_expanded[2]
		_top_panel.offset_bottom = _top_expanded[3]
		_top_toggle.text = "Hide HUD"
		_top_toggle.tooltip_text = "Collapse the top panel"

func _apply_net() -> void:
	_net_title.visible = not _net_collapsed
	_net_canvas.visible = not _net_collapsed
	_net_footer.visible = not _net_collapsed

	if _net_collapsed:
		_net_panel.offset_left = -NET_COLLAPSED_WIDTH - NET_RIGHT_MARGIN
		_net_panel.offset_top = -NET_COLLAPSED_HEIGHT - NET_BOTTOM_MARGIN
		_net_panel.offset_right = -NET_RIGHT_MARGIN
		_net_panel.offset_bottom = -NET_BOTTOM_MARGIN
		_net_toggle.text = "Show Survey"
		_net_toggle.tooltip_text = "Expand the claim survey"
	else:
		_net_panel.offset_left = _net_expanded[0]
		_net_panel.offset_top = _net_expanded[1]
		_net_panel.offset_right = _net_expanded[2]
		_net_panel.offset_bottom = _net_expanded[3]
		_net_toggle.text = "Hide Survey"
		_net_toggle.tooltip_text = "Collapse the claim survey"
