# VoIP Infrastructure Documentation

This directory contains specialized documentation for VoIP infrastructure design and implementation using libvirt virtualization on macOS.

## Documents

- **ANSIBLE_DYNAMIC_INVENTORY_POSTGRESQL.md** - Ansible dynamic inventory integration with PostgreSQL
- **AUTOMATION_INFRASTRUCTURE_DESIGN.md** - Complete VoIP automation architecture using libvirt
- **VOIP_INFRASTRUCTURE_ANALYSIS.md** - Analysis of VoIP infrastructure requirements and design decisions

## Overview

The VoIP infrastructure uses **libvirt for VM management** instead of containers, providing:
- Better automation support (Ansible, Terraform)
- Infrastructure as code
- HVF (Hypervisor.framework) support on macOS
- Declarative VM definitions

## Architecture

```
macOS Host (Apple Silicon)
├── Native Automation (no VM overhead)
│   ├── Ansible
│   ├── Terraform
│   └── libvirt client
│
├── Colima VM (devstack-core)
│   └── 12 containers (core infrastructure)
│
└── libvirt VMs (VoIP production)
    ├── OpenSIPS
    ├── Asterisk
    ├── RTPEngine
    └── PostgreSQL (VoIP database)
```

## Note

This VoIP infrastructure is **separate from DevStack Core** containers. DevStack Core provides the foundational services (Vault, databases, Git) while VoIP services run in dedicated VMs for performance and isolation.
