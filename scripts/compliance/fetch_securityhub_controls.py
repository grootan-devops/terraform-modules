#!/usr/bin/env python3
"""Build docs/compliance/data/securityhub-controls.json from the AWS Security Hub CSPM user guide.

The user guide publishes every page as Markdown (<page>.md). This script reads the controls
reference, every <service>-controls page and the standard pages, and records for each control:
title, severity, category, resource types, AWS Config rule, the standards it belongs to and the
framework requirement IDs from its "Related requirements" line.

It is a maintenance tool, not part of `make verify`: it needs network access. Re-run it when AWS
adds controls or standards, review the diff, and commit the JSON with the retrieval date.

Usage: python3 scripts/compliance/fetch_securityhub_controls.py [--cache DIR] [--output FILE]
"""

import argparse
import datetime
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

BASE = "https://docs.aws.amazon.com/securityhub/latest/userguide/"
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "docs" / "compliance" / "data" / "securityhub-controls.json"

# Standard pages whose control lists define membership. Key -> (page, display name, version).
STANDARD_PAGES = {
    "fsbp_v1_0_0": ("fsbp-standard", "AWS Foundational Security Best Practices", "1.0.0"),
    "tagging_v1_0_0": ("standards-tagging", "AWS Resource Tagging Standard", "1.0.0"),
    "ai_security_v1_0_0": ("standards-ai-security", "AI Security Best Practices", "1.0.0"),
    "cri_profile_v2_2": ("standards-reference-cri-profile", "CRI Profile", "2.2"),
    "nist_800_53_r5": ("standards-reference-nist-800-53", "NIST SP 800-53", "Revision 5"),
    "nist_800_171_r2": ("standards-reference-nist-800-171", "NIST SP 800-171", "Revision 2"),
    "control_tower_service_managed": ("service-managed-standard-aws-control-tower", "Service-Managed Standard: AWS Control Tower", "1.0.0"),
}

# "Related requirements" prefixes -> framework key.
REQUIREMENT_PREFIXES = [
    ("CIS AWS Foundations Benchmark v5.0.0/", "cis_v5_0_0"),
    ("CIS AWS Foundations Benchmark v3.0.0/", "cis_v3_0_0"),
    ("CIS AWS Foundations Benchmark v1.4.0/", "cis_v1_4_0"),
    ("CIS AWS Foundations Benchmark v1.2.0/", "cis_v1_2_0"),
    ("NIST.800-53.r5 ", "nist_800_53_r5"),
    ("NIST.800-171.r2 ", "nist_800_171_r2"),
    ("PCI DSS v3.2.1/", "pci_v3_2_1"),
    ("PCI DSS v4.0.1/", "pci_v4_0_1"),
    ("CRI Profile v2.2/", "cri_profile_v2_2"),
]

CONTROL_HEADING = re.compile(r"^## \[(?P<id>[A-Za-z0-9]+\.[0-9]+)\] (?P<title>.+)$", re.M)
CONTROL_LINK = re.compile(r"\[\[(?P<id>[A-Za-z0-9]+\.[0-9]+)\]")


def fetch(page, cache):
    path = cache / f"{page}.md" if cache else None
    if path and path.exists():
        return path.read_text()
    request = urllib.request.Request(BASE + page + ".md", headers={"User-Agent": "terraform-modules-compliance-fetch"})
    with urllib.request.urlopen(request, timeout=60) as response:
        text = response.read().decode("utf-8")
    if path:
        path.write_text(text)
    time.sleep(0.2)
    return text


def field(block, name):
    match = re.search(rf"\*\*{re.escape(name)}:\*\*\s*(.+)", block)
    return match.group(1).strip() if match else None


def parse_controls(text, page):
    controls = {}
    matches = list(CONTROL_HEADING.finditer(text))
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        block = text[match.end():end]
        requirements = {}
        related = field(block, "Related requirements") or ""
        for item in (part.strip() for part in related.split(",")):
            for prefix, key in REQUIREMENT_PREFIXES:
                if item.startswith(prefix):
                    requirements.setdefault(key, []).append(item[len(prefix):].strip())
                    break
        rule = field(block, "AWS Config rule")
        rule_match = re.search(r"\[([^\]]+)\]", rule or "")
        resource_types = re.findall(r"`([^`]+)`", field(block, "Resource type") or "")
        controls[match.group("id")] = {
            "id": match.group("id"),
            "title": match.group("title").strip(),
            "severity": field(block, "Severity"),
            "category": field(block, "Category"),
            "resource_types": resource_types,
            "config_rule": rule_match.group(1) if rule_match else (rule or None),
            "schedule": field(block, "Schedule type"),
            "requirements": requirements,
            "source": BASE + page + ".html#" + match.group("id").lower().replace(".", "-"),
        }
    return controls


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", type=Path, default=None, help="Directory for raw page copies (reused when present).")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    if args.cache:
        args.cache.mkdir(parents=True, exist_ok=True)

    reference = fetch("securityhub-controls-reference", args.cache)
    pages = sorted(set(re.findall(r"\(([a-z0-9-]+-controls)\.md", reference)))
    controls = {}
    for page in pages:
        controls.update(parse_controls(fetch(page, args.cache), page))

    standards = {}
    for key, (page, name, version) in STANDARD_PAGES.items():
        members = sorted(set(CONTROL_LINK.findall(fetch(page, args.cache))))
        standards[key] = {"name": name, "version": version, "source": BASE + page + ".html", "controls": members}
    # CIS, PCI DSS and NIST 800-171 membership also follows from the requirement IDs.
    for _, key in REQUIREMENT_PREFIXES:
        if key in standards:
            continue
        standards[key] = {
            "name": key, "version": key.split("_v")[-1] if "_v" in key else key,
            "source": BASE + "standards-reference.html",
            "controls": sorted(cid for cid, c in controls.items() if key in c["requirements"]),
        }
    for key, standard in standards.items():
        for cid in standard["controls"]:
            if cid in controls:
                controls[cid].setdefault("standards", []).append(key)
    for control in controls.values():
        control["standards"] = sorted(set(control.get("standards", [])))

    document = {
        "retrieved": datetime.date.today().isoformat(),
        "source": BASE + "securityhub-controls-reference.html",
        "note": "Generated by scripts/compliance/fetch_securityhub_controls.py. Security Hub CSPM findings are posture "
                "assessments, not certification of compliance with any framework.",
        "standards": standards,
        "controls": dict(sorted(controls.items(), key=lambda kv: (kv[0].split(".")[0], int(kv[0].split(".")[1])))),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2, sort_keys=False) + "\n")
    print(f"{len(controls)} controls, {len(standards)} standards -> {args.output.relative_to(ROOT)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
