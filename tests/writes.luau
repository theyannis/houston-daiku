-- Read-write exports, unchanged arguments and results, and a server without session ids.
return {
	scenario = {publisher = {client_id = "fixture-client"}, config = {access = "read-write"}, auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			local message = json.decode(req.body)
			if message.method == "initialize" then
				-- A stateless server: no session id, and an older protocol version.
				return fixture.operation({statusCode = 200, headers = {["content-type"] = {"application/json; charset=utf-8"}},
					body = fixture.reader('{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{}}}')})
			elseif message.method == "notifications/initialized" then
				return fixture.operation({statusCode = 202, headers = {}, body = fixture.reader("")})
			elseif message.method == "tools/list" then
				return fixture.operation({statusCode = 200, headers = {["content-type"] = {"application/json"}},
					body = fixture.reader('{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"unknown_tool"}]}}')})
			end
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {"application/json"}},
				body = fixture.reader('{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"needs_approval: https://daiku.ai/a/1"}],"structuredContent":{"status":"needs_approval"},"isError":true}}')})
		end}
	end,
	run = function(daiku)
		for _, name in {"act", "evaluate", "send_request", "download", "upload", "paste", "fill_secret", "browser", "feedback",
			"workspace", "read", "navigate", "tabs", "files", "network", "recipe", "watch", "trust", "show_browser", "request_human", "listTools", "help"} do
			assert(type(daiku[name]) == "function", "missing " .. name)
		end

		local result = daiku.act({action = "click", ref = "e12", workspace = "w3", description = "Send the invoice", idempotency_key = "k-1"})
		-- Tool errors are ordinary results, returned unchanged.
		assert(result.isError == true and result.structuredContent.status == "needs_approval")
		assert(result.content[1].text == "needs_approval: https://daiku.ai/a/1")
		assert(#requests == 3, "a stateless session sends no DELETE")
		for _, req in requests do
			assert(req.headers["Mcp-Session-Id"] == nil and req.headers.Authorization == nil)
		end
		assert(requests[3].headers["MCP-Protocol-Version"][1] == "2025-03-26")
		local call = json.decode(requests[3].body)
		assert(call.params.name == "act")
		local sent = call.params.arguments
		local count = 0
		for _ in sent do count += 1 end
		assert(count == 5 and sent.action == "click" and sent.ref == "e12" and sent.workspace == "w3"
			and sent.description == "Send the invoice" and sent.idempotency_key == "k-1", "arguments changed")

		-- Actions a read-only connection refuses pass through here.
		daiku.trust({action = "ask_first", site = "bahn.de", kind = "pay"})
		assert(json.decode(requests[6].body).params.arguments.action == "ask_first")
		daiku.send_request({url = "/api/comment", method = "POST", json = {text = "Hi"}, workspace = "w3"})
		assert(json.decode(requests[9].body).params.arguments.json.text == "Hi")

		-- An empty arguments object stays an object, and tools Daiku lists but the connector lacks are dropped.
		daiku.browser()
		assert(string.find(requests[12].body, '"arguments":{}', 1, true))
		local listed = daiku.listTools()
		assert(#listed.tools == 0 and listed.instructions == nil)
		assert(string.find(json.encode(listed), '"tools":[]', 1, true))
		assert(#requests == 15)
	end,
}
