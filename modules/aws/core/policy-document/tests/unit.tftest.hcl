variables {
  default_resources = ["arn:aws:sqs:eu-west-1:123456789012:core-prod-orders"]
  statements = [
    {
      sid        = "AllowEvents"
      actions    = ["sqs:SendMessage"]
      principals = { Service = ["events.amazonaws.com"] }
      conditions = [
        { test = "ArnEquals", variable = "aws:SourceArn", values = ["arn:aws:events:eu-west-1:123456789012:rule/a"] },
        { test = "StringEquals", variable = "aws:SourceAccount", values = ["123456789012"] },
        { test = "ArnEquals", variable = "aws:PrincipalArn", values = ["arn:aws:iam::123456789012:role/x"] }
      ]
    },
    {
      effect    = "Deny"
      actions   = ["sqs:*"]
      resources = ["*"]
    }
  ]
}

run "renders_statements" {
  command = plan

  assert {
    condition     = jsondecode(output.json).Version == "2012-10-17" && output.statement_count == 2
    error_message = "The document must carry the policy version and both statements."
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Resource == ["arn:aws:sqs:eu-west-1:123456789012:core-prod-orders"]
    error_message = "A statement without resources must use default_resources."
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Condition.ArnEquals["aws:SourceArn"] == ["arn:aws:events:eu-west-1:123456789012:rule/a"] && jsondecode(output.json).Statement[0].Condition.ArnEquals["aws:PrincipalArn"] == ["arn:aws:iam::123456789012:role/x"] && jsondecode(output.json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"]
    error_message = "Conditions with the same test must be grouped under one operator."
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Principal.Service == ["events.amazonaws.com"] && jsondecode(output.json).Statement[0].Sid == "AllowEvents"
    error_message = "Principal and Sid must be rendered."
  }

  assert {
    condition     = !can(jsondecode(output.json).Statement[1].Principal) && !can(jsondecode(output.json).Statement[1].Condition) && !can(jsondecode(output.json).Statement[1].Sid) && jsondecode(output.json).Statement[1].Effect == "Deny"
    error_message = "Empty principals, conditions and sid must be omitted."
  }
}

run "keeps_source_documents_first" {
  command = plan

  variables {
    source_documents = [jsonencode({ Version = "2012-10-17", Statement = [{ Sid = "Guard", Effect = "Deny", Action = "*", Resource = "*" }] })]
  }

  assert {
    condition     = output.statement_count == 3 && jsondecode(output.json).Statement[0].Sid == "Guard"
    error_message = "Source document statements must come first."
  }

  assert {
    condition     = length(jsondecode(output.statements_json)) == 2
    error_message = "statements_json must hold only the rendered statements."
  }
}

run "rejects_public_allow_without_condition" {
  command = plan

  variables {
    statements = [{ actions = ["s3:GetObject"], principals = { AWS = ["*"] } }]
  }

  expect_failures = [var.statements]
}

run "allows_public_when_requested" {
  command = plan

  variables {
    allow_public = true
    statements   = [{ actions = ["s3:GetObject"], principals = { AWS = ["*"] } }]
  }

  assert {
    condition     = jsondecode(output.json).Statement[0].Principal.AWS == ["*"]
    error_message = "allow_public must let a public statement through."
  }
}

run "rejects_bad_effect" {
  command = plan

  variables {
    statements = [{ effect = "Permit", actions = ["s3:GetObject"] }]
  }

  expect_failures = [var.statements]
}

run "rejects_empty_actions" {
  command = plan

  variables {
    statements = [{ actions = [] }]
  }

  expect_failures = [var.statements]
}

run "rejects_unknown_principal_type" {
  command = plan

  variables {
    statements = [{ actions = ["s3:GetObject"], principals = { User = ["x"] } }]
  }

  expect_failures = [var.statements]
}

run "rejects_missing_resources" {
  command = plan

  variables {
    default_resources = []
    statements        = [{ actions = ["s3:GetObject"] }]
  }

  expect_failures = [var.statements]
}

run "rejects_invalid_source_document" {
  command = plan

  variables {
    source_documents = ["{\"Version\":\"2012-10-17\"}"]
  }

  expect_failures = [var.source_documents]
}
