extends CanvasLayer

@onready var overlay: ColorRect = $Overlay
@onready var quiz_panel: PanelContainer = $QuizPanel
@onready var question_label: RichTextLabel = $QuizPanel/VBoxContainer/QuestionLabel
@onready var math_section: VBoxContainer = $QuizPanel/VBoxContainer/MathSection
@onready var input_field: LineEdit = $QuizPanel/VBoxContainer/MathSection/InputField
@onready var submit_button: Button = $QuizPanel/VBoxContainer/MathSection/SubmitButton
@onready var qa_section: VBoxContainer = $QuizPanel/VBoxContainer/QASection
@onready var qa_hint_label: Label = $QuizPanel/VBoxContainer/QASection/QAHintLabel
@onready var correct_button: Button = $QuizPanel/VBoxContainer/QASection/ButtonRow/CorrectButton
@onready var wrong_button: Button = $QuizPanel/VBoxContainer/QASection/ButtonRow/WrongButton
@onready var result_label: Label = $QuizPanel/VBoxContainer/ResultLabel

var _current_question: QuizData

func _ready() -> void:
	layer = 100
	QuizManager.quiz_triggered.connect(_on_quiz_triggered)
	_setup_ui()
	_hide_all()
	print("QuizUI: _ready完成, 已连接信号")

func _create_quiz_font_theme() -> Theme:
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray([
		"PingFang SC",
		"Hiragino Sans GB",
		"Noto Sans CJK SC",
		"Noto Sans SC",
		"Source Han Sans SC",
		"Microsoft YaHei",
		"Droid Sans Fallback",
		"Arial Unicode MS",
		"sans-serif"
	])
	system_font.font_weight = 500
	system_font.hinting = TextServer.HINTING_LIGHT
	system_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED

	var theme := Theme.new()
	theme.default_font = system_font
	theme.default_font_size = 24
	return theme

func _setup_ui() -> void:
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	quiz_panel.custom_minimum_size = Vector2(400, 250)
	quiz_panel.theme = _create_quiz_font_theme()
	result_label.visible = false
	input_field.placeholder_text = "输入答案"
	input_field.text_submitted.connect(_on_math_submitted)
	submit_button.text = "确认"
	submit_button.pressed.connect(func(): _on_math_submitted(input_field.text))
	qa_hint_label.text = "请家长判断对错"
	correct_button.text = "对"
	wrong_button.text = "错"
	correct_button.pressed.connect(_on_qa_answer.bind(true))
	wrong_button.pressed.connect(_on_qa_answer.bind(false))

func _hide_all() -> void:
	overlay.visible = false
	quiz_panel.visible = false

func _show_all() -> void:
	overlay.visible = true
	quiz_panel.visible = true

func show_quiz(question: QuizData) -> void:
	print("QuizUI: show_quiz被调用, 题目:", question.question)
	_current_question = question
	_show_all()
	result_label.visible = false
	math_section.visible = false
	qa_section.visible = false
	question_label.text = question.question
	match question.question_type:
		QuizData.QuestionType.MATH:
			math_section.visible = true
			input_field.text = ""
			input_field.grab_focus()
		QuizData.QuestionType.QA:
			qa_section.visible = true

func _on_quiz_triggered(question: QuizData) -> void:
	print("QuizUI: 收到答题信号, 题目:", question.question)
	_current_question = question
	_show_all()
	result_label.visible = false
	math_section.visible = false
	qa_section.visible = false
	question_label.text = question.question
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
	var user_answer := input_field.text.strip_edges()
	var is_correct := (user_answer == _current_question.answer)
	_show_result(is_correct)

func _on_qa_answer(is_correct: bool) -> void:
	_show_result(is_correct)

func _show_result(is_correct: bool) -> void:
	math_section.visible = false
	qa_section.visible = false
	result_label.visible = true
	if is_correct:
		result_label.text = "回答正确!"
		result_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		result_label.text = "回答错误! 扣除%d阳光" % QuizManager.wrong_penalty
		result_label.add_theme_color_override("font_color", Color.RED)
		QuizManager.end_quiz(false, _current_question)
		await get_tree().create_timer(1.5).timeout
		_hide_all()
		_current_question = null
		return
	QuizManager.end_quiz(true, _current_question)
	await get_tree().create_timer(1.0).timeout
	_hide_all()
	_current_question = null
