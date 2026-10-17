class_name UiCompat
extends RefCounted
## Guards for helpers owned by other workstreams that may not exist in this tree yet
## (campaign/economy.gd, campaign/contracts.gd, sim/healing.gd, sim/learning.gd).

static func script(path: String):
	if not ResourceLoader.exists(path):
		return null
	return load(path)

static func has(path: String, method: String) -> bool:
	var s = script(path)
	return s != null and s.has_method(method)

## Number of declared arguments of a script method (-1 if unknown).
static func arg_count(s, method: String) -> int:
	if s == null:
		return -1
	for m in s.get_script_method_list():
		if m["name"] == method:
			return (m["args"] as Array).size()
	return -1

## Calls `method` on the script at `path`, choosing the argument list by the method's arity.
## by_arity = {1: [unit], 2: [unit, town], ...}. Returns `fallback` if missing or no arity matches.
static func call_flex(path: String, method: String, by_arity: Dictionary, fallback = null):
	var s = script(path)
	if s == null or not s.has_method(method):
		return fallback
	var n := arg_count(s, method)
	if by_arity.has(n):
		return s.callv(method, by_arity[n])
	return fallback
