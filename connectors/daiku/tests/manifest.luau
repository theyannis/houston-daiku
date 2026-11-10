-- Proxy routes, OAuth scopes and configured exports for both access levels.
return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = {"POST", "https://daiku.ai/mcp"},
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "oauth",
				oauth = true,
				publisher = {client_id = "synthetic-public-client"},
				scopes = true,
			},
		})

		local readOnly = {"files", "listTools", "navigate", "network", "read", "recipe", "request_human", "show_browser", "tabs", "trust", "watch", "workspace"}
		local writes = {"act", "browser", "download", "evaluate", "feedback", "fill_secret", "paste", "send_request", "upload"}
		for _, access in {"read-only", "read-write"} do
			local r, err = m.resolve({client_id = "synthetic-public-client"}, {access = access}, {}, "oauth")
			assert(r and not err, tostring(err))
			assert(m.equal(r.Scopes, {"browser"}), "scopes must be exactly browser")
			r.Context.Auth["oauth"].access_token = "daiku-oauth"
			m.routes(r, "Bearer daiku-oauth", true, {
				"POST https://daiku.ai/mcp",
				"DELETE https://daiku.ai/mcp",
			})
			-- Only the MCP endpoint: never Daiku's OAuth, sign-in or file pages, nor lookalike hosts.
			m.routes(r, "Bearer daiku-oauth", false, {
				"GET https://daiku.ai/mcp",
				"PUT https://daiku.ai/mcp",
				"POST https://daiku.ai/oauth/token",
				"POST https://daiku.ai/oauth/register",
				"GET https://daiku.ai/authorize",
				"GET https://daiku.ai/.well-known/oauth-authorization-server",
				"GET https://daiku.ai/f/abc",
				"POST https://daiku.ai/mcp/extra",
				"POST https://daiku.ai/mcp/",
				"POST https://www.daiku.ai/mcp",
				"POST https://api.daiku.ai/mcp",
				"POST https://daiku.ai.evil.test/mcp",
				"POST https://evil-daiku.ai/mcp",
				"POST http://daiku.ai:8443/mcp",
			})
			m.rejectOverrides(r, {"POST https://daiku.ai/mcp"})

			local result, problem = m.exports({access = access}, "oauth", {"browser"})
			assert(result and not problem and result.type == "result", tostring(problem))
			local expected = table.clone(readOnly)
			if access == "read-write" then
				for _, name in writes do table.insert(expected, name) end
			end
			table.sort(expected)
			local exported = table.clone(result.exports)
			table.sort(exported)
			assert(m.equal(exported, expected), access .. " exports changed")
			local documented = {}
			for name in string.gmatch("\n" .. result.help, "\n([^%s%(]+)%(") do table.insert(documented, name) end
			table.sort(documented)
			assert(m.equal(documented, expected), access .. " help does not match exports")
			assert(#result.help < 16 * 1024, "help is too long")
		end
	end,
}
