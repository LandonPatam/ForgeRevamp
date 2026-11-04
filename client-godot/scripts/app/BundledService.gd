extends RefCounted
## Starts the Java deck/match service that ships beside an exported build:
##   ForgeUI.exe, runtime/ (Java), service/ (bridge classes + libraries), forge-gui/ (Forge rules and assets).
## Development launches (library.ps1) start the service themselves and pass --library-url instead.
## The service watches this process and shuts itself down, releasing any router mapping, when the game closes.

var pid := -1
var status_file := ""
var data_dir := ""
var error := ""

static func root() -> String:
	return OS.get_executable_path().get_base_dir()

static func available() -> bool:
	return OS.has_feature("template") and FileAccess.file_exists(root().path_join("runtime/bin/java.exe"))

func start(port: int) -> bool:
	var base := root()
	data_dir = ProjectSettings.globalize_path("user://service")
	DirAccess.make_dir_recursive_absolute(data_dir)
	status_file = data_dir.path_join("startup.json")
	if FileAccess.file_exists(status_file): DirAccess.remove_absolute(status_file)
	var classpath := base.path_join("service/classes") + ";" + base.path_join("service/lib/*")
	pid = OS.create_process(base.path_join("runtime/bin/java.exe"), [
		"-Xmx4g", "-cp", classpath, "forgeui.bridge.LibraryMain",
		"--assets", base.path_join("forge-gui"), "--port", str(port),
		"--startup-status", status_file, "--data-dir", data_dir, "--parent-pid", str(OS.get_process_id())])
	if pid <= 0:
		error = "The Forge service could not be started. Reinstall the game, or check that antivirus has not blocked runtime\\bin\\java.exe."
		return false
	return true

func running() -> bool:
	return pid > 0 and OS.is_process_running(pid)

func log_path() -> String:
	return data_dir.path_join("service.log")
