extends PanelContainer

const WINDOWS_ONLY_HINT := "仅 PC Windows 端支持本地题库设置"

@onready var title_button: Button = $ContentVBox/HeaderRow/TitleButton
@onready var collapse_button: Button = $ContentVBox/HeaderRow/CollapseButton
@onready var settings_body: VBoxContainer = $ContentVBox/SettingsBody
@onready var enabled_check: CheckBox = $ContentVBox/SettingsBody/EnabledCheck
@onready var frequency_spin: SpinBox = $ContentVBox/SettingsBody/FrequencyContainer/FrequencySpin
@onready var speed_spin: SpinBox = $ContentVBox/SettingsBody/SpeedContainer/SpeedSpin
@onready var penalty_spin: SpinBox = $ContentVBox/SettingsBody/PenaltyContainer/PenaltySpin
@onready var bank_settings_button: Button = $ContentVBox/SettingsBody/BankSettingsButton
@onready var bank_dialog: AcceptDialog = $BankDialog
@onready var path_label_math: Label = $BankDialog/Content/MathPathValue
@onready var path_label_qa: Label = $BankDialog/Content/QAPathValue
@onready var status_label: Label = $BankDialog/Content/StatusLabel
@onready var open_folder_button: Button = $BankDialog/Content/Actions/OpenFolderButton
@onready var reload_button: Button = $BankDialog/Content/Actions/ReloadButton
@onready var import_math_button: Button = $BankDialog/Content/ImportButtons/ImportMathButton
@onready var import_qa_button: Button = $BankDialog/Content/ImportButtons/ImportQAButton
@onready var file_dialog: FileDialog = $FileDialog

var _pending_import_type: QuizData.QuestionType = QuizData.QuestionType.MATH
var _is_collapsed := false
var _expanded_bottom := 354.0
var _collapsed_bottom := 112.0

func _ready() -> void:
	_setup_ui()
	_load_values()
	_refresh_question_bank_info()

func _setup_ui() -> void:
	enabled_check.text = "启用答题模式"
	enabled_check.toggled.connect(_on_setting_changed)

	frequency_spin.min_value = 1
	frequency_spin.max_value = 99
	frequency_spin.value = 3
	frequency_spin.value_changed.connect(_on_setting_changed)

	speed_spin.min_value = 0.1
	speed_spin.max_value = 0.5
	speed_spin.step = 0.05
	speed_spin.value = 0.25
	speed_spin.value_changed.connect(_on_setting_changed)

	penalty_spin.min_value = 0
	penalty_spin.max_value = 999
	penalty_spin.value = 50
	penalty_spin.value_changed.connect(_on_setting_changed)

	title_button.text = "答题学习设置"
	title_button.flat = true
	title_button.pressed.connect(_on_title_button_pressed)
	collapse_button.pressed.connect(_on_collapse_button_pressed)

	bank_settings_button.text = "题库设置"
	bank_settings_button.pressed.connect(_on_bank_settings_button_pressed)

	bank_dialog.title = "题库设置"
	bank_dialog.dialog_hide_on_ok = true
	bank_dialog.ok_button_text = "关闭"

	open_folder_button.pressed.connect(_on_open_folder_button_pressed)
	reload_button.pressed.connect(_on_reload_button_pressed)
	import_math_button.pressed.connect(_on_import_math_button_pressed)
	import_qa_button.pressed.connect(_on_import_qa_button_pressed)
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.txt ; 文本题库", "*.csv ; CSV 题库"])
	file_dialog.file_selected.connect(_on_file_selected)

func _load_values() -> void:
	enabled_check.button_pressed = QuizManager.is_enabled
	frequency_spin.value = QuizManager.trigger_frequency
	speed_spin.value = QuizManager.quiz_speed
	penalty_spin.value = QuizManager.wrong_penalty
	_apply_collapsed_state(false)

func _on_setting_changed(_value = null) -> void:
	QuizManager.is_enabled = enabled_check.button_pressed
	QuizManager.trigger_frequency = int(frequency_spin.value)
	QuizManager.quiz_speed = speed_spin.value
	QuizManager.wrong_penalty = int(penalty_spin.value)
	QuizManager.save_settings()

func _refresh_question_bank_info(message: String = "") -> void:
	var paths := QuizManager.get_question_bank_display_paths()
	path_label_math.text = str(paths.get("math", ""))
	path_label_qa.text = str(paths.get("qa", ""))
	status_label.text = message if not message.is_empty() else WINDOWS_ONLY_HINT

func _apply_collapsed_state(collapsed: bool) -> void:
	_is_collapsed = collapsed
	settings_body.visible = not collapsed
	collapse_button.text = "展开" if collapsed else "收起"
	title_button.text = "设置" if collapsed else "答题学习设置"
	offset_bottom = _collapsed_bottom if collapsed else _expanded_bottom

func _on_title_button_pressed() -> void:
	if _is_collapsed:
		_apply_collapsed_state(false)

func _on_collapse_button_pressed() -> void:
	_apply_collapsed_state(not _is_collapsed)

func _on_bank_settings_button_pressed() -> void:
	_refresh_question_bank_info()
	bank_dialog.popup_centered_ratio(0.5)

func _on_open_folder_button_pressed() -> void:
	var folder_path := str(QuizManager.get_question_bank_display_paths().get("folder", ""))
	if folder_path.is_empty():
		_refresh_question_bank_info("题库目录不可用")
		return

	if not DirAccess.dir_exists_absolute(folder_path):
		var mk_err := DirAccess.make_dir_recursive_absolute(folder_path)
		if mk_err != OK:
			_refresh_question_bank_info("创建题库目录失败，错误码：%d" % mk_err)
			return

	var folder_url := "file:///" + folder_path.replace("\\", "/")
	OS.shell_open(folder_url)
	_refresh_question_bank_info("已尝试打开题库目录")

func _on_reload_button_pressed() -> void:
	QuizManager.reload_questions()
	_refresh_question_bank_info("题库已重新加载")

func _on_import_math_button_pressed() -> void:
	_pending_import_type = QuizData.QuestionType.MATH
	file_dialog.title = "选择数学题库文件"
	file_dialog.popup_centered_ratio(0.7)

func _on_import_qa_button_pressed() -> void:
	_pending_import_type = QuizData.QuestionType.QA
	file_dialog.title = "选择问答题库文件"
	file_dialog.popup_centered_ratio(0.7)

func _on_file_selected(path: String) -> void:
	var error_message := QuizManager.import_question_bank(path, _pending_import_type)
	if error_message.is_empty():
		var success_text := "数学题库已更新并重新加载" if _pending_import_type == QuizData.QuestionType.MATH else "问答题库已更新并重新加载"
		_refresh_question_bank_info(success_text)
	else:
		_refresh_question_bank_info(error_message)
