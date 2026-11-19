extends Node
## Runs on the host device only: closes lots when the clock runs out,
## opens the next lot, and makes AI franchises bid. If the host leaves,
## another player's auctioneer takes over (see RtdbStore.try_take_over_host).

const HUMANS_DONE_WINDOW := 1500   # ms the lot stays open once only AI is bidding

var store: Node
var rng := RandomNumberGenerator.new()
var _busy := false
var _next_ai_at := 0
var _lot_key := ""
var _takeover_check := 0


func _ready() -> void:
	rng.randomize()


func _process(_dt: float) -> void:
	if store == null or _busy:
		return
	if not store.is_host():
		if store.is_online() and store.status() == "auction" and Time.get_ticks_msec() > _takeover_check:
			_takeover_check = Time.get_ticks_msec() + 2000
			store.try_take_over_host()
		return
	match store.status():
		"auction":
			_tick()
		"review":
			_check_review()


## Move to results once every human player has confirmed their XI.
func _check_review() -> void:
	var players: Dictionary = store.state.get("players", {})
	var now: int = store.now_ms()
	for uid in players:
		var gone: bool = store.is_online() and now - int(players[uid].get("seen", 0)) > 20000
		if not players[uid].get("ready", false) and not gone:
			return
	await _run({"meta/status": "results"})


func _tick() -> void:
	var state: Dictionary = store.state
	var a: Dictionary = state.get("auction", {})
	var now: int = store.now_ms()
	var phase: String = a.get("phase", "")
	if phase == "sold" or phase == "unsold":
		if now >= int(a.get("ends", 0)):
			await _run(Auction.advance_updates(state, now))
		return
	if phase != "bidding":
		return
	var key := "%s|%d|%s" % [a.get("pid", ""), int(a.get("round", 1)), str(a.get("idx", 0))]
	if key != _lot_key:
		_lot_key = key
		# Give humans a moment to look at the player before AI jumps in.
		_next_ai_at = now + rng.randi_range(1200, 2200)
	var done := Auction.humans_done(state, now)
	var ends := int(a.get("ends", 0))
	if now >= ends:
		await _run(Auction.settle_updates(state, now))
		return
	if done and ends - now > HUMANS_DONE_WINDOW + 200:
		await _run({"auction/ends": now + HUMANS_DONE_WINDOW})
		return
	if now < _next_ai_at:
		return
	var c := AI.choose_bidder(state, rng)
	if c.is_empty():
		if done:
			await _run(Auction.settle_updates(state, now))
		else:
			_next_ai_at = now + 500
		return
	_busy = true
	await store.place_bid(c["team"], c["amount"])
	_busy = false
	# AI-vs-AI bidding wars move quickly; humans can jump in at any moment.
	_next_ai_at = store.now_ms() + rng.randi_range(300, 700)


func _run(updates: Dictionary) -> void:
	_busy = true
	await store.write(updates)
	_busy = false
