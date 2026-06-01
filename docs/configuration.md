# Configuration

Requirements Engineering MCP is configured via environment variables with the
``REQENG_MCP_`` prefix.

## Common variables

See `fastmcp-pvl-core`'s README for the full list of universal
variables (`REQENG_MCP_TRANSPORT`, `REQENG_MCP_HOST`,
`REQENG_MCP_PORT`, `REQENG_MCP_HTTP_PATH`,
`REQENG_MCP_BASE_URL`, auth vars, etc.).

## MCP File Exchange

These variables control [MCP File Exchange](guides/file-exchange.md)
participation: pass-by-reference file transfer between co-deployed
servers (and HTTP fallback for remote clients). All are optional; the
defaults are sensible for both stdio and HTTP deployments.

| Variable | Default | Description |
|----------|---------|-------------|
| `REQENG_MCP_FILE_EXCHANGE_ENABLED` | `true` on HTTP/SSE, `false` on stdio | Master switch. Set `false` to opt out entirely. |
| `REQENG_MCP_FILE_EXCHANGE_PRODUCE` | `true` | Allow this server to mint `FileRef` objects via `handle.publish(...)`. |
| `REQENG_MCP_FILE_EXCHANGE_CONSUME` | `true` | Master toggle for the consumer side. **Only effective when `consumer_sink=` is wired in `server.py`**; without that argument, `fetch_file` is never registered no matter how this var is set. See [the guide](guides/file-exchange.md#consuming-files-consumer_sink). |
| `REQENG_MCP_FILE_EXCHANGE_TTL` | `3600` | Lifetime in seconds for download links and exchange-volume records. |
| `REQENG_MCP_UPLOAD_ENABLED` | `true` on HTTP/SSE, `false` on stdio | Master switch for the upload direction. **Only effective when `register_file_exchange_upload(...)` is uncommented in `server.py`**; without that call, no upload route is mounted regardless of this var. Also requires `REQENG_MCP_BASE_URL` to be set so `create_upload_link` can mint usable URLs. See [the guide](guides/file-exchange.md#uploading-files-receiver). |
| `REQENG_MCP_UPLOAD_MAX_BYTES` | `10485760` (10 MiB) | Maximum POST body size for the upload route. Bodies exceeding this return HTTP 413. |
| `REQENG_MCP_UPLOAD_TTL` | `300` | Default lifetime in seconds for upload links. Caller-requested TTL is clamped to `REQENG_MCP_UPLOAD_TTL_MAX`. |
| `REQENG_MCP_UPLOAD_TTL_MAX` | `3600` | Operator ceiling for caller-requested upload-link TTL. |
| `REQENG_MCP_BASE_URL` | unset | Public base URL of this server. Required for the `http` transfer method; the `create_download_link` tool and (when upload is wired) the `create_upload_link` tool both build URLs against it. Also referenced by the OIDC guide and the universal-variables list above. Set it once and every consumer picks it up. |

Note the upload-direction variables are namespaced under `_UPLOAD_*`,
not `_FILE_EXCHANGE_UPLOAD_*`. This matches the upstream
`fastmcp-pvl-core` 2.1.0 contract. The download-direction variables
keep the historical `_FILE_EXCHANGE_*` namespace.

The deployer also controls three **unprefixed** environment variables
shared by every co-deployed server:

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_EXCHANGE_DIR` | unset | Path to a directory shared between co-deployed MCP servers. When set, the `exchange://` transfer method activates; when unset, only the HTTP method is available. |
| `MCP_EXCHANGE_ID` | persisted in `.exchange-id` | Optional explicit exchange-group identifier; first server to start writes a UUID into `${MCP_EXCHANGE_DIR}/.exchange-id`, subsequent starts must agree. |
| `MCP_EXCHANGE_NAMESPACE` | the server's `namespace=` argument | Override the namespace used in `exchange://` URIs for this process. |

<!-- DOMAIN-CONFIG-VARS-START -->
## Domain variables

Document your project-specific variables here.
<!-- DOMAIN-CONFIG-VARS-END -->
