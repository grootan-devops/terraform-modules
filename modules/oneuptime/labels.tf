resource "oneuptime_label" "this" {
  for_each = merge([
    for k, labels in local.project_labels_config : {
      for label_name, color in labels :
      label_name => {
        type  = k
        name  = label_name
        color = color
      }
    }
  ]...)
  name  = each.value.name
  color = each.value.color
}
