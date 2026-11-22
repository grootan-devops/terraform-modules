terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = ">= 13.0.6"
    }
  }
}

provider "oneuptime" {
  oneuptime_url = var.oneuptime_url
}
