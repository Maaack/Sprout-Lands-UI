@tool
extends EditorPlugin

const PLUGIN_NAME = "Sprout Lands UI"
const PROJECT_SETTINGS_PATH = "sprout_lands_ui/"

const CONTENT_RELATIVE_PATH = "content/"
const UID_PREG_MATCH = r'uid="uid:\/\/[0-9a-z]+" '
const CUSTOM_THEME_SCENE_UPDATE_TEXT = "Current:\n%s\n\nNew:\n%s\n"
const THEME_FILE_RELATIVE_PATH = "sprout_lands_theme.tres"
const RESAVING_DELAY : float = 0.5
const REIMPORT_FILE_DELAY : float = 0.2
const OPEN_EDITOR_DELAY : float = 0.1
const CUSTOM_THEME_PROJECT_SETTING : String = "gui/theme/custom"

func _get_plugin_name():
	return PLUGIN_NAME

func get_plugin_path() -> String:
	return get_script().resource_path.get_base_dir() + "/"

func get_plugin_content_path() -> String:
	return get_plugin_path() + CONTENT_RELATIVE_PATH

func _replace_file_contents(file_path : String, target_path : String):
	var extension : String = file_path.get_extension()
	if extension == "import":
		# skip import files
		return OK
	var file = FileAccess.open(file_path, FileAccess.READ)
	var regex = RegEx.new()
	regex.compile(UID_PREG_MATCH)
	if file == null:
		push_error("plugin error - null file: `%s`" % file_path)
		return
	var original_content = file.get_as_text()
	var replaced_content = regex.sub(original_content, "", true)
	replaced_content = replaced_content.replace(get_plugin_content_path(), target_path)
	file.close()
	if replaced_content == original_content: return
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(replaced_content)
	file.close()

func _save_resource(resource_path : String, resource_destination : String, whitelisted_extensions : PackedStringArray = []) -> Error:
	var extension : String = resource_path.get_extension()
	if whitelisted_extensions.size() > 0:
		if not extension in whitelisted_extensions:
			return OK
	if extension == "import":
		# skip import files
		return OK
	var file_object = load(resource_path)
	if file_object is Resource:
		var possible_extensions = ResourceSaver.get_recognized_extensions(file_object)
		if possible_extensions.has(extension):
			return ResourceSaver.save(file_object, resource_destination, ResourceSaver.FLAG_CHANGE_PATH)
		else:
			return ERR_FILE_UNRECOGNIZED
	else:
		return ERR_FILE_UNRECOGNIZED
	return OK

func _delayed_reimporting_file(file_path : String):
	var timer: Timer = Timer.new()
	var callable := func():
		timer.stop()
		var file_system = EditorInterface.get_resource_filesystem()
		file_system.reimport_files([file_path])
		timer.queue_free()
	timer.timeout.connect(callable)
	add_child(timer)
	timer.start(REIMPORT_FILE_DELAY)

func _raw_copy_file_path(file_path : String, destination_path : String) -> Error:
	var dir := DirAccess.open("res://")
	var error := dir.copy(file_path, destination_path)
	if not error:
		EditorInterface.get_resource_filesystem().update_file(destination_path)
	return error

func _copy_file_path(file_path : String, destination_path : String, target_path : String, raw_copy_file_extensions : PackedStringArray = []) -> Error:
	if file_path.get_extension() in raw_copy_file_extensions:
		# Markdown file format
		return _raw_copy_file_path(file_path, destination_path)
	var error = _save_resource(file_path, destination_path)
	if error == ERR_FILE_UNRECOGNIZED:
		# Copy image files and other assets
		error = _raw_copy_file_path(file_path, destination_path)
		# Reimport image files to create new .import
		if not error:
			_delayed_reimporting_file(destination_path)
		return error
	if not error:
		_replace_file_contents(destination_path, target_path)
	return error

