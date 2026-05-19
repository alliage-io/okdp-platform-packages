[![ci](https://github.com/okdp/platform-packages/actions/workflows/ci.yml/badge.svg)](https://github.com/okdp/platform-packages/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/okdp/platform-packages)](https://github.com/okdp/platform-packages/releases/latest)&ensp;&ensp;
[![Flux](https://img.shields.io/badge/flux-latest-purple.svg)](https://fluxcd.io/)
[![KuboCD](https://img.shields.io/badge/kubocd-v0.2.2-green.svg)](https://github.com/kubocd/kubocd)&ensp;&ensp;
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.28+-blue.svg)](https://kubernetes.io/)
[![Kind](https://img.shields.io/badge/kind-latest-orange.svg)](https://kind.sigs.k8s.io/)&ensp;&ensp;
[![License Apache2](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
<a href="https://okdp.io">
<img src="https://okdp.io/logos/okdp-notext.svg" height="20px" style="margin: 0 2px;" />
</a>

## Overview

This repository contains the OKDP platform packages used to bootstrap and operate platform services with [KuboCD](https://www.kubocd.io/).

KuboCD complements GitOps controllers such as Flux by adding a higher-level packaging and deployment abstraction on top of Helm-based applications. Flux reconciles the desired state into the cluster, while KuboCD standardizes how platform engineers package applications and how teams deploy them through curated, declarative resources.

## KuboCD Concepts

KuboCD is built around a few concepts that are used throughout this repository:

- **Package**: a versioned OCI artifact that bundles a KuboCD application descriptor and one or more Helm charts. The manifests under `packages/` define the packages published by this repository.
- **Release**: a Kubernetes custom resource that deploys a specific package version into a cluster. Release manifests live under `releases/` and define where a package is installed, which tag is used, and which parameters and contexts are applied.
- **Context**: a reusable, declarative configuration layer shared across releases. Contexts provide environment-aware values such as ingress suffixes, storage classes, certificate issuers, catalogs, provider bindings, authentication settings, service endpoints, and platform defaults.

Contexts in this repository are applied as ordered layers. Each layer adds or overrides a specific part of the platform model, and KuboCD merges them into the effective context used by packages and releases:

- [`10-platform-context.yaml`](./10-platform-context.yaml): the base platform layer. It defines platform-wide values such as proxy settings, ingress suffix and class, certificate issuers, storage classes, portal catalogs, portal services, package repository, cluster metadata, and UI metadata.
- [`20-provider-context.yaml`](./20-provider-context.yaml): the provider abstraction layer. It binds shared provider contracts for object storage, OIDC identity, and PostgreSQL-compatible databases. In the sandbox these point to SeaweedFS, Keycloak, and CloudNativePG/PostgreSQL, but the same contracts can be replaced by external providers.
- [`30-service-context.yaml`](./30-service-context.yaml): the service layer. It describes how platform services consume the provider contracts and expose reusable service settings, including Hive Metastore, Trino, Superset, JupyterHub, Spark, Spark History Server, Polaris, Polaris Console, and Airflow.
- [`99-examples-context.yaml`](./99-examples-context.yaml): the final examples and sandbox layer. It adds demo lakehouse catalogs, Superset data sources, Spark/Jupyter connections, Polaris realms and grants, Airflow DAG sync, example datasets, local provider settings, users, roles, clients, databases, and local static secrets for sandbox usage.

The layer prefixes make the intended order explicit: platform foundations first, provider bindings next, service contracts after that, and example usage last. Environment-specific variants can define, override, or extend any layer while keeping the same declarative deployment model.

During deployment, KuboCD resolves package parameters together with the selected contexts and injects the resulting values into the target Helm releases. When a context changes, KuboCD propagates the update to the releases that reference it and reconciles only the components whose rendered configuration is affected.

For example, an organization can keep a shared `org` or `global` base, then layer `sandbox`, `dev`, and `prod` context files with environment-specific provider endpoints, credentials integration, storage classes, catalogs, or service defaults.

## Structure

```
packages/
├── system/             # Infrastructure & system packages
│   ├── cert-manager/
│   ├── ingress-nginx/
│   ├── dns-server/
│   └── ...
└── services/           # Services
    ├── superset/
    ├── jupyterhub/
    ├── seaweedfs/
    └── ...
releases/               # KuboCD Release manifests used by CI and installs
*-context.yaml           # Ordered KuboCD Context layers
```

Key paths:

- [`packages/system`](./packages/system): infrastructure and platform foundation packages.
- [`packages/services`](./packages/services): data and application service packages.
- [`releases`](./releases): release manifests that deploy selected package versions.
- [`10-platform-context.yaml`](./10-platform-context.yaml), [`20-provider-context.yaml`](./20-provider-context.yaml), [`30-service-context.yaml`](./30-service-context.yaml), [`99-examples-context.yaml`](./99-examples-context.yaml): ordered KuboCD context layers.

## Building Packages

### Basic Build Command

```bash
# Build a system package
kubocd package ./packages/system/cert-manager/cert-manager.yaml --ociRepoPrefix quay.io/okdp/platform-packages-v0.3

# Build a service package
kubocd package ./packages/services/superset/superset.yaml --ociRepoPrefix quay.io/okdp/platform-packages-v0.3
```

### Custom OCI Repository

```bash
# Using a different OCI registry
kubocd package ./packages/system/cert-manager/cert-manager.yaml --ociRepoPrefix myregistry.io/my-org/packages-v0.1

# Using a different prefix for packages
kubocd package ./packages/services/jupyterhub/jupyterhub.yaml --ociRepoPrefix harbor.company.com/okdp-prod
```

### Examples

```bash
# Build all system packages
for pkg in packages/system/*/; do
  kubocd package "$pkg"*.yaml --ociRepoPrefix quay.io/okdp/platform-packages-v0.3
done

# Build specific package
kubocd package ./packages/services/seaweedfs/seaweedfs.yaml --ociRepoPrefix quay.io/okdp/platform-packages-v0.3
```

### Build Output

Packages are pushed to: `{ociRepoPrefix}/{package-name}:{tag}`

Example: `quay.io/okdp/platform-packages-v0.3/superset:4.0.0-p02`

## GitHub CI and Publishing

The GitHub workflows share the reusable [`kubocd-package-template.yml`](./.github/workflows/kubocd-package-template.yml) workflow for both CI validation and publishing.

### CI Workflow

[`ci.yml`](./.github/workflows/ci.yml) runs on pushes, pull requests, and manual dispatch. It:

- reads the OCI package prefix from `10-platform-context.yaml`;
- builds every package manifest under `packages/` that contains `modules:`;
- pushes CI test packages to the repository-scoped GitHub Container Registry path;
- starts a Kind cluster;
- installs Flux and the KuboCD controller;
- applies every `*-context.yaml` file in sorted layer order;
- rewrites release package repositories to point at the CI registry and injects the CI pull secret;
- applies the manifests under [`releases`](./releases);
- waits until all KuboCD `Release` resources report `READY`, printing release, pod, PVC, event, and container log diagnostics on failure.

The KuboCD package CI job is skipped for fork pull requests because GitHub intentionally gives those runs a read-only token, which cannot push to GHCR.

### CI Registry

The `ci` workflow builds packages for integration tests and pushes them to the repository-scoped GitHub Container Registry path:

```text
ghcr.io/okdp/platform-packages/platform-packages-v0.3/{package-name}:{tag}
```

### Release Publishing

Published release packages continue to use the public repository from `10-platform-context.yaml`:

```text
quay.io/okdp/platform-packages-v0.3/{package-name}:{tag}
```

[`publish.yml`](./.github/workflows/publish.yml) can be dispatched manually and publishes packages to Quay using `REGISTRY_USERNAME` and `REGISTRY_ROBOT_TOKEN`. [`publish-on-merge.yml`](./.github/workflows/publish-on-merge.yml) triggers that publish workflow after a successful `ci` run on `main`, and [`release-please.yml`](./.github/workflows/release-please.yml) triggers it when Release Please creates a new release after a merged pull request.
