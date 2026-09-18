data "archive_file" "bootstrap" {
  count = local.use_generated_bootstrap ? 1 : 0

  type = "zip"

  source {
    filename = local.bootstrap_filename
    content  = local.bootstrap_content
  }

  output_path = "${path.root}/.terraform/${local.rendered_name}-bootstrap.zip"
}
