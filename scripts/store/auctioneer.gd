extends Node
## Runs on the host device only: closes lots when the clock runs out,
## opens the next lot, and makes AI franchises bid. If the host leaves,
## another player's auctioneer takes over (see RtdbStore.try_take_over_host).

const GOING_MS := 3600          # "going once… going twice…" before the hammer falls

var store: Node
var rng := RandomNumberGenerator.new()
var _busy := false
var _next_ai_at := 0
var _lot_key := ""
var _seen_n := -1
var _ai_answered := false
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
	var n := int(a.get("n", 0))
	if key != _lot_key:
		_lot_key = key
		_seen_n = n
		_ai_answered = false
		# The auctioneer introduces the player first; paddles go up after he asks
		# "who'll open the bidding?" (the line starts ~0.4 s after the lot opens).
		var base := int(DB.player(a.get("pid", "")).get("base", 0))
		_next_ai_at = now + 400 + Sfx.line_ms("open_%d" % base) + rng.randi_range(300, 900)
	elif n != _seen_n:
		# A new bid landed: the auctioneer calls it ("…anyone at X?") and only
		# then do the AI rooms raise their paddles. They take a little longer to
		# answer a human than another AI team; hard AI answers faster.
		_seen_n = n
		_ai_answered = false
		var human_led := Auction.human_teams(state).has(a.get("bidder", ""))
		var pace: float = AI.level(state)["pace"]
		var think := int((rng.randi_range(500, 1000) if human_led else rng.randi_range(200, 500)) * pace)
		_next_ai_at = now + Sfx.line_ms("bid_%d" % int(a.get("bid", 0))) + think
	if store.fast_forwarding():
		# Fast-forward: AI wars resolve in one jump, then the hammer falls at once.
		var f := AI.choose_bidder(state, rng, true)
		if f.is_empty():
			await _run(Auction.settle_updates(state, now))
		else:
			_busy = true
			await store.place_bid(f["team"], f["amount"])
			_busy = false
		return
	var ends := int(a.get("ends", 0))
	# Never close a lot before the AI teams have had their chance to answer the last bid.
	if now >= ends and now >= _next_ai_at and _ai_answered:
		await _run(Auction.settle_updates(state, now))
		return
	if now < _next_ai_at:
		return
	# Still mid-sentence (e.g. a queued line after a quick human bid): wait for him.
	if Sfx.talking() and now < ends:
		return
	var humans_in := Auction.humans_in_play(state, now)
	var c := AI.choose_bidder(state, rng, not humans_in)
	if c.is_empty():
		_ai_answered = true
		# No AI wants him at this price. If every human is out or already leading,
		# start the "going once, going twice" call; otherwise wait for the humans.
		if Auction.humans_done(state, now) and ends - now > GOING_MS:
			await _run({"auction/ends": now + GOING_MS})
		elif now >= ends:
			await _run(Auction.settle_updates(state, now))
		else:
			_next_ai_at = now + 400
		return
	_busy = true
	await store.place_bid(c["team"], c["amount"])
	_busy = false
	_next_ai_at = store.now_ms() + 300


func _run(updates: Dictionary) -> void:
	_busy = true
	await store.write(updates)
	_busy = false
