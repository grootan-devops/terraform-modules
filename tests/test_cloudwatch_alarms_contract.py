"""CloudWatch alarm notification contract.

The cloudwatch-alarms module never creates a notification destination and keeps every alarm
action off unless the caller opts in through var.notifications; the only action it can set is a
caller-supplied SNS topic ARN. Destinations live in the alarm-routing module, which creates
KMS-encrypted SNS topics, topic policies and email/HTTPS subscriptions and nothing else; its only
child modules are the core building blocks, and every topic takes the module key (never aws/sns).
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OBSERVABILITY = ROOT / "modules" / "aws" / "observability"
ALARMS = OBSERVABILITY / "cloudwatch-alarms"
ROUTING = OBSERVABILITY / "alarm-routing"

RESOURCE = re.compile(r'^\s*resource\s+"([a-z0-9_]+)"\s+"[^"]+"\s*\{', re.M)
MODULE_SOURCE = re.compile(r'^module\s+"[^"]+"\s*\{[^}]*?^\s*source\s*=\s*"([^"]+)"', re.M | re.S)
VARIABLE = re.compile(r'^\s*variable\s+"([a-z0-9_]+)"\s*\{', re.M)
ALARMS_ALLOWED_TYPES = {"aws_cloudwatch_metric_alarm", "aws_cloudwatch_log_metric_filter"}
ROUTING_ALLOWED_TYPES = {"aws_sns_topic", "aws_sns_topic_policy", "aws_sns_topic_subscription"}
ALARMS_ALLOWED_MODULES = {"../../core/naming"}
ROUTING_ALLOWED_MODULES = {"../../core/naming", "../../core/encryption", "../../core/policy-document"}
# Resource types that create or wire a destination other than an SNS topic subscription.
FOREIGN_DESTINATIONS = re.compile(
    r'resource\s+"(aws_cloudwatch_event_[a-z_]+|aws_chatbot_[a-z_]+|aws_lambda_[a-z_]+|aws_notifications_[a-z_]+|'
    r'aws_ses_[a-z_]+|aws_sqs_queue[a-z_]*|aws_cloudwatch_composite_alarm|aws_pipes_pipe|aws_scheduler_[a-z_]+)"'
)

# Action arguments: off (empty) unless var.notifications enables them.
ACTIONS_ENABLED = re.compile(r"^\s*actions_enabled\s*=\s*var\.notifications\.enabled\s*$", re.M)
ACTION_LISTS = {
    "alarm_actions": r"var\.notifications\.enabled",
    "ok_actions": r"var\.notifications\.enabled\s*&&\s*var\.notifications\.notify_on_ok",
    "insufficient_data_actions": r"var\.notifications\.enabled\s*&&\s*var\.notifications\.notify_on_insufficient_data",
}

# Documentation and tests may show placeholders only, never a real destination.
PLACEHOLDER_ACCOUNTS = {"111111111111", "111122223333", "123456789012", "222222222222", "444455556666"}
EXAMPLE_DOMAIN = re.compile(r"(^|\.)example\.(com|org|net)$")
REAL_DESTINATION_HOSTS = re.compile(
    r"hooks\.slack\.com|events\.pagerduty\.com|webhook\.office\.com|outlook\.office\.com/webhook|"
    r"discord(app)?\.com/api/webhooks|api\.opsgenie\.com|hooks\.chime\.aws",
    re.I,
)
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)")
RESOURCE_ARN = re.compile(r"arn:aws[a-z-]*:(sns|sqs|lambda|events|kms|chatbot):[a-z0-9-]*:([0-9]{12})")
HEARTBEAT_URL = re.compile(r"https?://([^/\s\"'`<>]+)/heartbeat/(\S*)")


def block_after(text, start):
    """Return the brace-balanced block that opens at text[start - 1]."""
    depth, index = 1, start
    while depth and index < len(text):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        index += 1
    return text[start:index]


def blocks(text, header):
    """Yield the body of every block whose opening line matches header."""
    for match in re.finditer(header, text, re.M):
        yield block_after(text, match.end())


def sources(module):
    return {p: p.read_text() for p in sorted(module.glob("*.tf"))}


def published_documents():
    documents = []
    for module in (ALARMS, ROUTING):
        documents.append(module / "README.md")
        documents.extend(sorted((module / "tests").glob("*.tftest.hcl")))
    return documents


class CloudWatchAlarmsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = sources(ALARMS)
        cls.text = "\n".join(cls.sources.values())
        cls.locals = {}
        for body in blocks(cls.text, r"^locals\s*\{"):
            for name, value in re.findall(r"^  ([a-z0-9_]+)\s*=\s*(.+)$", body, re.M):
                cls.locals[name] = value

    def test_module_exists(self):
        self.assertTrue(self.sources, "modules/aws/observability/cloudwatch-alarms has no Terraform files")

    def test_creates_no_destination_resources(self):
        types = set(RESOURCE.findall(self.text))
        self.assertTrue(types, "no resources found")
        self.assertLessEqual(types, ALARMS_ALLOWED_TYPES, "the alarms module may create only alarms and metric filters")
        self.assertIsNone(FOREIGN_DESTINATIONS.search(self.text))
        self.assertNotRegex(self.text, r'resource\s+"aws_sns_')

    def test_composes_only_naming(self):
        sources = set(MODULE_SOURCE.findall(self.text))
        self.assertLessEqual(sources, ALARMS_ALLOWED_MODULES, "the alarms module may compose only core/naming")

    def test_actions_are_off_by_default_and_only_from_notifications(self):
        alarms = 0
        for body in blocks(self.text, r'resource\s+"aws_cloudwatch_metric_alarm"\s+"[^"]+"\s*\{'):
            alarms += 1
            self.assertRegex(body, ACTIONS_ENABLED)
            for argument, guard in ACTION_LISTS.items():
                with self.subTest(argument=argument):
                    match = re.search(rf"^\s*{argument}\s*=\s*{guard}\s*\?\s*(?P<value>.+?)\s*:\s*\[\]\s*$", body, re.M)
                    self.assertIsNotNone(match, f"{argument} must be '<notifications guard> ? <topic> : []'")
                    value = match.group("value")
                    self.assertNotIn('"', value, f"{argument} must not contain a literal")
                    self.assertNotRegex(value, r"var\.(?!notifications\b)", f"{argument} may read only var.notifications")
                    referenced = re.findall(r"local\.([a-z0-9_]+)", value)
                    self.assertTrue(referenced or "var.notifications" in value)
                    for name in referenced:
                        definition = self.locals.get(name, "")
                        self.assertIn("var.notifications.topic_arns", definition, f"local.{name} must come from var.notifications")
                        self.assertNotIn("arn:", definition, f"local.{name} must not contain a literal ARN")
        self.assertGreater(alarms, 0)

    def test_notifications_input_is_off_by_default(self):
        variables = VARIABLE.findall(self.text)
        routing = [v for v in variables if re.search(r"action|topic|notification|subscri", v)]
        self.assertEqual(routing, ["notifications"], "routing must be configured through var.notifications only")
        body = next(blocks(self.text, r'^variable\s+"notifications"\s*\{'))
        self.assertRegex(body, r"\benabled\s*=\s*optional\(bool,\s*false\)")
        self.assertRegex(body, r"\btopic_arns\s*=\s*optional\(map\(map\(string\)\),\s*\{\}\)")
        self.assertRegex(body, re.compile(r"^\s*default\s*=\s*\{\}\s*$", re.M), "notifications must default to {} (routing off)")

    def test_no_literal_destination_in_code(self):
        for path, text in self.sources.items():
            with self.subTest(file=path.name):
                self.assertNotRegex(text, r"arn:aws[a-z-]*:(sns|lambda|events|sqs|chatbot):")
                self.assertIsNone(REAL_DESTINATION_HOSTS.search(text))


class AlarmRoutingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = sources(ROUTING)
        cls.text = "\n".join(cls.sources.values())

    def test_module_exists(self):
        self.assertTrue(self.sources, "modules/aws/observability/alarm-routing has no Terraform files")

    def test_creates_only_sns_topics_policies_and_subscriptions(self):
        types = set(RESOURCE.findall(self.text))
        self.assertTrue(types, "no resources found")
        self.assertLessEqual(types, ROUTING_ALLOWED_TYPES, "alarm-routing may create only SNS topics, policies and subscriptions")
        self.assertIsNone(FOREIGN_DESTINATIONS.search(self.text))

    def test_composes_only_core_building_blocks(self):
        sources = set(MODULE_SOURCE.findall(self.text))
        self.assertIn("../../core/encryption", sources)
        self.assertLessEqual(sources, ROUTING_ALLOWED_MODULES, "alarm-routing may compose only core building blocks")

    def test_every_topic_sets_the_module_key(self):
        topics = 0
        for body in blocks(self.text, r'resource\s+"aws_sns_topic"\s+"[^"]+"\s*\{'):
            topics += 1
            match = re.search(r"^\s*kms_master_key_id\s*=\s*(?P<value>.+?)\s*$", body, re.M)
            self.assertIsNotNone(match, "every aws_sns_topic must set kms_master_key_id")
            self.assertRegex(match.group("value"), r"^module\.encryption\[[^\]]+\]\.key_arn$", "the key must come from core/encryption")
        self.assertGreater(topics, 0)

    def test_aws_managed_key_is_rejected(self):
        body = next(blocks(self.text, r'^variable\s+"kms"\s*\{'))
        self.assertRegex(body, re.compile(r"^\s*default\s*=\s*\{\s*create\s*=\s*true\s*\}\s*$", re.M), "kms must default to a module key")
        self.assertRegex(body, r"condition\s*=\s*var\.kms\.create\s*\|\|\s*var\.kms\.key_id\s*!=\s*null", "kms = {} (aws/sns) must be rejected")
        self.assertNotIn("alias/aws/sns", self.text.replace(body, ""))

    def test_subscriptions_use_email_or_https_only(self):
        protocols = re.findall(r'^\s*protocol\s*=\s*"([^"]*)"', self.text, re.M)
        self.assertTrue(protocols)
        self.assertLessEqual(set(protocols), {"email", "https"})
        self.assertEqual(len(protocols), len(list(blocks(self.text, r'resource\s+"aws_sns_topic_subscription"\s+"[^"]+"\s*\{'))))

    def test_webhook_urls_are_sensitive(self):
        body = next(blocks(self.text, r'^variable\s+"https_subscriptions"\s*\{'))
        self.assertRegex(body, re.compile(r"^\s*sensitive\s*=\s*true\s*$", re.M))


class PublishedExamplesTests(unittest.TestCase):
    def test_examples_and_tests_carry_no_real_endpoints(self):
        for path in published_documents():
            text = path.read_text()
            with self.subTest(file=path.relative_to(ROOT).as_posix()):
                self.assertIsNone(REAL_DESTINATION_HOSTS.search(text))
                for domain in EMAIL.findall(text):
                    self.assertRegex(domain, EXAMPLE_DOMAIN, "email addresses must use example.com/.org/.net")
                for _service, account in RESOURCE_ARN.findall(text):
                    self.assertIn(account, PLACEHOLDER_ACCOUNTS, "ARNs must use a documentation account ID")
                for host, key in HEARTBEAT_URL.findall(text):
                    self.assertTrue(EXAMPLE_DOMAIN.search(host) or key.startswith("<"), f"heartbeat URL on {host} is not a placeholder")


if __name__ == "__main__":
    unittest.main()
