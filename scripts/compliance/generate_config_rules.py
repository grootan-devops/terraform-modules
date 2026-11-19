"""Generate modules/aws/security/config/rules.tf from the AWS Config managed rule pages.

Maintenance tool (needs network access with --fetch); not part of `make verify`. Example:

  python3 scripts/compliance/generate_config_rules.py --fetch \
    --candidates docs/compliance/data/config-rule-candidates.json \
    --controls docs/compliance/data/securityhub-controls.json \
    --docs /tmp/config-rule-pages --regions /tmp/aws-regions.md \
    --out-tf modules/aws/security/config/rules.tf \
    --out-report /tmp/config-rules-report.json --out-readme /tmp/config-rules-readme.md

Run `terraform fmt` on rules.tf, review its diff and the report, then update the module README tables from --out-readme.

Inputs (all local after fetch.py has run):
  --candidates   config-rule-candidates.json (include / exclude_services_not_in_library)
  --docs         directory with <rule-name>.md pages from
                 https://docs.aws.amazon.com/config/latest/developerguide/<rule-name>.md
  --regions      aws-regions.md from
                 https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.md
  --controls     docs/compliance/data/securityhub-controls.json (repo, read-only)
Outputs:
  --out-tf       rules.tf (locals { managed_rules = { ... } })
  --out-report   JSON report (rules, dropped, excluded services, counts)
  --out-readme   Markdown fragment (rule table + excluded services)
"""

import argparse
import concurrent.futures
import json
import pathlib
import re
import subprocess
import sys
import unicodedata

RULE_PAGE = "https://docs.aws.amazon.com/config/latest/developerguide/{}.md"
REGIONS_PAGE = "https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.md"

LIBRARY_EXTRA_RULES = {
    "required-tags": "Library governance tags (Application, Environment, Name, ManagedBy) on every taggable resource",
    "cloudwatch-log-group-encrypted": "Library rule: every log group sets kms_key_id",
    "dynamodb-table-encrypted-kms": "Library rule: DynamoDB tables use a KMS key",
    "secretsmanager-using-cmk": "Library rule: secrets use a customer managed key",
}

LIBRARY_PRODUCED_RESOURCE_TYPES = {
    "AWS::RDS::DBSnapshot": "automated and final DB snapshots of database/rds/postgres",
}

TAG_KEYS = ["Application", "Environment", "Name", "ManagedBy"]

ELB17_POLICIES = [
    "ELBSecurityPolicy-TLS13-1-3-2021-06",
    "ELBSecurityPolicy-TLS13-1-3-FIPS-2023-04",
    "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09",
    "ELBSecurityPolicy-TLS13-1-3-PQ-2025-09",
    "ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09",
    "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09",
    "ELBSecurityPolicy-TLS13-1-2-RFC9151-FIPS-2023-07",
    "ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP1-FIPS-2023-07",
    "ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP2-FIPS-2023-07",
    "ELBSecurityPolicy-TLS13-1-3-RFC9151-FIPS-2023-07",
    "ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09",
    "ELBSecurityPolicy-TLS13-1-2-PQ-2025-09",
]

LAMBDA2_RUNTIMES = [
    "dotnet10", "java25", "java21", "java17", "java11", "java8.al2", "java17.al2023", "java11.al2023",
    "java8.al2023", "nodejs26.x", "nodejs24.x", "nodejs22.x", "python3.15", "python3.14", "python3.13",
    "python3.12", "python3.11", "ruby4.0", "ruby3.4", "ruby3.3",
]

EC2_19_PORTS = "20,21,22,23,25,110,135,143,445,1433,1434,3000,3306,3389,4333,5000,5432,5500,5601,8080,8088,8888,9200,9300"

