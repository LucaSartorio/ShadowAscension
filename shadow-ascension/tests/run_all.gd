extends SceneTree

## Runs every suite under tests/ and reports, for each: passes, failures, runtime
## errors and exit-time leaks. The last two are what a PASS/FAIL count cannot
## see — M10.4 shipped a helper that leaked GDScript instances on every run
## through the dungeon while every assertion still passed.
##
##   godot --headless --path . --script res://tests/run_all.gd
##
## Each suite runs in its own Godot process, exactly as it would by hand, so no
## suite's state reaches the next. Scene suites are `*_test.tscn` / `*_suite.tscn`,
## flow scripts are `*_run.gd`. Exits with 1 when anything failed, errored or
## leaked, so it can gate a commit.
##
## It takes about twenty minutes: the whole-game runs play the dungeon for real.

const ROOT: String = "res://tests"
const PASS_MARK: String = "[PASS]"
const FAIL_MARK: String = "[FAIL]"
## Lines in a suite's output that mean something went wrong outside its
## assertions. Matched at the start of the line ("ERROR:") or anywhere.
const ERROR_PREFIXES: Array[String] = ["ERROR:", "SCRIPT ERROR:"]
const ERROR_FRAGMENTS: Array[String] = ["Parse Error", "leaked at exit", "still in use at exit"]


func _initialize() -> void:
	var suites: Array[String] = []
	_collect(ROOT, suites)
	suites.sort()
	var project: String = ProjectSettings.globalize_path("res://")
	var total_pass: int = 0
	var total_fail: int = 0
	var total_errors: int = 0
	var broken: Array[String] = []
	print("Running %d suites.\n" % suites.size())
	for suite in suites:
		var args: PackedStringArray = ["--headless", "--path", project]
		if suite.ends_with(".gd"):
			args.append_array(["--script", suite])
		else:
			args.append(suite)
		var output: Array = []
		OS.execute(OS.get_executable_path(), args, output, true)
		var lines: PackedStringArray = "\n".join(output).split("\n")
		var passes: int = 0
		var fails: Array[String] = []
		var errors: Array[String] = []
		for line in lines:
			if line.begins_with(PASS_MARK):
				passes += 1
			elif line.begins_with(FAIL_MARK):
				fails.append(line)
			elif _is_error(line):
				errors.append(line.strip_edges())
		total_pass += passes
		total_fail += fails.size()
		total_errors += errors.size()
		var ran: bool = passes + fails.size() > 0
		print("%-48s pass %4d  fail %2d  errors %2d%s" % [
			suite.trim_prefix(ROOT + "/"), passes, fails.size(), errors.size(),
			"" if ran else "  (reported nothing)"])
		for line in fails:
			print("    " + line)
		for line in errors.slice(0, 6):
			print("    " + line)
		if not fails.is_empty() or not errors.is_empty() or not ran:
			broken.append(suite)
	print("\nTOTAL  suites %d  pass %d  fail %d  errors %d" % [
		suites.size(), total_pass, total_fail, total_errors])
	if broken.is_empty():
		print("All suites clean.")
	else:
		print("Not clean: %s" % ", ".join(broken))
	quit(0 if broken.is_empty() else 1)


func _collect(path: String, into: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(path.path_join(sub), into)
	for file in dir.get_files():
		if file.ends_with("_test.tscn") or file.ends_with("_suite.tscn") or file.ends_with("_run.gd"):
			into.append(path.path_join(file))


func _is_error(line: String) -> bool:
	for prefix in ERROR_PREFIXES:
		if line.begins_with(prefix):
			return true
	for fragment in ERROR_FRAGMENTS:
		if line.contains(fragment):
			return true
	return false
