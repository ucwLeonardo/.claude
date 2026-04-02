Adapt a tool, plugin, skill, or any code that needs network access to work inside Claude Code's bwrap sandbox on this WSL2 environment.

$ARGUMENTS = what to adapt (e.g. "web-access skill", "an MCP server that calls OpenAI API", "a script that fetches data from localhost:8080")

## Environment (known facts — do NOT ask user to re-explain)

**WSL2 mirrored networking** (`~/.wslconfig: networkingMode=mirrored`):
- WSL and Windows share localhost — WSL can directly reach Windows ports (Chrome:9222, Clash:7897, etc.)
- No virtual gateway, no NAT

**Claude Code sandbox** (`bwrap --unshare-net`):
- Each Bash tool call gets an **isolated network namespace** — cannot reach any TCP port, not even localhost
- `/tmp/` is bind-mounted and shared across all Bash calls
- Unix sockets in `/tmp/` are the ONLY cross-namespace communication channel

**Implication**: anything that needs network must be split into an outside-sandbox service + inside-sandbox client bridged via Unix socket.

## Adaptation Process

### 1. Read and map network dependencies

Read the code to adapt. For every network call (HTTP, WebSocket, TCP), note: what host:port, what protocol, is it persistent or request/response.

### 2. Verify direct connectivity (outside sandbox)

Use `dangerouslyDisableSandbox: true` to confirm the target is reachable from WSL:
```bash
curl -s --max-time 3 http://localhost:<port>/...
```
If this fails, fix the network issue first — it's not a sandbox problem.

### 3. Design the split

| Layer | Runs where | Role |
|-------|-----------|------|
| **Service** | Outside sandbox (`dangerouslyDisableSandbox`) | Persistent process with network access. Listens on Unix socket `/tmp/<name>.sock` AND optionally TCP for convenience. |
| **socat bridge** | Inside sandbox (each Bash call) | `socat TCP-LISTEN:<port>,fork,reuseaddr UNIX-CONNECT:/tmp/<name>.sock &` + `sleep 1` |
| **Client calls** | Inside sandbox (same Bash call as bridge) | `curl http://127.0.0.1:<port>/...` |

**Critical**: socat bridge + client calls = ONE Bash invocation. Never split them.

### 4. Eliminate unnecessary relays

With mirrored networking, WSL can reach Windows localhost directly. Remove any Windows-side relay/proxy processes that only exist to bridge old NAT networking. If the code spawns `node.exe` or `powershell.exe` just to proxy network calls, it's now redundant.

### 5. Implement and test

Test in three stages:
1. Outside sandbox → service starts, connects to target, socket created
2. Inside sandbox → socat bridge + health check curl
3. Inside sandbox → full end-to-end operation

### 6. Common gotchas

- **`ws` module**: not global — load via `createRequire('file:///mnt/d/project/package.json')('ws')`
- **Chrome debug port**: must kill all `chrome.exe` first, then restart with `--remote-debugging-port=9222 --user-data-dir=C:\Users\Administrator\AppData\Local\Google\Chrome\DevProfile`
- **Chrome DevProfile**: persistent — login state survives restarts
- **Starting Windows processes from WSL**: use `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Start-Process ..."`
- **Proxy (Clash)**: available at `localhost:7897` if internet access is needed outside the browser

## Deliverables

After adaptation is complete:
1. Working code that passes the three-stage test
2. Update the relevant skill/tool documentation with WSL2 sandbox usage instructions
3. Brief summary to user of what changed and why