PARAMETER_DEFAULTS = {
    "required-tags": {f"tag{i + 1}Key": key for i, key in enumerate(TAG_KEYS)},
    "access-keys-rotated": {"maxAccessKeyAge": "90"},
    "alb-desync-mode-check": {"desyncMode": "defensive,strictest"},
    "cloudfront-ssl-policy-check": {"securityPolicies": "TLSv1.2_2025,TLSv1.3_2025"},
    "cloudwatch-alarm-action-check": {
        "alarmActionRequired": "true",
        "insufficientDataActionRequired": "false",
        "okActionRequired": "false",
    },
    "cognito-user-pool-password-policy-check": {"minLength": "14"},
    "cw-loggroup-retention-period-check": {"MinRetentionTime": "365"},
    "db-instance-backup-enabled": {"backupRetentionMinimum": "7"},
    "ecs-fargate-latest-platform-version": {"latestLinuxVersion": "1.4.0", "latestWindowsVersion": "1.0.0"},
    "ecs-no-environment-secrets": {"secretKeys": "AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,ECS_ENGINE_AUTH_DATA"},
    "eks-cluster-log-enabled": {"logTypes": "audit"},
    "eks-cluster-supported-version": {"oldestVersionSupported": "1.34"},
    "eks-nodegroup-supported-version-check": {"oldestVersionSupported": "1.34"},
    "elasticache-redis-cluster-automatic-backup-check": {"snapshotRetentionPeriod": "7"},
    "elbv2-predefined-security-policy-ssl-check": {"sslPolicies": ",".join(ELB17_POLICIES)},
    "iam-customer-policy-blocked-kms-actions": {
        "blockedActionsPatterns": "kms:Decrypt,kms:ReEncryptFrom",
        "excludePermissionBoundaryPolicy": "true",
    },
    "iam-password-policy": {
        "RequireUppercaseCharacters": "true",
        "RequireLowercaseCharacters": "true",
        "RequireSymbols": "true",
        "RequireNumbers": "true",
        "MinimumPasswordLength": "14",
        "PasswordReusePrevention": "24",
        "MaxPasswordAge": "90",
    },
    "iam-policy-in-use": {"policyARN": "arn:${local.partition}:iam::aws:policy/AWSSupportAccess", "policyUsageType": "ANY"},
    "iam-policy-no-statements-with-admin-access": {"excludePermissionBoundaryPolicy": "true"},
    "iam-policy-no-statements-with-full-access": {"excludePermissionBoundaryPolicy": "true"},
    "iam-user-unused-credentials-check": {"maxCredentialUsageAge": "90"},
    "lambda-function-settings-check": {"runtime": ",".join(LAMBDA2_RUNTIMES)},
    "multi-region-cloudtrail-enabled": {"readWriteType": "ALL", "includeManagementEvents": "true"},
    "restricted-common-ports": {"blockedPorts": EC2_19_PORTS},
    "vpc-sg-open-only-to-authorized-ports": {"authorizedTcpPorts": "80,443"},
}

PARAMETER_SOURCES = {
    "required-tags": "library governance tags",
    "access-keys-rotated": "IAM.3",
    "alb-desync-mode-check": "ELB.12",
    "cloudfront-ssl-policy-check": "CloudFront.15",
    "cloudwatch-alarm-action-check": "CloudWatch.15",
    "cognito-user-pool-password-policy-check": "security/cognito default minimum_length",
    "cw-loggroup-retention-period-check": "CloudWatch.16",
    "db-instance-backup-enabled": "RDS.11",
    "ecs-fargate-latest-platform-version": "ECS.10",
    "ecs-no-environment-secrets": "ECS.8",
    "eks-cluster-log-enabled": "EKS.8",
    "eks-cluster-supported-version": "EKS.2",
    "eks-nodegroup-supported-version-check": "EKS.9",
    "elasticache-redis-cluster-automatic-backup-check": "database/elasticache/valkey default snapshot_retention_limit",
    "elbv2-predefined-security-policy-ssl-check": "ELB.17",
    "iam-customer-policy-blocked-kms-actions": "KMS.1",
    "iam-password-policy": "account baseline password policy (IAM.7, IAM.15, IAM.16)",
    "iam-policy-in-use": "IAM.18",
    "iam-policy-no-statements-with-admin-access": "IAM.1",
    "iam-policy-no-statements-with-full-access": "IAM.21",
    "iam-user-unused-credentials-check": "IAM.8",
    "lambda-function-settings-check": "Lambda.2",
    "multi-region-cloudtrail-enabled": "CloudTrail.1",
    "restricted-common-ports": "EC2.19",
    "vpc-sg-open-only-to-authorized-ports": "EC2.18 and the network/alb HTTP redirect listener",
}

