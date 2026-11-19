data "archive_file" "placeholder" {
  count = local.placeholder ? 1 : 0

  type        = "zip"
  output_path = "${path.root}/.terraform/${local.function_name}-placeholder.zip"

  source {
    filename = local.runtime_family == "nodejs" ? "index.js" : "lambda_function.py"
    content  = local.runtime_family == "nodejs" ? "exports.handler = async () => ({ statusCode: 501, body: \"not deployed\" });\n" : "def handler(event, context):\n    return {\"statusCode\": 501, \"body\": \"not deployed\"}\n"
  }
}
