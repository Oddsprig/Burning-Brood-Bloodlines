extends RefCounted
## Scoped argument view for the run-plan driver; ordinary invocations read real OS arguments.
static var active: bool = false
static var selected: PackedStringArray = PackedStringArray()

static func arguments() -> PackedStringArray:
	return selected.duplicate() if active else OS.get_cmdline_user_args()
