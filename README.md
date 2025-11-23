# Finure Kubernetes Infrastructure repo

## Overview
This repository contains the Kubernetes infrastructure for Finure project. The project uses GitOps with Flux to set up and manage the Kubernetes infrastructure for the Finure platform. It includes Flux sources (Git), Flux Kustomizations, Helm Releases with cluster specific values, Kustomize with base & overlays for different environments and other Kubernetes manifests required to deploy required infrastructure, CI/CD & ML pipelines for Finure applications on a GKE cluster while following best practices for security, scalability, and maintainability.

## Prerequisites
- Kubernetes cluster bootstrapped ([Finure Terraform](https://github.com/finure/terraform))
- kubectl installed for interacting with the Kubernetes cluster
- Flux CLI installed for managing GitOps deployments

## Repository Structure

The repository has the following structure:
```
kubernetes/
├── .github/                     # Contains GitHub Actions workflows
├── apps/                        # Contains Flux resources to deploy Finure applications
├── clusters/                    # Contains Flux system configs & Kustomizations for various infra components & Finure apps
├── infra/                       # Contains Flux resources to deploy infra components 
└── README.md                    # Project documentation
```

## Infrastructure Components

The infrastructure includes the following components:
1. **Airflow:** Airflow with git-sync ([Finure Airflow Repo](https://github.com/finure/airflow)) for orchestrating data pipelines, managing datasets via GCS, triggering ML workflows via Argo and sending notifications to Slack
2. **Argo Events:** Event-driven automation to trigger ML pipeline using Argo Workflows based on successful Airflow data pipeline runs
3. **Argo Workflows:** Kubernetes-native workflow engine to run containerized ML training jobs on new datasets using model code in ([Finure AI Models Repo](https://github.com/finure/ai-models)) and store trained models in GCS
4. **Atlantis**: Automate Terraform workflows via PR triggered deployments with approval gate, to allow machine based parallel runs, custom workflows (eg security checks via Checkov), reduce deployment time, deployment conflicts, Terraform state drift/errors, human errors & improve security
5. **SOPS:** Manage and encrypt sensitive data in Git using SOPS 
6. **Cert-Manager:** Manages TLS certificates for secure communication
7. **External-DNS:** Automatically manages DNS records in Cloudflare for Finure applications
8. **Flux**: GitOps tool to automate Kubernetes deployments and manage cluster state, with automated Slack notifications on deployment status
9. **Istio:** Service mesh to manage microservices communication, security and observability & ingress traffic management, routing, failover, and load balancing
10. **Kiali:** Visualize and manage the Istio service mesh
11. **Jaeger:** Distributed tracing to monitor and troubleshoot microservices with Istio 
12. **Kafka:** Strimzi Kafka operator and Kafka cluster for scalable decoupled communication between Finure services
13. **Knative:** Works with Kserve to deploy and manage serverless ML model inference services
14. **Kserve:** Serves ML models for real-time predictions using custom-trained models. Scales to zero when not in use to save resources, runs on Knative for serverless deployments & management.
15. **Kyverno:** Kubernetes-native policy engine to enforce security, compliance and operational policies
16. **Metrics:** Prometheus for metrics and Grafana for visualization
17. **Logging:** Fluentbit as lightweight log forwarder, Loki with GCS as the backend and Grafana for query 
18. **Observability:** Beyla for auto instrumentation of app metrics and traces using eBPF, OpenTelemetry Collector for central pipeline and Signoz as the backend
19. **PostgreSQL:** Cloudnative PostgreSQL operator and PostgreSQL cluster for Finure infra apps such as SonarQube & Finure apps
20. **Reflector:** Replicates Kubernetes secrets across namespaces for easier management
21. **SonarQube:** Code quality and security analysis tool for continuous inspection of code
22. **Velero:** Backup and restore tool for Kubernetes cluster resources and persistent volumes, using GCS as the backup storage location
23. **Vault:** HashiCorp Vault for managing secrets and sensitive data securely, working with External Secrets Operator to sync secrets on the cluster & uses GCS as the storage backend
24. **External Secrets Operator:** Integrates with Vault to sync secrets into Kubernetes secrets for infra & Finure apps
25. **Tekton**: Dynamic & re-usable Kubernetes-native CI/CD pipeline tool to automate build, test and deployment workflows for Finure applications
26. **KEDA**: Kubernetes Event-Driven Autoscaling to scale Finure app-backend consumers based on Kafka lag
27. **Opencost:** Cost monitoring and optimization tool for Kubernetes clusters 
28. **GitHub Actions:** Self-hosted GitHub Actions runners to run GitHub workflows (more planned)
29. **Kubernetes Gateway API with Istio:** Manage ingress traffic for Finure applications using Kubernetes Gateway API with Istio controller
30. **Flagger with Istio:** Progressive delivery for Finure apps supporting canary and blue/green (A/B) deployments with traffic mirroring

## Tekton Pipeline

### Purpose
End-to-end CI/CD for Finure repos using Tekton

### Core Tekton Pieces
- **EventListener**: receives GitHub webhooks
- **Interceptor(s)**: filter by event/action/paths (e.g. `pull_request`, `opened` action in `feature/` branch for CI and `merged` action in non-feature branch for CD)
- **Trigger(s)**: link EventListener + Interceptor to TriggerBinding/Template
- **TriggerBinding**: maps webhook payload → params (repo, SHA, PR number, branch, etc)
- **TriggerTemplate**: renders `PipelineRun` with bound params and workspaces/secrets
- **Pipeline**: shared CI/CD pipeline referenced by TriggerTemplate
- **Tasks**: reusable steps (lint, scan, build, push, deploy, notify, etc) across CI/CD pipelines

### High-Level Flow
1. GitHub sends webhook → **EventListener**.  
2. **Interceptor** filters (PR opened/synced), extracts details
3. **TriggerBinding/Template** passes params (repo/org, ref, commit, PR metadata, image/tag, chart path)
4. Tekton creates a **PipelineRun** with required secrets/workspaces
5. Tasks run depending on CI vs CD and dependencies
6. Slack/GitHub notified of success/failure

### CI Stages (Pull Requests)
- Clone private repo (via PAT/SSH) 
- Lint code + Helm charts
- Security/Quality Scans:
  - **Checkov**: Helm chart misconfig/secrets
  - **Snyk**: dependency scan 
  - **SonarQube**: static analysis with custom quality gates
  - **Trivy (repo)**: IaC/dependency scan (optional)
- Report status to Slack + GitHub (merge blocked on failure)

### CD Stages (Main/Merge)
- SemVer: compute next version and create Git tag
- Builds multi-stage multi-arch container image with **Buildah**
- Push to **GitHub Container Registry (GHCR)**
- Image scan with **Trivy**
- Update Finure apps repo `k8s` folder Helm chart/app version to trigger Flux deployments
- Create a release in GitHub
- Blue/Green (A/B) progressive delivery using Flagger with Istio, with smoke and load tests (manifest in apps repos)
- Notify Slack + GitHub of success/failure  

### Secrets & Workspaces
Secrets are stored in Vault, synced to the cluster using External Secrets Operator and mounted as needed

### Policies
- **Push-based**: Triggered only via GitHub webhooks  
- **CI**: Runs on **PR open** and **feature branches**
- **CD**: Runs only on **merge with non-main**
- Merge blocked on failed CI checks

### Observability
- Tekton Dashboard/CLI for runs
- Logs available per step; Slack summary with commit/PR/version + failing checks

### Repos Involved
- **App Repo**: works with all Finure app repos (gateway, backend, seed job, frontend)
- **Manifests Repo**: K8s paths in each app repo includes Helm charts and Kubernetes components; updates trigger Flux deployments
- **Registry**: GHCR for container images

### Failure Handling
- Fast-fail on lint/misconfig
- Slack/GitHub alerts on failure

## ML Pipelines

### Purpose
End-to-end ML workflow from data ingestion to model training to deployment

### Core Components
- **GCS**: Centralized storage for datasets, model artifacts, and backups
- **Airflow**: Orchestrates data pipelines, manages datasets via GCS, triggers ML workflows via Argo Events and sends notifications to Slack
- **Argo Events**: Event-driven automation to trigger ML pipeline using Argo Workflows based on successful Airflow data pipeline runs
- **Argo Workflows**: Kubernetes-native workflow engine to run containerized ML training jobs on new datasets using model code in ([Finure AI Models Repo](https://github.com/Finure/ai-models)) and store trained models in GCS
- **KServe**: Serves ML models for real-time predictions using custom-trained models. Scales to zero when not in use to save resources, runs on Knative for serverless deployments & management.
- **Knative**: Works with Kserve to deploy and manage serverless ML model inference services

### High-Level Flow
1. **Data Ingestion**: Airflow DAG downloads dataset from Kaggle, validates, cleans, uploads the dataset to GCS, sends an event to Argo Events and notifies Slack
2. **Event Trigger**: Receives event from Airflow with the new dataset path, uses it as input to trigger Argo Workflow
3. **Model Training**: Argo Event triggers Argo Workflow to run ML training jobs on the new dataset using model code in ([Finure AI Models Repo](https://github.com/Finure/ai-models)) and stores newly trained models in GCS
4. **Model Deployment**: KServe monitors GCS for new models, automatically deploys them as serverless inference services on Knative, scales to zero when not in use to save resources
5. **Prediction**: Finure app backend consumes credit card application data from Kafka, sends it to KServe for real-time predictions using the deployed model and stores results in PostgreSQL
6. **Monitoring & Alerts**: Prometheus, Grafana and Jaeger monitor the entire ML pipeline, set up alerts for failures or performance issues

## Github Actions
The repository includes GitHub Actions workflows to automate the following tasks:
- **Validate:** Validates new infra changes such as k8 manifests, HelmReleases etc using custom scripts
- **Lint:** Lints the Github Actions workflows & YAML files
- **Label PRs:** Automatically labels pull requests based on the changes made

## Additional Information

This repository is intended to be used as part of the Finure project. While the infrastructure code can be adapted for other use cases, it is recommended to use it as part of the Finure platform for full functionality.