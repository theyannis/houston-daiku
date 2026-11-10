# Houston connector for Daiku

A [Houston](https://ok-houston.com) connector for [Daiku](https://daiku.ai), the
user's own Chrome browser signed in to their sites. It follows the
[houston-hub](https://github.com/aibakery/houston-hub) bundle layout and contract
(`AUTHORING.md`).

The bundle is in [`connectors/daiku`](connectors/daiku):

- `houston.json`: setup, Daiku OAuth (publisher-owned public client, PKCE) and the
  proxy rule, limited to `POST` and `DELETE https://daiku.ai/mcp`.
- `connector.luau`: a small client for Daiku's MCP server. Each call opens a
  session, calls one Daiku tool with its native arguments, and ends the session.
- `tests/`: fixtures for the read-only and read-write surfaces, stream parsing,
  errors and proxy routes.
- `README.md`, `SETUP.md`: what account users see.

## Publish on Houston Hub

1. Register a Daiku OAuth client once, with the publication's callback URL:

   ```sh
   curl -sS https://daiku.ai/oauth/register -H 'content-type: application/json' -d '{
     "client_name": "Houston",
     "redirect_uris": ["<Houston callback URL shown by Hub>"],
     "grant_types": ["authorization_code", "refresh_token"],
     "response_types": ["code"],
     "token_endpoint_auth_method": "none",
     "scope": "browser"
   }'
   ```

2. In Houston Hub, open **My connectors** and publish this repository, branch
   `main`, path `connectors/daiku/houston.json`.
3. Enter the returned `client_id` as **Daiku OAuth client ID**.
4. Add a connection and follow its setup to test it.
