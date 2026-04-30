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

const PVZ_THEME := preload("res://data/PVZ_theme.tres")

var _current_question: QuizData

func _ready() -> void:
	layer = 100
	QuizManager.quiz_triggered.connect(_on_quiz_triggered)
	_setup_ui()
	_hide_all()
	print("QuizUI: _ready完成, 已连接信号")

func _setup_ui() -> void:
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
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
	var user_answer := input_field.text
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
