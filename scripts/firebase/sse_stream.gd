extends Node
## Server-Sent Events reader for the Firebase RTDB REST streaming API.
## Emits event(kind, {"path":..., "data":...}) for put/patch events and
## reconnects automatically (follows 307 redirects, refreshes auth on revoke).

signal event(kind: String, data: Dictionary)
signal connected

var url_provider: Callable   # async () -> String full URL
var _client := HTTPClient.new()
var _running := false
var _state := "idle"         # idle, connecting, requesting, streaming, waiting
var _host := ""
var _path := ""
var _buffer := PackedByteArray()
var _retry_at := 0
var _backoff := 1000
var _redirect := ""


func start() -> void:
	_running = true
	_connect()


func stop() -> void:
	_running = false
	_client.close()
	_state = "idle"


func _connect() -> void:
	if not _running:
		return
	var url: String = _redirect
	if url == "":
		url = await url_provider.call()
	_redirect = ""
	var no_scheme := url.trim_prefix("https://")
	var slash := no_scheme.find("/")
	_host = no_scheme.substr(0, slash)
	_path = no_scheme.substr(slash)
	_client.close()
	_buffer = PackedByteArray()
	var err := _client.connect_to_host(_host, 443, TLSOptions.client())
	if err != OK:
		_schedule_retry()
		return
	_state = "connecting"


func _schedule_retry() -> void:
	_state = "waiting"
	_retry_at = Time.get_ticks_msec() + _backoff
	_backoff = mini(_backoff * 2, 15000)


func _process(_dt: float) -> void:
	if not _running:
		return
	if _state == "waiting":
		if Time.get_ticks_msec() >= _retry_at:
			_connect()
		return
	if _state == "idle":
		return
	_client.poll()
	var st := _client.get_status()
	match _state:
		"connecting":
			if st == HTTPClient.STATUS_CONNECTED:
				_client.request(HTTPClient.METHOD_GET, _path, PackedStringArray([
					"Accept: text/event-stream", "Cache-Control: no-cache"]))
				_state = "requesting"
			elif st in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE,
					HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,
					HTTPClient.STATUS_DISCONNECTED]:
				_schedule_retry()
		"requesting":
			if st == HTTPClient.STATUS_BODY or (st == HTTPClient.STATUS_CONNECTED and _client.has_response()):
				var code := _client.get_response_code()
				if code == 307 or code == 302:
					var hdrs := _client.get_response_headers_as_dictionary()
					for k in hdrs:
						if str(k).to_lower() == "location":
							_redirect = hdrs[k]
					_client.close()
					_connect()
					return
				if code != 200:
					push_warning("SSE stream HTTP %d" % code)
					_client.close()
					_schedule_retry()
					return
				_state = "streaming"
				_backoff = 1000
				connected.emit()
			elif st in [HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_DISCONNECTED]:
				_schedule_retry()
		"streaming":
			if st != HTTPClient.STATUS_BODY:
				_schedule_retry()
				return
			for i in 32:
				var chunk := _client.read_response_body_chunk()
				if chunk.is_empty():
					break
				_buffer.append_array(chunk)
			_drain()


## Split complete events (terminated by a blank line) out of the byte buffer.
func _drain() -> void:
	while true:
		var idx := -1
		for i in range(0, _buffer.size() - 1):
			if _buffer[i] == 10 and _buffer[i + 1] == 10:
				idx = i
				break
		if idx < 0:
			return
		var block := _buffer.slice(0, idx).get_string_from_utf8()
		_buffer = _buffer.slice(idx + 2)
		var kind := ""
		var data := ""
		for line in block.split("\n"):
			if line.begins_with("event:"):
				kind = line.substr(6).strip_edges()
			elif line.begins_with("data:"):
				data += line.substr(5).strip_edges()
		match kind:
			"put", "patch":
				var d = JSON.parse_string(data)
				if typeof(d) == TYPE_DICTIONARY:
					event.emit(kind, d)
			"cancel", "auth_revoked":
				_client.close()
				_schedule_retry()
				return