func _copy_directory_path(dir_path : String, target_path : String, raw_copy_file_extensions : PackedStringArray = []):
	if not dir_path.ends_with("/"):
		dir_path += "/"
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var error : Error
		while file_name != "" and error == 0:
			var relative_path = dir_path.trim_prefix(get_plugin_content_path())
			var destination_path = target_path + relative_path + file_name
			var full_file_path = dir_path + file_name
			if dir.current_is_dir():
				if not dir.dir_exists(destination_path):
					error = dir.make_dir(destination_path)
				_copy_directory_path(full_file_path, target_path, raw_copy_file_extensions)
			else:
				error = _copy_file_path(full_file_path, destination_path, target_path, raw_copy_file_extensions)
			file_name = dir.get_next()
		if error:
			push_error("plugin error - copying path: %s" % error)
	else:
		push_error("plugin error - accessing path: %s" % dir_path)

func _delayed_saving_and_check_custom_theme(target_path : String):
	var timer: Timer = Timer.new()
	var callable := func():
		timer.stop()
		EditorInterface.get_resource_filesystem().scan()
		EditorInterface.save_all_scenes()
		_check_custom_theme_needs_updating(target_path)
		timer.queue_free()
	timer.timeout.connect(callable)
	add_child(timer)
	timer.start(RESAVING_DELAY)

func _copy_to_directory(target_path : String):
	ProjectSettings.set_setting(PROJECT_SETTINGS_PATH + "copy_path", target_path)
	ProjectSettings.save()
	if not target_path.ends_with("/"):
		target_path += "/"
	_copy_directory_path(get_plugin_content_path(), target_path, ["md"])
	_delayed_saving_and_check_custom_theme(target_path)

func _update_custom_theme(custom_theme_path : String):
	ProjectSettings.set_setting(CUSTOM_THEME_PROJECT_SETTING, custom_theme_path)
	ProjectSettings.save()
	EditorInterface.restart_editor()

func _check_custom_theme_needs_updating(target_path : String):
	var current_custom_theme_path = ProjectSettings.get_setting(CUSTOM_THEME_PROJECT_SETTING, "")
	var new_custom_theme_path = target_path + THEME_FILE_RELATIVE_PATH
	if new_custom_theme_path == current_custom_theme_path:
		return
	_open_custom_theme_confirmation_dialog(current_custom_theme_path, new_custom_theme_path)

func _open_path_dialog():
	var destination_scene : PackedScene = load(get_plugin_path() + "installer/destination_dialog.tscn")
	var destination_instance : FileDialog = destination_scene.instantiate()
	destination_instance.dir_selected.connect(_copy_to_directory)
	add_child(destination_instance)

func _open_confirmation_dialog():
	var confirmation_scene : PackedScene = load(get_plugin_path() + "installer/copy_confirmation_dialog.tscn")
	var confirmation_instance : ConfirmationDialog = confirmation_scene.instantiate()
	confirmation_instance.confirmed.connect(_open_path_dialog)
	add_child(confirmation_instance)

func _open_custom_theme_confirmation_dialog(current_custom_theme : String, new_custom_theme : String):
	var custom_theme_confirmation_scene : PackedScene = load(get_plugin_path() + "installer/custom_theme_confirmation_dialog.tscn")
	var custom_theme_confirmation_instance : ConfirmationDialog = custom_theme_confirmation_scene.instantiate()
	custom_theme_confirmation_instance.dialog_text += CUSTOM_THEME_SCENE_UPDATE_TEXT % [current_custom_theme, new_custom_theme]
	custom_theme_confirmation_instance.confirmed.connect(_update_custom_theme.bind(new_custom_theme))
	add_child(custom_theme_confirmation_instance)

func _show_plugin_dialogues():
	if ProjectSettings.has_setting(PROJECT_SETTINGS_PATH + "disable_plugin_dialogues") :
		if ProjectSettings.get_setting(PROJECT_SETTINGS_PATH + "disable_plugin_dialogues") :
			return
	_open_confirmation_dialog()
	ProjectSettings.set_setting(PROJECT_SETTINGS_PATH + "disable_plugin_dialogues", true)
	ProjectSettings.save()

func _enter_tree():
	add_tool_menu_item("Copy " + _get_plugin_name() + " Contents...", _open_path_dialog)
	_show_plugin_dialogues()

func _exit_tree():
	remove_tool_menu_item("Copy " + _get_plugin_name() + " Contents...",)
