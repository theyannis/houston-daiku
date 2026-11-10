-- Read-only exports, the MCP session (initialize, initialized, call, DELETE) and stream parsing.
return {
	scenario = {publisher = {client_id = "fixture-client"}, config = {access = "read-only"}, auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		toolPages = {
			'{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"read","description":"Look","inputSchema":{"type":"object"}},{"name":"act","description":"Click","inputSchema":{"type":"object"}}],"nextCursor":"c2"}}',
			'{"jsonrpc":"2.0","id":3,"result":{"tools":[]}}',
		}
		http = {request = function(req)
			table.insert(requests, req)
			if req.method == "DELETE" then
				return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader("")})
			end
			local message = json.decode(req.body)
			if message.method == "initialize" then
				return fixture.operation({statusCode = 200,
					headers = {["content-type"] = {"application/json"}, ["mcp-session-id"] = {"sess-1"}},
					body = fixture.reader('{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"daiku","version":"1"},"instructions":"Open a workspace first."}}')})
			elseif message.method == "notifications/initialized" then
				return fixture.operation({statusCode = 202, headers = {}, body = fixture.reader("")})
			elseif message.method == "tools/list" then
				return fixture.operation({statusCode = 200, headers = {["content-type"] = {"application/json"}},
					body = fixture.reader(table.remove(toolPages, 1))})
			end
			-- tools/call answers as an event stream with a progress notification first.
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {"text/event-stream"}},
				body = fixture.reader('event: message\r\ndata: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\r\n\r\n'
					.. 'event: message\ndata: {"jsonrpc":"2.0","id":2,\ndata: "result":{"content":[{"type":"text","text":"Page: Example"}],"isError":false}}\n\n')})
		end}
	end,
	run = function(daiku)
		local names = {}
		for name, value in daiku do
			assert(type(value) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		local expected = {"files", "listTools", "navigate", "network", "read", "recipe", "request_human", "show_browser", "tabs", "trust", "watch", "workspace"}
		assert(#names == #expected, "exports: " .. table.concat(names, ","))
		for index, name in expected do assert(names[index] == name, "exports: " .. table.concat(names, ",")) end

		local result = daiku.read({action = "snapshot", workspace = "w3", scope = "main", any_text = {"Done", "Failed"}})
		assert(result.content[1].text == "Page: Example" and result.isError == false)
		assert(#requests == 4, "session request count " .. #requests)
		for _, req in requests do
			assert(req.url == "https://daiku.ai/mcp", req.url)
			assert(req.headers.Authorization == nil and req.headers.authorization == nil, "connector set Authorization")
		end
		local init = json.decode(requests[1].body)
		assert(requests[1].method == "POST" and init.jsonrpc == "2.0" and init.id == 1 and init.params.protocolVersion == "2025-06-18")
		assert(requests[1].headers["Mcp-Session-Id"] == nil and requests[1].headers.Accept[1] == "application/json, text/event-stream")
		assert(requests[1].headers["Content-Type"][1] == "application/json")
		assert(json.decode(requests[2].body).method == "notifications/initialized" and json.decode(requests[2].body).id == nil)
		for index = 2, 4 do
			assert(requests[index].headers["Mcp-Session-Id"][1] == "sess-1")
			assert(requests[index].headers["MCP-Protocol-Version"][1] == "2025-06-18")
		end
		local call = json.decode(requests[3].body)
		assert(call.method == "tools/call" and call.id == 2 and call.params.name == "read")
		assert(call.params.arguments.action == "snapshot" and call.params.arguments.workspace == "w3" and call.params.arguments.scope == "main")
		assert(call.params.arguments.any_text[2] == "Failed")
		assert(requests[4].method == "DELETE" and requests[4].body == nil)

		-- Allowed actions pass; others never reach the network.
		daiku.files({action = "list", workspace = "w3"})
		assert(#requests == 8)
		for _, case in {
			function() daiku.files({action = "delete", file = "f1"}) end,
			function() daiku.files() end,
			function() daiku.trust({action = "mode", mode = "yolo"}) end,
			function() daiku.recipe({action = "run", name = "x"}) end,
			function() daiku.watch({action = "add", every = "1h"}) end,
			function() daiku.network({action = 1}) end,
			function() daiku.read("snapshot") end,
			function() daiku.read({"snapshot"}) end,
		} do
			assert(not pcall(case), "invalid call succeeded")
		end
		assert(#requests == 8, "invalid input reached the network")

		-- listTools pages, keeps only exported tools and returns the server's instructions.
		local listed = daiku.listTools()
		assert(#listed.tools == 1 and listed.tools[1].name == "read" and listed.instructions == "Open a workspace first.")
		assert(json.decode(requests[11].body).params.cursor == nil and json.decode(requests[12].body).params.cursor == "c2")
		assert(json.decode(requests[12].body).id == 3)
		assert(#requests == 13 and requests[13].method == "DELETE")
		assert(string.find(json.encode(listed), '"tools":[', 1, true))
	end,
}
