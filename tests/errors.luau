-- HTTP and JSON-RPC failures: messages, retryable, no replayed calls, and session cleanup.
return {
	scenario = {publisher = {client_id = "fixture-client"}, config = {access = "read-write"}, auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		initStatus, initBody, initHeaders = 200, "", {}
		callStatus, callBody, callHeaders = 200, "", {}
		http = {request = function(req)
			table.insert(requests, req)
			if req.method == "DELETE" then
				return fixture.operation({statusCode = 405, headers = {}, body = fixture.reader("")})
			end
			local message = json.decode(req.body)
			if message.method == "initialize" then
				local body = if initBody ~= "" then initBody
					else '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{}}}'
				local headers = table.clone(initHeaders)
				headers["content-type"] = {"application/json"}
				if headers["mcp-session-id"] == nil then headers["mcp-session-id"] = {"sess-9"} end
				return fixture.operation({statusCode = initStatus, headers = headers, body = fixture.reader(body)})
			elseif message.method == "notifications/initialized" then
				return fixture.operation({statusCode = 202, headers = {}, body = fixture.reader("")})
			end
			return fixture.operation({statusCode = callStatus, headers = callHeaders, body = fixture.reader(callBody)})
		end}
	end,
	run = function(daiku)
		local function check(expected: {string}, requestCount: number)
			local before = #requests
			local ok, err = pcall(function() daiku.act({action = "click", ref = "e1", workspace = "w1"}) end)
			assert(not ok, "call succeeded")
			for _, text in expected do
				assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(#requests == before + requestCount, "request count " .. tostring(#requests - before))
			assert(not string.find(tostring(err), "fixture-client", 1, true))
		end

		-- Sign-in problems surface before any tool call.
		initStatus, initBody = 401, '{"error":"invalid_token","error_description":"The access token expired"}'
		check({"HTTP 401", "reconnect Daiku", "The access token expired", '"retryable":false'}, 1)
		initStatus, initBody = 503, "<html>down</html>"
		initHeaders = {["retry-after"] = {"7"}}
		check({"HTTP 503", "<html>down</html>", "Retry-After: 7", '"retryable":true'}, 1)
		initStatus, initBody, initHeaders = 200, "", {["mcp-session-id"] = {"bad id"}}
		check({"invalid session id"}, 1)
		initHeaders = {}
		initBody = '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"latest"}}'
		check({"invalid protocol version"}, 2)
		initBody = ""

		-- Tool-call failures still end the session (DELETE) and are never retried.
		callHeaders = {["content-type"] = {"application/json"}}
		callBody = '{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"Unknown tool argument: ref"}}'
		check({"Daiku error -32602", "Unknown tool argument: ref", '"retryable":false'}, 4)
		assert(requests[#requests].method == "DELETE" and requests[#requests].headers["Mcp-Session-Id"][1] == "sess-9")
		callStatus, callBody = 429, '{"jsonrpc":"2.0","error":{"code":-32000,"message":"Slow down"}}'
		callHeaders = {["retry-after"] = {"30"}}
		check({"HTTP 429", "Slow down", "Retry-After: 30", '"retryable":true'}, 4)
		callStatus, callBody = 500, string.rep("x", 9000)
		callHeaders = {}
		check({"HTTP 500", '"retryable":true'}, 4)
		callStatus, callHeaders = 200, {["content-type"] = {"text/event-stream"}}
		callBody = 'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{}}\n\n'
		check({"sent no answer"}, 4)
		callBody = 'data: {"jsonrpc":"2.0","id":2,"result":"text"}\n\n'
		check({"invalid result"}, 4)
		callHeaders = {["content-type"] = {"application/json"}}
		callBody = "not json"
		check({"sent no answer"}, 4)
	end,
}
