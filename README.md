[![Build Status](https://github.com/stevius10/Proxmox-GitOps/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/stevius10/Proxmox-GitOps/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
  - [Core Concepts](#core-concepts)
  - [Design](#design)
  - [Trade-offs](#trade-offs)
- [Usage](#usage)
  - [Lifecycle](#lifecycle)
  - [Getting Started](#getting-started)
    - [Requirements](#requirements)
    - [Define Container](#define-container)

---

## Overview

Proxmox-GitOps implements a self-sufficient, extensible CI/CD environment for provisioning, configuring, and orchestrating Linux Containers (LXC) within Proxmox VE. Leveraging an Infrastructure-as-Code (IaC) approach, it manages the entire container lifecycle—bootstrapping, deployment, configuration, and validation—through version-controlled automation.

## Architecture

The architecture is based on a multi-stage pipeline capable of recursively deploying and configuring itself. 

<p align="center">
  <img src="./docs/concept.svg" alt="Concept"/>
</p>

Initial bootstrapping is performed via a local Docker environment, with subsequent deployments targeting Proxmox VE.  

### Core Concepts 

This system implements stateless infrastructure management on Proxmox VE, ensuring deterministic reproducibility and environmental parity through recursive self-containment.

| Concept | Approach | Reasoning |
|---------|----------|-----------|
| **Ephemeral State** | Git repository represents *current desired state*, ensuring state purity across deployments.| Deployment consistency and stateless infrastructure over version history. |
| **Recursive Self-Containment** | Embedded control plane recursively provisions itself within target containers, ensuring deterministic bootstrap.| Prevents configuration drift; enables consistent and reproducible behavior. |
| **Dynamic Orchestration** | Imperative logic (e.g. `config/recipes/repo.rb`) used for dynamic, cross-layer state management| Declarative approach intractable for adjusting to dynamic cross-layer changes (e.g. submodule remote rewriting). |
| **Monorepository** | Centralizes infrastructure as a single code artifact; submodules modularize development at runtime| Consistency and modularity: infrastructure self-contained; dynamically resolved in recursive context. |

### Design

- **Loosely coupled**: Containers are decoupled from the platform, so control plane is independently interchangeable.

- **Headless**: Ansible for provisioning, leveraging upstream maintenance; Cinc (Chef) for modular, declarative desired state configuration and managing recursive complexity.

### Trade-offs

- **Complexity vs. Autonomy:** Recursive self-replication increases complexity drastically to achieve integrated deterministic bootstrap and reproducing behavior.

- **Git Convention vs. Infrastructure State:** Uses Git as a state engine rather than versioning in volatile, stateless contexts. Mono-repository representation, however, encapsulates the entire infrastructure as a self-contained asset suited for version control.

<p align="center">
  <img src="./docs/repositories.png" alt="Repositories"/>
</p>

## Usage

### Lifecycle

- **Self-contained Mono-Repository** Artifact for **Version-Controlled Mirroring**
  - `clone` aliased `git clone --recurse-submodules` (store network /share in persistent context)

- **Backup**: See previous

- **Update**: See previous, and redeploy merged

- **Rollback**: See previous, or set `snapshot` to `release` at runtime

### Getting Started

- Set **credentials and Proxmox API token** in [`local/.config.json`](local/.config.json) as `./local/config.json`
- Run `./local/run.sh` for local Docker environment
- Accept the Pull Request at `localhost:8080/srv/proxmoxgitops/pulls/1` to deploy on Proxmox VE

<p align="center">
  <img src="./docs/recursion.png" alt="Pipeline"/>
</p>

#### Requirements

- Docker
- Proxmox VE 8.4
- Proxmox API token
- See [Wiki](https://github.com/stevius10/Proxmox-GitOps/wiki) for recommendations

#### Define Container

Reusable container definitions are stored in the [`libs`](libs) folder. Copy an example container (like [`libs/broker`](libs/broker) or [`libs/proxy`](libs/proxy)) as a template, or create a new container lib from scratch and follow these steps:

- Add `config.env` to your container's _libs_ root directory (e.g. `./libs/apache`):
```dotenv
IP=192.168.178.42
ID=42
HOSTNAME=apache
CORES=2
MEMORY=2048
SWAP=512
DISK=local-lvm:8
BOOT=yes
```

- Paste generic pipeline in container's `.gitea/workflows`:
```yaml
on:
  workflow_dispatch:
  push:
    branches: [ release, main, develop ]

jobs:
  include:
    runs-on: shell
    steps:
      - id: init
        uses: srv/config/.gitea/workflows@main
        with:
          repo: ${{ gitea.repository }}
          ref: ${{ gitea.ref_name }}
          cache_bust: ${{ gitea.run_number }}
```

- Add your cookbook to the container definition root:
```ruby
# libs/apache/recipes/default.rb
package 'apache2'

file '/var/www/html/index.html' do
  content "<h1>Hello from #{Env.get(node, 'login')}</h1>"
  mode '0644'
  owner 'app' # see base/roles/base/tasks/main.yml
  group 'app' # each container is configured identically 
end

Common.application 'apache2' # reusables included by convention
```

- Optionally, use `Env.get()` and `Env.set()` to access Gitea environment variables.

- a) **Deploy**: Push to the `release` branch of a new repository

- b) **Add to Meta-/Mono-Repository**: Add path to [repositories](config/attributes/default.rb#L24) and redeploy

The container can be tested locally running `./local/run.sh [container]` (_wip_)

<p align="center">
  <img src="./docs/development.png" alt="Local Development"/>
</p>