SPLIT_RULES = {
    "vpc-endpoint-enabled": [
        ("vpc-endpoint-enabled-ec2", "EC2.10", "ec2"),
        ("vpc-endpoint-enabled-ecr-api", "EC2.55", "ecr.api"),
        ("vpc-endpoint-enabled-ecr-dkr", "EC2.56", "ecr.dkr"),
        ("vpc-endpoint-enabled-ssm", "EC2.57", "ssm"),
        ("vpc-endpoint-enabled-ssm-contacts", "EC2.58", "ssm-contacts"),
        ("vpc-endpoint-enabled-ssm-incidents", "EC2.60", "ssm-incidents"),
    ],
}

GLOBAL_CONTROL_PREFIXES = ("IAM.", "Account.")
GLOBAL_CONTROLS = {"KMS.1"}

EXTRA_REGIONS = {
    "AWS GovCloud (US-East)": "us-gov-east-1",
    "AWS GovCloud (US-West)": "us-gov-west-1",
    "China (Beijing)": "cn-north-1",
    "China (Ningxia)": "cn-northwest-1",
}

AREA_RULES = [
    ("tagging", r"tagged$|^required-tags$"),
    ("secrets", r"^secretsmanager-(rotation|scheduled|secret-periodic|secret-unused)|ecs-no-environment-secrets"),
    ("detection", r"^guardduty-|^inspector-"),
    ("log_retention", r"retention-period-check"),
    ("backup", r"backup|pitr"),
    ("deletion_protection", r"deletion-protection|default-lock|mfa-delete"),
    ("encryption_in_transit", r"in-transit|ssl|tls|https|traffic-to-origin|sni|custom-ssl|listener-encryption|protocol-encrypted|deprecated-ssl"),
    ("encryption_at_rest", r"encrypt|kms|cmk|ebs-encryption"),
    ("public_access", r"public|no-public|not-public|endpoint-no-public|igw-check|auto-assign-public"),
    ("logging", r"logging|log-enabled|logs|log-configuration|cloudwatch-logs|xray|cloudtrail|cloud-trail|data-event|accesslogs|log-file-validation|container-insights|enhanced-monitoring"),
    ("monitoring", r"alarm"),
    ("iam", r"iam|mfa|password|access-keys|root-account|admin|user-identity|root-directory|non-root|non-admin|nonprivileged|readonly|pid-mode|imdsv2|policy-attached|auth"),
    ("versioning", r"versioning|version-lifecycle"),
    ("network", r"sg-|security-group|ssh|ports|nacl|vpc|subnet|eip|waf|multiple-az|multi-az|eni|desync|invalid-header|network-mode|healthcheck|failover|origin|endpoint"),
]


def fetch(url, target):
    target = pathlib.Path(target)
    if target.exists() and target.stat().st_size > 0:
        return "cached"
    tmp = target.with_suffix(target.suffix + ".tmp")
    result = subprocess.run(
        ["curl", "-sL", "--max-time", "60", "-o", str(tmp), "-w", "%{http_code}", url],
        capture_output=True,
        text=True,
    )
    if result.stdout.strip() == "200" and tmp.exists() and tmp.stat().st_size > 0:
        tmp.rename(target)
        return "ok"
    tmp.unlink(missing_ok=True)
    return f"http {result.stdout.strip()}"


def fetch_all(names, docs_dir, regions_page):
    docs_dir = pathlib.Path(docs_dir)
    docs_dir.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda n: (n, fetch(RULE_PAGE.format(n), docs_dir / f"{n}.md")), names))
    failed = [(n, s) for n, s in results if s not in ("ok", "cached")]
    for name, status in failed:
        print(f"FETCH FAILED {name}: {status}")
    status = fetch(REGIONS_PAGE, regions_page)
    if status not in ("ok", "cached"):
        raise SystemExit(f"cannot fetch {REGIONS_PAGE}: {status}")


SERVICE_PREFIXES = [
    ("acm-pca", "PCA"), ("acmpca", "PCA"), ("appconfig", "AppConfig"), ("appflow", "AppFlow"), ("appsync", "AppSync"),
    ("aurora", "RDS"), ("rds-aurora", "RDS"), ("rds-cluster", "RDS"), ("rds-snapshot", "RDS"),
    ("autoscaling-launch", "AutoScaling"), ("beanstalk", "ElasticBeanstalk"), ("elastic-beanstalk", "ElasticBeanstalk"),
    ("cassandra", "Keyspaces"), ("codebuild", "CodeBuild"), ("codeguru", "CodeGuru"), ("customerprofiles", "CustomerProfiles"),
    ("dax", "DynamoDB"), ("ec2-", "EC2"), ("vpc-vpn", "EC2"), ("elasticsearch", "ES"), ("frauddetector", "FraudDetector"),
    ("global-endpoint", "EventBridge"), ("iotsitewise", "IoTSiteWise"), ("iottwinmaker", "IoTTwinMaker"),
    ("iotwireless", "IoTWireless"), ("ivs", "IVS"), ("kinesis-firehose", "DataFirehose"), ("macie", "Macie"), ("mq-", "MQ"),
    ("neptune", "Neptune"), ("opensearch", "Opensearch"), ("route53", "Route53"), ("waf", "WAF"), ("workspaces", "WorkSpaces"),
]

