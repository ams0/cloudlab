# GitOps Manifests

This directory contains Kubernetes manifests managed by Flux CD.

## Structure

- `kustomization.yaml` - Main Kustomize configuration
- `namespace.yaml` - Applications namespace
- Add your application manifests here

## Usage

Flux monitors this directory and automatically applies changes to the cluster when you push to the main branch.

## Getting Started

1. Add your Kubernetes manifests to this directory
2. Update `kustomization.yaml` to include new resources
3. Commit and push to trigger deployment

Example deployment:
```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
  namespace: applications
spec:
  # ... your deployment spec
```