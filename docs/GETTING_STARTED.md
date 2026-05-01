## Getting Started
- [Configuration](#configuration)
    - [Configure Credentials](#configure-credentials)
    - [Environment Configuration](#environment-configuration)
- [Deployment and Automation](#deployment-and-automation)

---

### Configuration
Edit the configuration according to [Proxmox-GitOps#deployment](../README.md#deployment).

#### Configure Credentials
```bash
jq '
  .proxmox.host = "192.168.178.100" |
  .proxmox.user = "root@pam" |
  .proxmox.password = "GITOPS.PM" |
  .login = "steven" |
  .password = "gitops.pm"
' local/config.json > local/config.local.json
```

#### Environment Configuration
Ensure the global environment configuration (`globals.json`) is set up to centralize configuration in Git :
```json
{
  "AUTO_DEPLOY": "false",
  "LIBS_BROKER_ENDPOINT": "mqtt://192.168.178.109:1883",
  "LIBS_BRIDGE_ADAPTER": "zstack",
  "LIBS_BRIDGE_SERIAL": "/dev/serial/by-id/"
}
```

#### Optional: [`config` Share](reference/CONFIGURATION.md#persistence)

### Deployment and Automation

- If `AUTO_DEPLOY` is set to `true`, `./local/run.sh` will deploy `Proxmox-GitOps` to PVE as `config` container, and subsequently deploy the container libraries (`/libs`) from within the `config` container itself.

- Otherwise, the container deployment must be triggered manually by accepting the Pull Request, either via `http://localhost:8080/main/config` or directly from the `config` container for the respective container library.
