locals {
  restriction = var.on_call_schedule_layer_config.restriction

  // OneUptime serializes its own value types as an `_type` tag plus a `value`
  // payload, and the API rejects anything else. The key names below are that
  // wire format verbatim - including `restictionType`, which is misspelled in
  // the OneUptime schema itself, so the correct spelling is silently ignored.
  rotation = jsonencode({
    _type = "Recurring"
    value = {
      intervalType = var.on_call_schedule_layer_config.rotation.interval_type
      intervalCount = {
        _type = "PositiveNumber"
        value = var.on_call_schedule_layer_config.rotation.interval_count
      }
    }
  })

  restriction_times = jsonencode({
    _type = "RestrictionTimes"
    value = {
      restictionType = local.restriction.type

      dayRestrictionTimes = local.restriction.type == "Daily" ? {
        startTime = local.restriction.daily.start_time
        endTime   = local.restriction.daily.end_time
      } : null

      // Always an array. OneUptime iterates this key even when the layer is
      // unrestricted, so null would fault it.
      weeklyRestrictionTimes = local.restriction.type == "Weekly" ? [
        for window in local.restriction.weekly : {
          startDay  = window.start_day
          endDay    = window.end_day
          startTime = window.start_time
          endTime   = window.end_time
        }
      ] : []
    }
  })
}
