extends VBoxContainer

@onready var enabled_check: CheckBox = $EnabledCheck
@onready var frequency_spin: SpinBox = $FrequencyContainer/FrequencySpin
@onready var speed_spin: SpinBox = $SpeedContainer/SpeedSpin
@onready var penalty_spin: SpinBox = $PenaltyContainer/PenaltySpin

func _ready() -> void:
	_setup_ui()
	_load_values()

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

func _load_values() -> void:
	enabled_check.button_pressed = QuizManager.is_enabled
	frequency_spin.value = QuizManager.trigger_frequency
	speed_spin.value = QuizManager.quiz_speed
	penalty_spin.value = QuizManager.wrong_penalty

func _on_setting_changed(_value = null) -> void:
	QuizManager.is_enabled = enabled_check.button_pressed
	QuizManager.trigger_frequency = int(frequency_spin.value)
	QuizManager.quiz_speed = speed_spin.value
	QuizManager.wrong_penalty = int(penalty_spin.value)
	QuizManager.save_settings()
