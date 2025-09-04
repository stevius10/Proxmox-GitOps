# Reference for the Ruby library modules

Modules are self‑contained and usable in container recipes and the control plane. 

Functions are exposed as module methods and usually accept a context object `ctx` - Chef or resource context, e.g. `self` within recipe or reconstructured object in Ruby scripts. 

## Table of Contents

- [Common](#common-general-utilities)
- [Constants](#constants-http-constants)
- [Default](#default-default-configuration-values)
- [Ctx](#ctx-chef-context-helpers)
- [Env](#env-environment-and-external-config-management)
- [Logs](#logs-logging-and-error-handling-utilities)
- [Patch](#patch-ruby-core-extensions-and-compatibility)
- [Utils](#utils-general-utilities)

---

## Common

High‑level helpers for frequent automation tasks in recipes (packages, directories, systemd). Wraps Chef resources to ensure concise, idempotent operations.

### `Common.packages(ctx, *pkgs, action: :install)`
Installs or removes packages using Chef’s `package` resource for each given name.

- **Parameters:** `*pkgs` package names; `action` e.g. `:install`, `:remove`
- **Returns:** `true` on success

**Example**

```ruby
Common.packages(self, 'nginx', 'git')
```

---

### `Common.directories(ctx, dirs, opts = {})`
Ensures one or multiple directories exist (optionally recreates).

- **Parameters:**
  - `dirs` String or Array of paths
  - `owner`, `group` (default: `Default.user(ctx)`, `Default.group(ctx)`)
  - `mode` String permissions (default `"0755"`)
  - `recursive` Boolean (default `true`)
  - `recreate` Boolean delete‑then‑create (default `false`)
- **Behavior:** creates missing paths; when `recreate: true`, deletes first using safe order
- **Returns:** `true`

**Example**

```ruby
Common.directories(self, ['/var/app/data', '/var/app/log'], owner: 'appuser', group: 'appgroup', recreate: true)
```

---

### `Common.daemon(ctx, name)`
Declares a single `systemctl daemon-reload` execute resource (no immediate run). Used to ensure systemd notices new unit files.

- **Parameters:** `name` String key
- **Returns:** the execute resource

---

### `Common.application(ctx, name, user: nil, group: nil, exec: nil, cwd: nil, unit: {}, actions: [:enable, :start], restart: 'on-failure', subscribe: nil, reload: 'systemd_reload', verify: true, verify_timeout: 60, verify_interval: 3, verify_cmd: "systemctl is-active --quiet #{name}")`
Deploys and manages a systemd service in one call, optionally writing a unit file and performing a health check.

- **Creates/updates:** `/etc/systemd/system/<name>.service` if `exec` or `unit` provided
- **Defaults:** `Type=simple`, `WantedBy=multi-user.target`, `After=network.target`, restart policy per `restart`
- **Service:** manages `:enable`, `:start` by default; `:force_restart` triggers explicit stop/start
- **Subscriptions:** optional `subscribe` array/resource for delayed restart
- **Health check:** when `verify`, runs a polling block until `verify_cmd` is successful or `verify_timeout` elapses

**Example**

```ruby
Common.application(self, 'my_app',
  exec: '/usr/local/bin/my_app --serve',
  user: 'appuser', group: 'appgroup',
  actions: [:enable, :start],
  verify: true
)
```

---

### `Common.create_dir(ctx, dir, owner, group, mode, recursive)`
Low‑level directory creation wrapper around Chef `directory`. Logs warnings on errors instead of raising.

### `Common.delete_dir(ctx, dir)`
Low‑level safe deletion of a directory tree if it exists. Errors are logged and suppressed based on policy.

### `Common.sort_dir(dirs)`
Sorts paths deepest‑first to ensure safe deletion order.

---

## Constants

Shared HTTP header constants for API interactions.

- `Constants::HEADER_JSON` → `{ 'Content-Type' => 'application/json', 'Accept' => 'application/json' }`
- `Constants::HEADER_FORM` → `{ 'Content-Type' => 'application/x-www-form-urlencoded' }`

Use with `Utils.request` and `Env.request` for consistent headers.

---

## Default

Helpers for default user/group/config resolution from ENV or node attributes.

### `Default.user(ctx, default: nil)`
Returns the application username. Falls back to `"app"` or forced default when `default: true`.

### `Default.group(ctx, default: nil)`
Returns the application group. Falls back to `"config"` or forced default when `default: true`.

### `Default.config(ctx, default: nil)`
Returns the config directory/key, default `"config"`.

### `Default.presence_or(var, default)`
Returns `var.to_s` if present, else `default.to_s`.

---

## Ctx

Normalize arbitrary objects into a usable Chef DSL context and manage resources safely.

### `Ctx.node(obj)`
Extracts `Chef::Node` from recipes/resources/run contexts or returns `obj` if already a node.

### `Ctx.dsl(obj)`
Returns a DSL‑capable context for declaring Chef resources, constructing one if needed.

### `Ctx.rc(obj)`
Returns `Chef::RunContext` or `nil`.

### `Ctx.find(obj, type, name, &block)`
Finds or defines a resource `type[name]` within the current run, avoiding duplicates.

**Example**

```ruby
Ctx.find(self, :execute, 'my_task') { action :nothing }
```

---

## Env

Unified retrieval/storage of configuration bridging node attributes, environment variables, and external GitOps stores (e.g., Gitea).

### `Env.creds(ctx, login = 'login', password = 'password')`
Returns `[user, pass]` by checking ENV (`LOGIN`, `PASSWORD`) and node attributes.

### `Env.get(ctx, key)`
Retrieves `key` from node, then ENV, else via `Env.get_variable` from remote config. Errors are logged and suppressed unless critical.

**Example**

```ruby
db_password = Env.get(self, 'db_password')
```

### `Env.get_variable(ctx, key, repo: nil, owner: nil)`
Fetches a remote variable via API using `Env.endpoint` and credentials.

### `Env.set_variable(ctx, key, val, repo: nil, owner: nil)` (alias: `Env.set`)
Creates or updates a remote variable. Values are JSON‑encoded when not strings. Logs with masked values. Raises on failure.

**Example**

```ruby
Env.set(self, 'API_TOKEN', 'supersecretvalue', repo: 'my-app')
```

### `Env.endpoint(ctx)`
Builds the Git service API base URL, typically `http://<host>:8080/api/v1`, from node/ENV or `git.api.endpoint`.

### `Env.request(ctx, key, body: nil, repo: nil, owner: nil, expect: false)`
Performs GET/PUT/POST for variables. Returns HTTP response; with `expect: true` returns boolean success.

### `Env.dump(ctx, *args, repo: nil, owner: nil)`
Batch‑export of node values to remote variables. Supports Scalars, Hash (flattens keys), Array (indexes), and `[key, value]` pairs or procs. Raises on failure.

**Example**

```ruby
Env.dump(self, 'app_version', 'db')
```

---

## Logs

Consistent logging, context‑rich debugging, and error control around risky operations.

### `Logs.log(msg, level: :info)`
Core formatter; delegates to `Chef::Log` with method labels and callsites.

### `Logs.info(msg)` / `Logs.warn(msg)`
Level‑specific conveniences.

### `Logs.error(msg, raise: true)`
Logs error; raises by default.

### `Logs.info?(msg, result: true)`
Logs and returns `result` for inline use.

### `Logs.request(uri, response)`
Standardizes request/response logs; returns `response` unchanged.

### `Logs.return(msg)`
Logs and returns `msg`.

### `Logs.debug(msg, *pairs, ctx: nil, level: :info)`
Structured message with optional key/value pairs and deep environment dump at debug level.

### `Logs.try!(msg, *pairs, ctx: nil, raise: false) { ... }`
Executes a block with error handling and structured logging; re‑raises when `raise: true`.

### `Logs.request!(uri, response, valid = [], msg: nil, ctx: nil)`
Validates HTTP status codes (`valid` Array or `true` for any 2xx). Raises on unexpected status.

---

## Patch

Monkey Patching and compatibility.

### Core object enhancements
- `Object#blank?`, `#present?`, `#presence`, `#presence_in(collection)`
- `NilClass#blank?`, `#present?`, `#presence`

### Data type extensions
- `String#blank?`, `#squish`, `#mask`
- `Integer#minutes`, `#hours`
- `Hash#slice`, `#except`, `#json`, `#mask`
- `Array#mask`
- `Net::HTTPResponse#json(symbolize_names: false, allow_blank: false, validate_content_type: false)`

### Other additions
- Global `include(rel_path)` loader for relative Ruby files
- Chef compatibility shims for `Chef` and `Chef::Log` when absent

**Examples**

```ruby
''.blank?
' Hello  \nWorld '.squish
'secret1234'.mask
2.hours
{foo: 1, bar: 2}.except(:bar)
['alpha', 'beta'].mask
```

---

## Utils

Utilities for waiting, system checks, snapshot backup/restore, HTTP requests, and installation logic.

### `Utils.wait(condition = nil, timeout: 20, sleep_interval: 5, &block)`
Flexible waiter:
- Numeric → sleeps that many seconds
- URL String → polls until 2xx/3xx
- `host:port` String → polls TCP connect
- Block → runs with timeout

**Examples**

```ruby
Utils.wait('127.0.0.1:8080', timeout: 30, sleep_interval: 2)
Utils.wait('https://my.service/health', timeout: 60)
Utils.wait(5)
```

---

### `Utils.arch(ctx)`
Returns normalized architecture: `"arm64"`, `"armv7"`, or `"amd64"`.

---

### `Utils.snapshot(ctx, dir, snapshot_dir: '/share/snapshots', name: ctx.cookbook_name, restore: false, user: Default.user(ctx), group: Default.group(ctx), mode: 0o755)`
Creates or restores a verified tarball snapshot of `dir`. On restore, wipes and re‑creates the target, fixes ownership and permissions. On create, verifies by checksum comparison.

**Examples**

```ruby
Utils.snapshot(self, '/var/lib/myapp/data')
Utils.snapshot(self, '/var/lib/myapp/data', restore: true)
```

---

### `Utils.proxmox(ctx, path)`
Authenticated GET against Proxmox API at `https://<host>:8006/api2/json/<path>`. Supports password (ticket) and API token modes. Returns parsed `"data"` payload.

**Example**

```ruby
nodes = Utils.proxmox(self, 'nodes')
```

---

### `Utils.request(uri, user: nil, pass: nil, headers: {}, method: Net::HTTP::Get, body: nil, expect: false, log: true, verify: OpenSSL::SSL::VERIFY_NONE)`
General HTTP helper with redirect handling, optional basic auth, logging, and expectation mode.

**Examples**

```ruby
resp = Utils.request('https://api.example.com/data', headers: { 'Accept' => 'application/json' })
ok = Utils.request('https://example.com/upload', method: Net::HTTP::Post, body: 'data', expect: true)
```

---

### `Utils.install(ctx, uri, app_dir, data_dir, version_dir: "/app", snapshot_dir: "/share/snapshots")`
Decides whether to install/upgrade based on `Utils.latest` and current version file at `version_dir/.version`. If a change is needed, recreates `app_dir`, snapshots `data_dir`, writes the new version, and returns the version; otherwise returns `false`.

**Example**

```ruby
version = Utils.install(self, 'https://example.com/myapp/releases/', '/app/myapp', '/var/lib/myapp')
```

---

### `Utils.download(ctx, path, url:, owner: Default.user(ctx), group: Default.group(ctx), mode: '0754', action: :create)`
Wrapper around `remote_file` with defaults. Accepts lazy `url` via `Proc`.

**Example**

```ruby
Utils.download(self, '/usr/local/bin/tool', url: 'https://example.com/tool-latest.sh', mode: '0755')
```

---

### `Utils.latest(url, installed_version = nil)`
Scrapes a version string from a releases page `<title>` (`v?X.Y[.Z]`). Returns a version String when initial or newer is available; otherwise `false`.

**Example**

```ruby
latest = Utils.latest('https://example.com/releases', '1.2.3')
```
