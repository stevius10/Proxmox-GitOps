## Configuration Reference
* [Credentials](#credentials-localconfigjson-or-localconfiglocaljson)
* [Global Environment](#global-environment-globalsjson-or-globalslocaljson)
* [Container Resources](#container-resources-containerenv-or-containerlocalenv)
* [Advanced Configuration](#advanced-configuration)
    * [State & Persistence](#state--persistence)
    * [Reverse Proxy](#reverse-proxy)

The configuration for `Proxmox-GitOps` and the container libraries is split into several files.

### Credentials
Contains credentials for Proxmox VE, the `Proxmox-GitOps` control plane, and container libraries.

- `./local/config.json` or `./local/config.local.json`

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

`Proxmox-GitOps` centralizes configuration via Git. It leverages [`Env.get()` and `Env.set()`](config/libraries/env.rb) to access environment variables, which are initially populated from the [globals](globals.json) file.

- `./globals.json` or `./globals.local.json`

### Container Resources

Defines resource allocation for the `Proxmox-GitOps` control plane and container libraries.

- `./container.env` or `./container.local.env`
- `./libs/{lib}/container[.local|.stage].env`

```dotenv
IP="192.168.178.***"
ID="***"
...
MOUNT="..."
```

* Host-level resources can be passed to containers via `MOUNT`, e.g., `MOUNT="/mnt/..:/share/.."`.

### Advanced Configuration

#### State and Persistence
The control plane `config` manages the (network) `/share`.

* Create `./local/share/` to override the `Proxmox-GitOps` default share (e.g., to fix keys or set specific snapshot paths).
```
tree -a ./local/share
./local/share
├── .certs
│   ├── .lego
│   │   ├── accounts
│   │   └── certificates
├── .keys
│   ├── 100
│   ├── 100.pub
│   ├── 101
│   ├── ...
└── snapshots
    ├── assistant
    │   ├── assistant-260420.tar.gz
    └── bridge
        ├── bridge-260420.tar.gz
```

* Snapshots are automatically restored via `Utils.snapshot` and written to `/share/snapshots/{lib}/` by the `snapshot` pipeline.


#### Reverse Proxy
The Caddy-based reverse proxy dynamically includes configuration files via `./libs/proxy/templates/Caddyfile`:

  ```erb
  <%= domain %> {
      import <%= @config_dir %>/*<%= hostname %>.caddy
     ...
  } <% end -%>
  import <%= @config_dir %>/*.local.caddy
  ```

You can inject custom logic via `.caddy` and `.local.caddy` files, for example in `./libs/proxy/files/default/config/10-assistant.local.caddy`:

```caddy
proxmox.gitops.pm {
    @denied not remote_ip 192.168.178.0/24
    abort @denied
    tls /share/.certs/cert.crt /share/.certs/cert.key
    import default assistant 192.168.178.110:8123
}
```
