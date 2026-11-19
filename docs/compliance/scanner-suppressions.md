# Scanner suppression register

Trivy (github-ci-library `scan.yml`, the `iac-scan` job) and TFLint (github-ci-library `terraform.yml`, the
`terraform` job) run over every module in `.github/workflows/pr.yml`. A finding is fixed in code wherever the
provider and the service allow it. The rows below are the only exceptions. Each one is an inline comment on a single
resource or variable (`#trivy:ignore:<id>` or `# tflint-ignore: <rule>`),
never a repository-wide skip, and `tests/test_scanner_suppressions.py` fails the build when
an inline suppression is missing here, a row has no matching suppression in the code, or a
field is empty.

| File | Resource | Check | Reason | Justification | Remediation reference |
| --- | --- | --- | --- | --- | --- |
| `modules/aws/compute/ecr/main.tf` | `aws_ecr_repository.this` | `AVD-AWS-0033` | AES256 (ECR default encryption) is the deliberate default when no `kms` input is given. | The library default is the service's own encryption; images are never stored unencrypted, and `kms.create` or `kms.key_id` switches to SSE-KMS (inventory ECR.5 PARTIAL). | Set `kms = { create = true }` or `kms.key_id` for a customer managed key. |
| `modules/aws/compute/ecs/main.tf` | `module.security_group` | `AVD-AWS-0104` | Open egress (`security_group.egress_cidr_blocks` default `0.0.0.0/0`) lets tasks reach ECR, Secrets Manager and CloudWatch Logs without VPC endpoints. | Tasks without VPC endpoints cannot pull images or resolve secrets with narrower egress; the default is documented in the README and inventory (network PARTIAL). | Set `security_group.egress_cidr_blocks` and `egress_prefix_list_ids` to VPC endpoint and proxy ranges. |
| `modules/aws/compute/eks/main.tf` | `aws_eks_cluster.this` | `AVD-AWS-0039` | Without a `kms` input the cluster has no `encryption_config`; EKS encrypts all Kubernetes API data, secrets included, with an AWS owned key (1.28+). | The library default is the service's own encryption; `kms.create` or `kms.key_id` adds envelope encryption of secrets with a customer managed key. | Set `kms = { create = true }` or `kms.key_id`. |
| `modules/aws/network/alb/main.tf` | `aws_lb.this` | `AVD-AWS-0053` | The load balancer is internet-facing when the caller sets `internal = false`. | `internal` is required with no default, so exposure is always an explicit decision; internet-facing ALBs are a supported use case, the security group admits nothing until sources are listed and `0.0.0.0/0` is rejected on internal load balancers. | Set `internal = true` for internal workloads and list only the needed `security_group.ingress_*` sources. |
| `modules/aws/storage/s3/main.tf` | `aws_s3_bucket.this` | `AVD-AWS-0089` | Server access logging needs a separate SSE-S3 target bucket, so it cannot be on by default. | `access_logs` is opt-in and points at another bucket (for example `storage/log-bucket`); S3.9 is PARTIAL in the inventory. | Set `access_logs = { enabled = true, bucket = module.logs.name }`; <https://docs.aws.amazon.com/AmazonS3/latest/userguide/enable-server-access-logging.html> |

[Compliance documentation](README.md)
