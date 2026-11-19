extends RefCounted
## A one-shot awaitable result: `var r = await pending.done`.

signal done(value)

var finished := false
var value = null


func resolve(v = null) -> void:
	if finished:
		return
	finished = true
	value = v
	done.emit(v)
