resource "oneuptime_team" "this" {
  for_each = var.rbac_team_mapping
  name     = each.key
}

// THIS BELOW REQUIRES PERMISSION BEYOND PROJECT SCOPED API KEYS

# resource "oneuptime_team_member" "this" {
#   for_each = {
#     for item in flatten([
#       for team, users in var.rbac_team_mapping : [
#         for user in users : {
#           team = team
#           user = user
#         }
#       ]
#     ]) : "${item.team}-${item.user}" => item
#   }
#   user_id = data.oneuptime_user.this[each.value.user]
#   team_id = oneuptime_team.this[each.value.team].id
# }

# data "oneuptime_user" "this" {
#   for_each = toset(flatten([for k, v in var.rbac_team_mapping : v ]))
#   name = each.value
# }
