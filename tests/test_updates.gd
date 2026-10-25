extends TestCase
## The update check: version numbers compare part by part, and test runs
## never go online.


func test_versions_compare_part_by_part() -> void:
	check(UpdateCheck.is_newer("0.6.1", "0.6.0"), "0.6.1 is newer than 0.6.0")
	check(UpdateCheck.is_newer("0.6.1.1", "0.6.1"), "a build on the same line is newer")
	check(UpdateCheck.is_newer("0.7.0", "0.6.1.12"), "a new line beats any build of the last")
	check(UpdateCheck.is_newer("0.10.0", "0.9.9"), "numbers, not letters (10 > 9)")
	check(not UpdateCheck.is_newer("0.6.1", "0.6.1"), "the same version isn't newer")
	check(not UpdateCheck.is_newer("0.6.0", "0.6.1"), "an older one isn't")
	check(not UpdateCheck.is_newer("", "0.6.1"), "no answer isn't")


func test_test_runs_never_go_online() -> void:
	var u := UpdateCheck.new()
	add_child(u)
	var was := UpdateCheck.checked
	u.start()
	check(u.get_child_count() == 0, "no request made in a test run")
	UpdateCheck.checked = was
	u.queue_free()
