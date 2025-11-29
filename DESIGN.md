# Design Decisions and Documentation

## Design Decisions
The original `tf/main.tf` was monolithic, with duplicated code for each environment and service, making it hard to maintain as the company grows. To address this, I refactored the code into a reusable Terraform module (`tf/modules/environment/main.tf`) that encapsulates environment-specific resources (Vault audit, auth, secrets, policies, endpoints, Docker networks, and containers).

### Key Changes
- **Modular Structure**: The module takes variables for environment, Vault details, services, and frontend image/port. This allows dynamic creation of resources using `for_each` loops, reducing duplication.
- **Environment Segregation**: Each environment (development, staging, production) is instantiated as a separate module call in `tf/main.tf`, ensuring isolation.
- **Service Flexibility**: Services are defined in `locals` as a map, making it easy to add/remove services by updating the map and module variables.
- **Version Control**: Kept existing service versions (e.g., nginx images) and ensured staging mirrors development/production structure.
- **No External Tools**: Used plain Terraform only, as required.
- **Staging Environment Creation**: To add staging, I added a new module call in `tf/main.tf` for the staging environment, using the same module source as dev and prod. Files changed: `tf/main.tf` (added module "staging" block with vars for Vault addr/token, services, and frontend image/port), and `docker-compose.yml` (added vault-staging service with network, image, ports, and token). No changes to the module itself, as it dynamically handles environments via variables. This ensured staging runs all services with unique ports/networks/Vault instances.

## CI/CD Pipeline Integration
This Terraform setup integrates with GitHub Actions for automated deployment via Git workflows, with adaptations for cloud environments (e.g., AWS or Azure) by replacing local Docker resources with cloud-native services. The following lists the considerations, and some options based on using GitHub Actions, but similarly supported by Azure DevOps Pipelines.

- **Pipeline Structure**: Use a `.github/workflows/deploy.yml` file with jobs for build, test, plan, and deploy. Trigger on pushes to main branch or pull requests.
- **Environment Handling**: Use GitHub environments for each env (e.g., dev, staging, prod). Pass env-specific vars like Vault addresses via workflow inputs or secrets.
- **Automation**:
  - Local testing: Use Vagrant for dev (as in this setup).
  - Cloud deployment: Run Terraform commands in GitHub-hosted runners. Use actions like `hashicorp/setup-terraform` for init, validate, plan, and apply.
  - Approval Gates: Add manual approvals for production via `environment` protection rules.
- **Variables and Sensitive Information**:
  - Store non-sensitive vars (e.g., env names) in workflow YAML or repository variables.
  - Handle sensitive data (Vault tokens, cloud keys) via GitHub Secrets: Reference as `${{ secrets.VAULT_TOKEN }}` in YAML. Use environment secrets for per-env overrides.
  - Runtime vars: Override Terraform vars via `terraform plan -var-file=env.tfvars` in steps.
- **State Management**: Use HashiCorp Cloud Platform (HCP) as the remote backend for state files, configured in `tf/main.tf` (e.g., `backend "remote" { organization = "your-org" workspaces { name = "env-workspace" } }`). GitHub Actions authenticates via `TF_API_TOKEN` secret, enabling team collaboration and avoiding local state issues. Other alternatives to HCP would be cloud storage services, like AWS S3 Buckets.
- **Testing**: Add steps for `terraform validate` and custom scripts for integration tests (e.g., check Vault connectivity).
- **Deployment Flow**: Code Push → Build/Test → Terraform Plan (with artifact upload) → Approval → Apply → Post-Deploy Verification.
- **Cloud Adaptations**:
  - **Core Reuse**: Vault resources (audit, auth, secrets, policies, endpoints) remain unchanged, as Vault can be deployed on EC2 (AWS), VMs (Azure), or GCE instances (GCP).
  - **Docker Replacement**: Replace `docker_container` and `docker_network` with:
    - AWS: `aws_ecs_service`, `aws_ecs_task_definition`, and `aws_vpc` subnets for container orchestration.
    - Azure: `azurerm_kubernetes_cluster` (AKS) or `azurerm_container_group`, and Azure VNets.
    - GCP: `google_cloud_run_service` or `google_container_cluster` (GKE), and VPC networks/subnets.

This ensures secure, automated IaC with GitHub Actions handling variables and secrets natively.

## Production Considerations
Beyond this task, for real production:
- **State Management**: Use remote state (e.g., Terraform Cloud) to avoid local state issues and enable team collaboration.
- **Security**: Enable Vault TLS, use IAM roles for access, and rotate tokens regularly. Implement least-privilege policies.
- **Monitoring/Logging**: Add CloudWatch or ELK for container logs; monitor Vault with metrics.
- **Disaster Recovery**: Backup Vault data, use multi-region deployments, and implement rollback strategies.
- **Compliance**: Follow company policies or imposed compliance standards for encryption at rest/transit, or data handling. Utilize audit logs for all changes.
- **Cost Optimization**: Use spot instances, monitor resource usage, and clean up unused resources. Make use of FinOps tools for cost reporting and alerts.
- **CI/CD Enhancements**: Add blue-green deployments, canary releases, and automated rollbacks on failures.
- **Multi-Cloud Support**: To accommodate AWS, Azure, GCP with dev/staging/prod environments using the modular structure:
  - **High-Level Structure**: Create cloud-specific sub-modules (e.g., `modules/aws/environment`, `modules/azure/environment`, `modules/gcp/environment`) that extend the base `modules/environment/main.tf`. Use conditional logic (e.g., `if var.cloud == "aws"`) or separate module calls in `tf/main.tf` for each cloud.
  - **Environment Handling**: Use Terraform workspaces in HCP (one per env per cloud, e.g., `aws-prod`, `azure-dev`) or variable maps for env-specific configs. Alternative could be variable handling within CI/CD pipeline platform - GitHub Actions, Azure DevOps Pipelines.
  - **Key Changes**: In each cloud module, replace Docker resources with provider-specific ones (as above). Add cloud providers (e.g., `aws`, `azurerm`, `google`) and resources like VPCs, IAM roles, and container services. Reuse Vault configs by deploying Vault on cloud instances. Update `locals` in `tf/main.tf` to include cloud vars (e.g., `var.cloud = "aws"`).
  - **Example**: For AWS prod, call `module "aws-prod" { source = "./modules/aws/environment" cloud = "aws" environment = "production" ... }`. This allows 3 clouds × 3 envs = 9 combinations with minimal duplication.