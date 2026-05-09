extends Node

@onready var overlay_layer: CanvasLayer = $OverlayLayer
@onready var panel_layer: CanvasLayer = $PanelLayer
@onready var overlay: ColorRect = $OverlayLayer/Overlay
@onready var quiz_panel: PanelContainer = $PanelLayer/QuizPanel
@onready var question_label: RichTextLabel = $PanelLayer/QuizPanel/VBoxContainer/QuestionLabel
@onready var math_section: VBoxContainer = $PanelLayer/QuizPanel/VBoxContainer/MathSection
@onready var input_field: LineEdit = $PanelLayer/QuizPanel/VBoxContainer/MathSection/InputField
@onready var submit_button: Button = $PanelLayer/QuizPanel/VBoxContainer/MathSection/SubmitButton
@onready var qa_section: VBoxContainer = $PanelLayer/QuizPanel/VBoxContainer/QASection
@onready var qa_hint_label: Label = $PanelLayer/QuizPanel/VBoxContainer/QASection/QAHintLabel
@onready var correct_button: Button = $PanelLayer/QuizPanel/VBoxContainer/QASection/ButtonRow/CorrectButton
@onready var wrong_button: Button = $PanelLayer/QuizPanel/VBoxContainer/QASection/ButtonRow/WrongButton
@onready var result_label: Label = $PanelLayer/QuizPanel/VBoxContainer/ResultLabel

const PVZ_THEME := preload("res://data/PVZ_theme.tres")
const OVERLAY_SHADER := preload("res://shaders/quiz_overlay.gdshader")

var _current_question: QuizData
var _current_user_answer: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay_layer.layer = 126
	panel_layer.layer = 127
	QuizManager.settings_changed.connect(_on_quiz_settings_changed)
	_setup_ui()
	_hide_all()
	print("QuizUI: _ready完成")

func _setup_ui() -> void:
	# 设置遮罩 shader
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = OVERLAY_SHADER
	overlay.material = shader_mat
	_apply_overlay_settings()

	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 0
	quiz_panel.z_index = 1
	quiz_panel.custom_minimum_size = Vector2(400, 250)
	quiz_panel.theme = PVZ_THEME
	result_label.visible = false
	input_field.placeholder_text = "输入答案"
	input_field.text_submitted.connect(_on_math_submitted)
	submit_button.text = "确认"
	submit_button.pressed.connect(func(): _on_math_submitted(input_field.text))
	qa_hint_label.text = "请家长判断对错"
	correct_button.text = "对"
	wrong_button.text = "错"
	correct_button.pressed.connect(_on_qa_answer.bind(true, "对"))
	wrong_button.pressed.connect(_on_qa_answer.bind(false, "错"))

func _apply_overlay_settings() -> void:
	if overlay.material is ShaderMaterial:
		var mat: ShaderMaterial = overlay.material
		mat.set_shader_parameter("opacity", QuizManager.overlay_opacity)
		mat.set_shader_parameter("blur_amount", QuizManager.overlay_blur)
	overlay.color = Color(0, 0, 0, QuizManager.overlay_opacity)

func _on_quiz_settings_changed() -> void:
	_apply_overlay_settings()

func _hide_all() -> void:
	overlay_layer.visible = false
	panel_layer.visible = false

func _show_all() -> void:
	_apply_overlay_settings()
	overlay_layer.visible = true
	panel_layer.visible = true

func show_quiz(question: QuizData) -> void:
	print("QuizUI: show_quiz被调用, 题目:", question.question)
	_current_question = question
	_current_user_answer = ""
	_show_all()
	result_label.visible = false
	math_section.visible = false
	qa_section.visible = false
	# 题目文字：加大字号 + 加粗 + 醒目颜色
	question_label.text = "[b][font_size=28][color=#FFD700]%s[/color][/font_size][/b]" % question.question
	match question.question_type:
		QuizData.QuestionType.MATH:
			math_section.visible = true
			input_field.text = ""
			input_field.grab_focus()
		QuizData.QuestionType.QA:
			qa_section.visible = true

func _on_math_submitted(_text: String = "") -> void:
	if _current_question == null or not math_section.visible:
		return
	var user_answer := input_field.text
	_current_user_answer = user_answer
	var is_correct := _answers_match(user_answer, _current_question.answer)
	_show_result(is_correct)

# 答案归一化比较：大小写、全半角、空格、数值
func _answers_match(user_input: String, correct: String) -> bool:
	var a := _normalize_answer(user_input)
	var b := _normalize_answer(correct)
	if a == b:
		return true
	# 数值比较：8 == 8.0, 01 == 1
	if a.is_valid_float() and b.is_valid_float():
		return absf(a.to_float() - b.to_float()) < 0.001
	return false

func _normalize_answer(text: String) -> String:
	var result := text.strip_edges().to_lower()
	var normalized := ""
	for i in range(result.length()):
		var c := result.unicode_at(i)
		# 全角 ASCII → 半角 (０xFF01-0xFF5E → 0x0021-0x007E)
		if c >= 0xFF01 and c <= 0xFF5E:
			normalized += char(c - 0xFEE0)
		# 全角空格 → 半角空格
		elif c == 0x3000:
			normalized += " "
		else:
			normalized += result[i]
	# 去掉所有空格后比较
	return normalized.replace(" ", "")

func _on_qa_answer(is_correct: bool, user_answer: String) -> void:
	_current_user_answer = user_answer
	_show_result(is_correct)

func _show_result(is_correct: bool) -> void:
	math_section.visible = false
	qa_section.visible = false
	result_label.visible = true
	if is_correct:
		result_label.text = "✅ 回答正确!"
		result_label.add_theme_font_size_override("font_size", 36)
		result_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		_play_correct_effect()
		SoundManager.play_other_SFX("points")
	else:
		result_label.text = "❌ 回答错误! 扣除%d阳光" % QuizManager.wrong_penalty
		result_label.add_theme_font_size_override("font_size", 24)
		result_label.add_theme_color_override("font_color", Color.RED)
		QuizManager.end_quiz(false, _current_question, _current_user_answer)
		await get_tree().create_timer(1.5).timeout
		_hide_all()
		_current_question = null
		_current_user_answer = ""
		return
	QuizManager.end_quiz(true, _current_question, _current_user_answer)
	await get_tree().create_timer(1.2).timeout
	_hide_all()
	_current_question = null
	_current_user_answer = ""

# 回答正确特效：缩放弹跳 + 阳光粒子飘散
func _play_correct_effect() -> void:
	# 文字缩放弹跳
	result_label.scale = Vector2(0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(result_label, "scale", Vector2(1.2, 1.2), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(result_label, "scale", Vector2(1.0, 1.0), 0.15)

	# 飘出几个 "+☀" 粒子
	for i in range(5):
		var particle := Label.new()
		particle.text = "☀"
		particle.add_theme_font_size_override("font_size", randi_range(18, 28))
		particle.modulate = Color(1, 0.9, 0.2, 1)
		quiz_panel.add_child(particle)
		var start_pos := result_label.position + Vector2(randf_range(-60, 60), randf_range(-10, 10))
		particle.position = start_pos
		var ptween := create_tween()
		ptween.set_parallel(true)
		ptween.tween_property(particle, "position", start_pos + Vector2(randf_range(-40, 40), randf_range(-80, -40)), randf_range(0.6, 1.0)).set_ease(Tween.EASE_OUT)
		ptween.tween_property(particle, "modulate:a", 0.0, randf_range(0.6, 1.0)).set_delay(0.2)
		ptween.chain().tween_callback(particle.queue_free)
