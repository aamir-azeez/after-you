extends SceneTree
const Api = preload("res://services/rooms_api.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0

class Echo:
	extends Node
	var server := TCPServer.new()
	var peers: Array = []
	var requests: Array = []
	var port := 0
	func start() -> bool:
		for candidate in range(24173,24189):
			if server.listen(candidate,"127.0.0.1") == OK:
				port = candidate
				return true
		return false
	func _process(_delta: float) -> void:
		while server.is_connection_available():
			peers.append({"stream":server.take_connection(),"bytes":PackedByteArray()})
		for i in range(peers.size()-1,-1,-1):
			var peer: Dictionary = peers[i]
			peer.stream.poll()
			var size: int = peer.stream.get_available_bytes()
			if size > 0:
				var received: Array = peer.stream.get_data(size)
				if received[0] == OK: peer.bytes.append_array(received[1])
			var raw: String = peer.bytes.get_string_from_utf8()
			var split := raw.find("\r\n\r\n")
			if split < 0: continue
			var lines := raw.substr(0,split).split("\r\n")
			var headers := {}
			for line in lines.slice(1):
				var colon: int = line.find(":")
				if colon > 0: headers[line.substr(0,colon).to_lower()] = line.substr(colon+1).strip_edges()
			var length := int(headers.get("content-length","0"))
			if peer.bytes.size() < split+4+length: continue
			var body := raw.substr(split+4,length)
			var entry := {"request":lines[0],"headers":headers,"body":body}
			requests.append(entry)
			var encoded := JSON.stringify(entry).to_utf8_buffer()
			peer.stream.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % encoded.size()).to_utf8_buffer())
			peer.stream.put_data(encoded)
			peers.remove_at(i)
	func stop() -> void:
		for peer: Dictionary in peers: peer.stream.disconnect_from_host()
		peers.clear()
		server.stop()

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var echo := Echo.new()
	root.add_child(echo)
	if not echo.start():
		_check(false,"A local-only HTTP fixture can bind a test port")
		_finish()
		return
	var api := Api.new()
	root.add_child(api)
	api.base_url = "http://127.0.0.1:"+str(echo.port)
	api.player_id = "H".repeat(22)
	api.device_token = "synthetic-header-test-only"
	var body := {"schema_version":1,"idempotency_key":"same-saved-key","retain":"exact body"}
	var ordinary: Dictionary = await api.request_json(HTTPClient.METHOD_POST,"/v2/rooms",body)
	_check(ordinary.ok and ordinary.status == 200,"Ordinary request still completes through the bounded HTTP client")
	_check(not ordinary.data.headers.has("x-afteryou-campaign-schema"),"Ordinary requests do not advertise campaign support")
	var campaign: Dictionary = await api.request_campaign_json(HTTPClient.METHOD_POST,"/v2/campaigns",body)
	_check(campaign.ok and campaign.data.headers.get("x-afteryou-campaign-schema") == "2","Only the explicit campaign call sends protocol2 negotiation")
	_check(campaign.data.headers.get("authorization") == "Bearer synthetic-header-test-only" and campaign.data.headers.get("x-player-id") == "H".repeat(22),"Protocol negotiation preserves existing authenticated headers")
	_check(campaign.data.body == ordinary.data.body and Canonical.same(JSON.parse_string(campaign.data.body),body),"The request body and saved key are unchanged by negotiation")
	var after: Dictionary = await api.request_json(HTTPClient.METHOD_GET,"/v2/rooms")
	_check(after.ok and not after.data.headers.has("x-afteryou-campaign-schema") and after.data.body.is_empty(),"A later ordinary GET does not inherit the previous campaign header or body")
	_check(echo.requests.size() == 3 and not api.busy,"Each deliberate call dispatches exactly once and releases the existing busy guard")
	api.device_token = ""
	var anonymous: Dictionary = await api.request_campaign_json(HTTPClient.METHOD_GET,"/v2/capabilities")
	_check(anonymous.ok and not anonymous.data.headers.has("authorization") and not anonymous.data.headers.has("x-player-id"),"Negotiation never manufactures authentication credentials")
	await process_frame
	echo.stop()
	api.free()
	echo.free()
	_finish()

func _finish() -> void:
	print("Campaign HTTP negotiation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
