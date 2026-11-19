locals {
  rendered = [
    for s in var.statements : merge(
      s.sid == null ? {} : { Sid = s.sid },
      { Effect = s.effect },
      length(s.principals) == 0 ? {} : { Principal = s.principals },
      { Action = s.actions },
      { Resource = coalesce(s.resources, var.default_resources) },
      length(s.conditions) == 0 ? {} : {
        Condition = {
          for test in distinct([for c in s.conditions : c.test]) : test => {
            for c in s.conditions : c.variable => c.values if c.test == test
          }
        }
      }
    )
  ]

  source_statements = flatten([for d in var.source_documents : try(tolist(jsondecode(d).Statement), [jsondecode(d).Statement])])

  statements = concat(local.source_statements, local.rendered)
}
