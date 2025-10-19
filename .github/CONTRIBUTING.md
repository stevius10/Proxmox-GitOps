# Contributing to Proxmox-GitOps

Thank you for considering contributing to Proxmox-GitOps.

This document provides guidelines for contributing. These are conventions, not strict mandates; feel free to propose improvements to this document via a pull request.

This project is governed by the [Code of Conduct](CODE_OF_CONDUCT.md) and released under the [MIT License](../LICENSE). By participating, contributors agree to uphold these terms.

### Workflow
- Branching: Fork the repository and create a branch from `develop`. The `main` branch is for stable releases, while `develop` is the active integration branch.
- Make Changes: Follow existing patterns in the codebase. Keep the branch narrowly scoped for easier review.
- Idempotency: Test changes multiple times to ensure idempotency. Subsequent runs should result in no changes.
- Open Pull Request: Open a pull request from the fork’s branch to the main repository’s `develop` branch. Provide a clear summary and link relevant issues.

### Development Guidelines

#### Architecture
- Proxmox-GitOps is a self-contained monorepo that uses Git submodules to compose the complete Infrastructure-as-Code declaration.
- The system bootstraps from a local Docker environment, which initializes itself.

#### Idiomatic Development
- Abstraction and modulararity: Extract repetitive tasks into high-level modules. Prefer shared, project-specific abstractions over re-defining primitive resource to enforce consistency and centralize logic.
- Context (`ctx`): Most library expect a context object (`ctx`) as argument. Within configuration, pass `self` as context to provide access to the run context, node attributes, and the resource DSL.
- Centralize Configuration: Encapsulate lookup to reinforce GitOps-driven model with centrally managed configuration.
- Preserve Separation of Concerns. 

### Container Definitions
Modular container definitions in `libs/` following this structure: 

```
libs/mycontainer/
├── config.env
├── recipes/
│   └── default.rb
├── templates/
└── attributes/
    └── default.rb
```

### Questions and Support
- Issues: Use GitHub Issues for bug reports and feature requests. 
- Report Bugs
  - Include clear, step-by-step instructions to reproduce the issue.
  - Describe the expected behavior versus the actual behavior.
  - Add relevant environment details (e.g., versions).
  - Attach applicable logs.
- Suggest Enhancements
  - Explain change and motivation. 
  - Describe how it aligns with the project's scope, concept and architecture.
- Discussion: Engage with maintainers and contributors.
- Documentation: [Wiki](https://github.com/stevius10/Proxmox-GitOps/wiki) for setup instructions and configuration examples.
