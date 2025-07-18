[![Build Status](https://github.com/stevius10/Proxmox-GitOps/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/stevius10/Proxmox-GitOps/actions/workflows/build.yml)

## Overview

Proxmox GitOps implements a self-sufficient, extensible CI/CD environment for provisioning, configuring, and orchestrating Linux Containers (LXC) within Proxmox VE. Leveraging an Infrastructure-as-Code (IaC) approach, it manages the entire container lifecycle—bootstrapping, deployment, configuration, and validation—through version-controlled automation.

## Architecture

The architecture is based on a multi-stage pipeline capable of recursively deploying and configuring itself. 

<p align="center">
  <img src="./docs/concept.svg" alt="Concept"/>
</p>

Initial bootstrapping is performed via a local Docker environment, with subsequent deployments targeting Proxmox VE. This ensures consistent, reproducible, and automated infrastructure management. 

## Getting Started

- Configure **credentials and Proxmox API token** in [`local/.config.json`](local/.config.json) as `config.json`
- Run `local/run.sh` for local Docker environment 
- Accept the [`Pull Request`](http://localhost:8080/srv/proxmoxgitops/pulls/1) to deploy on Proxmox VE

<p align="center">
  <img src="./docs/recursion.png" alt="Pipeline"/>
</p>

### Create Container

Reusable container definitions are stored in the [`libs`](libs) folder. Copy an example container (like [`libs/broker`](libs/broker) or [`libs/proxy`](libs/proxy)) as a template, or create a new container lib from scratch and follow these steps:

- Add `config.env` to your container's root directory, e.g.:
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

- Paste generic pipeline in `gitea/workflows`:
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
# ./libs/apache/recipes/default.rb
package 'apache2'

service 'apache2' do
  action [:enable, :start]
end

file '/var/www/html/index.html' do
  content "<h1>Hello from #{Env.get(node, 'login')}</h1>"
  mode '0644'
  owner 'app' # see base/roles/base/tasks/main.yml
  group 'app' # each container is configured identically 
end
```

- Optionally, use `Env.get()` and `Env.set()` to access Gitea environment variables.

- a) **Deploy**: Push to the `release` branch of a new repository

- b) **Add to Meta-/Mono-Repository**: Add path to [repositories](config/attributes/default.rb#L24) and redeploy Proxmox-GitOps

The container can be tested locally running `./local/run.sh [container]`

<p align="center">
  <img src="./docs/development.png" alt="Local Development"/>
</p>


### Requirements

- Docker
- Proxmox VE
- Proxmox API token
- See [Wiki](https://github.com/stevius10/Proxmox-GitOps/wiki) for recommendations 

### Core Concepts

#### Self-Replication
- During configuration, the codebase is pushed into a Gitea instance running inside the container
- This triggers the same pipeline from within the new environment, enabling recursive configuration ("pipeline within a pipeline")
- Subsequent runs are idempotent: Ansible and Chef validate and enforce the desired state using static configuration

<p align="center">
  <img src="./docs/repositories.png" alt="Repositories"/>
</p>

#### Key Features

- **Self-Managed Infrastructure:** The system provisions, configures, and verifies itself recursively
- **Container Provisioning:** Managed by Ansible using the Proxmox API
- **Container Configuration:** Managed by cookbooks for application-level setup
- **CI/CD Orchestration:** Execution is handled by a Runner automatically installed inside the container
- **Environment Management:** Environment variables are initially loaded from `config.json` and recursively propagated into the GitOps system
- **Modularity:** Distinct components and modular reusable workflows managed within Gitea, facilitating extension
