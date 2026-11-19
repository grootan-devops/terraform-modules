locals {
  name = module.naming.names.app

  security_headers = <<-EOT
    customHeaders:
      - pattern: '**'
        headers:
          - key: 'Strict-Transport-Security'
            value: 'max-age=31536000; includeSubDomains'
          - key: 'X-Content-Type-Options'
            value: 'nosniff'
          - key: 'X-Frame-Options'
            value: 'SAMEORIGIN'
          - key: 'Referrer-Policy'
            value: 'strict-origin-when-cross-origin'
  EOT

  custom_headers = var.custom_headers.enabled ? coalesce(var.custom_headers.yaml, local.security_headers) : null
}