SERVICE_NOTES = {
    "APIGateway": "HTTP and WebSocket APIs (API Gateway v2) and custom domain names",
    "AutoScaling": "launch configurations (the library uses launch templates)",
    "CloudTrail": "CloudTrail Lake event data stores",
    "Cognito": "identity pools",
    "DynamoDB": "DynamoDB Accelerator (DAX) clusters",
    "EC2": "Client VPN, Site-to-Site VPN, Transit Gateway, traffic mirroring, prefix lists, Spot Fleet, standalone network interfaces, the EBS snapshot block-public-access setting",
    "EventBridge": "global endpoints",
    "ECS": "capacity providers",
    "ELB": "Classic Load Balancers",
    "KMS": "IAM inline policies (the library attaches customer managed policies)",
    "RDS": "Aurora and Multi-AZ DB clusters (DB instance snapshots are covered)",
    "S3": "S3 access points and directory buckets",
    "SSM": "Systems Manager managed EC2 instances",
    "WAF": "AWS WAF Classic resources and WAFv2 rule groups",
}


def catalog_rule(control):
    return (control.get("config_rule") or "").strip().strip("`").strip()


def library_produced_rules(candidates, controls_catalog):
    produced = {}
    for name in candidates["exclude_services_not_in_library"]:
        controls = sorted(
            cid for cid, c in controls_catalog.items()
            if catalog_rule(c) == name and any(t.strip() in LIBRARY_PRODUCED_RESOURCE_TYPES for t in c.get("resource_types", []))
        )
        if controls:
            produced[name] = controls
    return produced


def service_for(name, controls_catalog):
    canonical = {service.lower(): service for service in SERVICE_NOTES}
    services = sorted({cid.split(".")[0] for cid, c in controls_catalog.items() if catalog_rule(c) == name})
    if services:
        return canonical.get(services[0].lower(), services[0])
    for prefix, service in SERVICE_PREFIXES:
        if name.startswith(prefix):
            return service
    return "Other"


