# Design Decisions

## Terraform Refactoring
- **Modularity**: Used locals and `for_each` loops to define environments and services centrally, eliminating duplication. This makes adding/removing services or environments (e.g., staging) a simple update to the maps, without touching resource blocks.
- **Abstractions**: Environments are mapped with Vault addresses, tokens, and networks. Services include shared secret data. This promotes reusability and reduces errors.
- **Simplicity**: Avoided over-engineering by keeping everything in one file; loops handle scaling without external modules.
- **Staging Environment**: Added as a third environment, replicating dev/prod with unique Vault port (8401) and token for isolation.

## Docker Compose Updates
- **Staging Support**: Added `vault-staging` service and `staging` network to mirror existing environments, ensuring consistent provisioning.

# CI/CD Integration

This setup integrates into CI/CD pipelines as follows:
- **Provisioning**: Run `vagrant up` in CI to build images, start Docker Compose, and apply Terraform. Use tools like GitHub Actions or Jenkins to automate.
- **Terraform Commands**: In CI, execute `terraform init`, `terraform plan`, and `terraform apply` in the `tf/` directory. Pass variables (e.g., Vault tokens) via environment secrets.
- **Testing**: After apply, run integration tests (e.g., curl services to verify Vault secrets retrieval). Destroy resources post-test with `terraform destroy`.
- **Version Control**: Store Terraform state in a remote backend (e.g., S3) for team collaboration. Use locking to prevent concurrent applies.
- **Automation Example** (GitHub Actions snippet):
  ```yaml
  - name: Provision Infrastructure
    run: |
      vagrant up
      cd tf && terraform apply -auto-approve

# Production Considerations
- **Security**: Hardcoded Vault tokens are placeholders; in production, use Vault's auto-unseal with KMS (e.g., AWS KMS) and inject tokens via CI secrets. Enable TLS for Vault communications.
- **Scalability**: For larger deployments, consider Terraform modules for environments or Kubernetes for service orchestration. Monitor resource usage (e.g., via Prometheus) to scale VMs.
- **State Management**: Use remote state with locking to avoid corruption. Backup Vault data regularly.
- **Networking**: In cloud (e.g., AWS), replace local Docker networks with VPCs and security groups. Use load balancers for frontend services.
- **Monitoring/Logging**: Integrate with ELK stack or CloudWatch for logs. Set up alerts for Vault/service failures.
- **Compliance**: Ensure secrets rotation and audit logs meet regulatory requirements (e.g., GDPR, PCI).
- **Cost/Performance**: Use spot instances for staging. Optimize Docker images for size to reduce startup time.