## Configuration Reference

The configuration is split into credential configuration, global environment variables, and container-specific overrides. `.local` file suffixes can be used for configuration files to prevent data from being committed.

### Proxmox VE and Container Credentials
Credentials for Proxmox VE, the `Proxmox-GitOps` control plane, and its containers (`./local/config.json` or `./local/config.local.json`).

```json
{
  "proxmox": {
    "host": "192.168.178.***",
    "user": "root@pam",
    "password": "***"
  },
  "login": "***",
  "password": "***"
}
```

### Global Environment
Global environment settings and centralized configuration (`./globals.json` or `./globals.local.json`).

### Container Resources
Resource allocation for the control plane (`./container.env` or `./container.local.env`) and container libraries (`./libs/{lib}/container[.local|.stage].env`).

```dotenv
IP="192.168.178.***"
ID="***"
...
MOUNT="***"
```

### Advanced

#### State & Persistence
* **`config` /share:** The control plane initializes and persists the (_network_) share.
* **Application Snapshots:** The `snapshot` pipeline exports artifacts to `config`'s `/share/snapshots/{lib}/`.
* **Mounts and Passthrough** Host-level resources can be passed to containers via `MOUNT` in the container-specific `container.env` file (e.g., `MOUNT="/mnt/..:/share/.."`).

#### Reverse Proxy
The Caddy-based reverse proxy dynamically includes configuration files via `./libs/proxy/templates/Caddyfile`: 

  ```erb
  <% @hosts.each do |entry| -%> 
  <% domain, upstream, hostname = entry.split(' ') -%>
  <%= domain %> {
      import internal
      import <%= @config_dir %>/*<%= hostname %>.caddy
      tls internal
      import default <%= hostname %> <%= upstream %>
  }
  <% end -%>
  import <%= @config_dir %>/*.local.caddy
  ```

You can inject custom logic via `.caddy` and `.local.caddy` files: 

  - **Example:** `./libs/proxy/files/default/config/10-assistant.local.caddy`
    ```caddy
    proxmox.gitops.pm {
        @denied not remote_ip 192.168.178.0/24
        abort @denied
        tls /share/.certs/cert.crt /share/.certs/cert.key
        import default assistant 192.168.178.110:8123
    }
    ```