def clean_markdown(text):
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = text.replace("\\_", "_").replace("\\*", "*").replace("`", "")
    text = text.replace("‘", "'").replace("’", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", text).strip()


def normalise_region_name(name):
    name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    name = re.sub(r"\s+Regions?$", "", name.strip())
    return name.strip()


def load_region_map(path):
    mapping = dict(EXTRA_REGIONS)
    for line in pathlib.Path(path).read_text().splitlines():
        match = re.match(r"^\|\s*([a-z]{2}(?:-[a-z]+)+-\d+)\s*\|\s*([^|]+?)\s*\|", line)
        if match:
            mapping[normalise_region_name(match.group(2))] = match.group(1)
    return mapping


def parse_region_line(line, region_map, rule):
    value = re.sub(r"\s+Regions?\s*$", "", line.strip())
    if value.startswith("All supported AWS regions except"):
        names = value[len("All supported AWS regions except"):]
        mode = "except"
    elif value.startswith("Only available in"):
        names = value[len("Only available in"):]
        mode = "only"
    elif value.startswith("All supported AWS regions"):
        return [], []
    else:
        raise SystemExit(f"{rule}: unknown AWS Region line: {line}")
    codes = []
    for name in names.split(","):
        normalised = normalise_region_name(name)
        if not normalised:
            continue
        if normalised not in region_map:
            raise SystemExit(f"{rule}: unknown Region name {normalised!r}")
        codes.append(region_map[normalised])
    codes = sorted(set(codes))
    return (codes, []) if mode == "only" else ([], codes)


def parse_page(name, text, region_map):
    def field(label):
        match = re.search(r"^\*\*" + re.escape(label) + r":\*\*\s*(.+?)\s*$", text, re.M)
        return match.group(1) if match else None

    identifier = field("Identifier")
    if identifier is None:
        return None
    identifier = identifier.replace("\\_", "_").strip()
    resource_types = [t.strip() for t in (field("Resource Types") or "").split(",") if t.strip()]
    trigger = (field("Trigger type") or "").strip()
    only_regions, except_regions = parse_region_line(field("AWS Region") or "", region_map, name)

    params = {}
    block = re.search(r"^\*\*Parameters:\*\*\s*\n(.*?)(?=^## |^\*\*Proactive|\Z)", text, re.S | re.M)
    if block:
        lines = block.group(1).splitlines()
        for index, line in enumerate(lines):
            match = re.match(r"^(\w+?)( \(Optional\))?Type: (\w+)(?:Default: (.*?))?\s*$", line)
            if match:
                description = lines[index + 1].strip() if index + 1 < len(lines) else ""
                params[match.group(1)] = {
                    "optional": bool(match.group(2)),
                    "type": match.group(3),
                    "default": (match.group(4) or "").strip() or None,
                    "description": clean_markdown(description),
                }

    summary = ""
    for paragraph in re.split(r"\n\s*\n", text):
        paragraph = paragraph.strip()
        if not paragraph or paragraph.startswith(("#", "<a name", "**")):
            continue
        summary = clean_markdown(paragraph)
        break

    deprecated = bool(re.search(r"\bdeprecated\b", text[:2000], re.I)) and "deprecated-ssl" not in name
    return {
        "identifier": identifier,
        "resource_types": resource_types,
        "trigger": trigger,
        "only_regions": only_regions,
        "except_regions": except_regions,
        "parameters": params,
        "summary": summary,
        "deprecated": deprecated,
    }


def first_sentence(text):
    match = re.match(r"(.+?\.)(\s|$)", text)
    return match.group(1) if match else text


def make_description(controls, summary, extra):
    prefix = ", ".join(controls) + ": " if controls else "Library baseline: "
    body = first_sentence(summary) if summary else extra
    description = prefix + body
    if len(description) > 256:
        description = description[:252].rsplit(" ", 1)[0] + " ..."
    return description


AREA_OVERRIDES = {
    "cloudfront-accesslogs-enabled": "logging",
    "iam-customer-policy-blocked-kms-actions": "iam",
    "kms-key-policy-no-public-access": "public_access",
    "vpc-sg-open-only-to-authorized-ports": "network",
    "backup-recovery-point-encrypted": "encryption_at_rest",
    "rds-enhanced-monitoring-enabled": "monitoring",
    "ecs-container-insights-enabled": "monitoring",
    "s3-bucket-acl-prohibited": "iam",
    "s3-version-lifecycle-policy-check": "versioning",
    "s3-event-notifications-enabled": "monitoring",
}


def area_for(key):
    if key in AREA_OVERRIDES:
        return AREA_OVERRIDES[key]
    for area, pattern in AREA_RULES:
        if re.search(pattern, key):
            return area
    return "governance"


def hcl_string(value):
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("%{", "%%{")
    escaped = re.sub(r"\$\{(?!local\.partition\})", "$${", escaped)
    return f'"{escaped}"'


def hcl_list(values):
    return "[" + ", ".join(hcl_string(v) for v in values) + "]"


def hcl_map(values):
    if not values:
        return "{}"
    parts = []
    for key, value in values.items():
        name = key if re.match(r"^[A-Za-z_][A-Za-z0-9_-]*$", key) else hcl_string(key)
        parts.append(f"{name} = {hcl_string(value)}")
    return "{ " + ", ".join(parts) + " }"


def build(args):
    candidates = json.loads(pathlib.Path(args.candidates).read_text())
    controls_catalog = json.loads(pathlib.Path(args.controls).read_text())["controls"]
    region_map = load_region_map(args.regions)
    docs = pathlib.Path(args.docs)

    produced = library_produced_rules(candidates, controls_catalog)
    names = list(candidates["include"]) + list(produced) + list(LIBRARY_EXTRA_RULES)
    rules = {}
    dropped = []
    for name in names:
        page = docs / f"{name}.md"
        if not page.exists():
            dropped.append({"rule": name, "reason": "no AWS Config managed rule page"})
            continue
        parsed = parse_page(name, page.read_text(), region_map)
        if parsed is None:
            dropped.append({"rule": name, "reason": "page has no managed rule identifier"})
            continue
        if parsed["deprecated"]:
            dropped.append({"rule": name, "reason": "rule page marks the rule deprecated"})
            continue

        controls = candidates["include"].get(name, {}).get("controls", produced.get(name, []))
        unknown_controls = [c for c in controls if c not in controls_catalog]
        if unknown_controls:
            raise SystemExit(f"{name}: unknown Security Hub controls {unknown_controls}")

        defaults = dict(PARAMETER_DEFAULTS.get(name, {}))
        if "requiredKeyTags" in parsed["parameters"]:
            defaults["requiredKeyTags"] = ",".join(TAG_KEYS)

        unknown = [p for p in defaults if p not in parsed["parameters"]]
        if unknown:
            raise SystemExit(f"{name}: default parameters {unknown} are not on the rule page")

        split_parameters = {"serviceNames"} if name in SPLIT_RULES else set()
        missing = [
            p for p, meta in parsed["parameters"].items()
            if not meta["optional"] and p not in defaults and p not in split_parameters and meta["default"] is None
        ]
        if missing:
            dropped.append({"rule": name, "reason": f"required parameter(s) {', '.join(missing)} have no sensible library default"})
            continue
        for p, meta in parsed["parameters"].items():
            if not meta["optional"] and p not in defaults:
                defaults[p] = meta["default"]

        change = "Configuration changes" in parsed["trigger"]
        periodic = "Periodic" in parsed["trigger"]
        if not (change or periodic):
            raise SystemExit(f"{name}: unknown trigger {parsed['trigger']!r}")
        scope = [t for t in parsed["resource_types"] if t != "AWS::::Account"] if change else []
        if change and not scope:
            raise SystemExit(f"{name}: change-triggered rule without resource types")
        if len(scope) > 100:
            raise SystemExit(f"{name}: more than 100 resource types in scope")
        frequency = "TwentyFour_Hours" if periodic and not change else None
        is_global = bool(controls) and all(c.startswith(GLOBAL_CONTROL_PREFIXES) or c in GLOBAL_CONTROLS for c in controls)

        variants = SPLIT_RULES.get(name, [(name, None, None)])
        for key, only_control, service in variants:
            rule_controls = [only_control] if only_control else controls
            rule_params = dict(defaults)
            if service:
                rule_params["serviceNames"] = service
            encoded = json.dumps(rule_params, separators=(",", ":"))
            if len(encoded) > 1024:
                raise SystemExit(f"{key}: input parameters exceed 1024 characters")
            rules[key] = {
                "rule_name": name,
                "identifier": parsed["identifier"],
                "description": make_description(rule_controls, parsed["summary"], LIBRARY_EXTRA_RULES.get(name, "")),
                "controls": rule_controls,
                "trigger": "Configuration changes and Periodic" if change and periodic else ("Periodic" if periodic else "Configuration changes"),
                "global": is_global,
                "input_parameters": rule_params,
                "maximum_execution_frequency": frequency,
                "resource_types_scope": scope,
                "only_regions": parsed["only_regions"],
                "except_regions": parsed["except_regions"],
                "area": area_for(key),
                "parameter_source": PARAMETER_SOURCES.get(name, "requiredKeyTags = library governance tags" if "requiredKeyTags" in rule_params else ""),
                "library_extra": name in LIBRARY_EXTRA_RULES,
                "library_produced": name in produced,
            }

    excluded = {}
    for name in candidates["exclude_services_not_in_library"]:
        if name in produced:
            continue
        excluded.setdefault(service_for(name, controls_catalog), []).append(name)

    return rules, dropped, excluded, produced


def render_tf(rules):
    lines = ["locals {", "  managed_rules = {"]
    for key in sorted(rules):
        rule = rules[key]
        lines.append(f"    {hcl_string(key)} = {{")
        lines.append(f"      identifier = {hcl_string(rule['identifier'])}")
        lines.append(f"      description = {hcl_string(rule['description'])}")
        lines.append(f"      controls = {hcl_list(rule['controls'])}")
        lines.append(f"      trigger = {hcl_string(rule['trigger'])}")
        lines.append(f"      global = {'true' if rule['global'] else 'false'}")
        lines.append(f"      input_parameters = {hcl_map(rule['input_parameters'])}")
        frequency = hcl_string(rule["maximum_execution_frequency"]) if rule["maximum_execution_frequency"] else "null"
        lines.append(f"      maximum_execution_frequency = {frequency}")
        lines.append(f"      resource_types_scope = {hcl_list(rule['resource_types_scope'])}")
        lines.append(f"      only_regions = {hcl_list(rule['only_regions'])}")
        lines.append(f"      except_regions = {hcl_list(rule['except_regions'])}")
        lines.append("    }")
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def markdown_escape(value):
    return value.replace("|", "\\|")


def render_readme(rules, dropped, excluded):
    out = []
    out.append("| Rule key | Identifier | Security Hub controls | Trigger | Placement | Default parameters |")
    out.append("| --- | --- | --- | --- | --- | --- |")
    for key in sorted(rules):
        rule = rules[key]
        controls = ", ".join(rule["controls"]) if rule["controls"] else "- (library rule)"
        trigger = {"Configuration changes": "Change", "Periodic": "Periodic (24 h)", "Configuration changes and Periodic": "Change and periodic"}[rule["trigger"]]
        if rule["global"]:
            placement = "Global Region only"
        elif rule["only_regions"]:
            placement = "Only " + ", ".join(rule["only_regions"])
        elif rule["except_regions"]:
            placement = f"Not in {len(rule['except_regions'])} Regions"
        else:
            placement = "Every Region"
        params = rule["input_parameters"]
        if params:
            rendered = []
            for name, value in params.items():
                value = value.replace("${local.partition}", "<partition>")
                if len(value) > 60:
                    value = value[:57] + "..."
                rendered.append(f"`{name}={value}`")
            param_text = ", ".join(rendered)
        else:
            param_text = "-"
        out.append(f"| `{key}` | `{rule['identifier']}` | {controls} | {trigger} | {placement} | {markdown_escape(param_text)} |")
    out.append("")
    out.append("EXCLUDED")
    out.append("| Service | Not created by any module | Rules not deployed |")
    out.append("| --- | --- | --- |")
    for service in sorted(excluded, key=str.lower):
        note = SERVICE_NOTES.get(service, "the whole service")
        out.append(f"| {service} | {note} | {', '.join('`' + r + '`' for r in sorted(excluded[service]))} |")
    out.append("")
    out.append("DROPPED")
    for item in dropped:
        out.append(f"- `{item['rule']}`: {item['reason']}")
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidates", required=True)
    parser.add_argument("--docs", required=True)
    parser.add_argument("--regions", required=True)
    parser.add_argument("--controls", required=True)
    parser.add_argument("--out-tf", required=True)
    parser.add_argument("--out-report", required=True)
    parser.add_argument("--out-readme", required=True)
    parser.add_argument("--fetch", action="store_true", help="download missing rule pages and the Regions page first")
    args = parser.parse_args()

    if args.fetch:
        candidates = json.loads(pathlib.Path(args.candidates).read_text())
        controls_catalog = json.loads(pathlib.Path(args.controls).read_text())["controls"]
        extra = list(library_produced_rules(candidates, controls_catalog)) + list(LIBRARY_EXTRA_RULES)
        fetch_all(list(candidates["include"]) + extra, args.docs, args.regions)

    rules, dropped, excluded, produced = build(args)
    pathlib.Path(args.out_tf).write_text(render_tf(rules))
    pathlib.Path(args.out_readme).write_text(render_readme(rules, dropped, excluded))
    report = {
        "rule_count": len(rules),
        "rule_names_included": len(json.loads(pathlib.Path(args.candidates).read_text())["include"]),
        "dropped": dropped,
        "library_produced": produced,
        "excluded_count": sum(len(v) for v in excluded.values()),
        "excluded": excluded,
        "periodic": sorted(k for k, r in rules.items() if r["trigger"] == "Periodic"),
        "change": sorted(k for k, r in rules.items() if r["trigger"] == "Configuration changes"),
        "hybrid": sorted(k for k, r in rules.items() if r["trigger"] == "Configuration changes and Periodic"),
        "global": sorted(k for k, r in rules.items() if r["global"]),
        "rules": rules,
    }
    pathlib.Path(args.out_report).write_text(json.dumps(report, indent=1))
    print(f"rules={len(rules)} dropped={len(dropped)} excluded={report['excluded_count']} "
          f"periodic={len(report['periodic'])} change={len(report['change'])} hybrid={len(report['hybrid'])} global={len(report['global'])}")
    for item in dropped:
        print("DROPPED", item["rule"], "-", item["reason"])


if __name__ == "__main__":
    sys.exit(main())
