extends HBoxContainer

onready var status_label: Label = $Status
onready var action_button: Button = $Action

func _ready():
	Rhythia.connect("discord_login_changed", self, "_update")
	action_button.connect("pressed", self, "_on_action_pressed")
	_update()

func _update():
	action_button.disabled = false
	if Rhythia.discord_user.has("username") and String(Rhythia.discord_user.username) != "":
		status_label.text = "Linked as %s" % String(Rhythia.discord_user.username)
		action_button.text = "Unlink Discord"
	else:
		status_label.text = "Not linked" if Rhythia.discord_login_error == "" else Rhythia.discord_login_error
		action_button.text = "Connect Discord"

func _on_action_pressed():
	action_button.disabled = true
	if Rhythia.discord_user.has("username") and String(Rhythia.discord_user.username) != "":
		Rhythia.unlink_discord()
	else:
		status_label.text = "Opening your browser…"
		Rhythia.start_discord_login()
