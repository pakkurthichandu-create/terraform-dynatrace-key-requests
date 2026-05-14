terraform {
  backend "s3" {
    bucket       = "terraform-state-bucket-4440"
    key          = "key-requests.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    dynatrace = {
      source  = "dynatrace-oss/dynatrace"
      version = "1.96.0"
    }
  }
}

provider "dynatrace" {
  dt_env_url   = var.dt_env_url
  dt_api_token = var.dynatrace_api_token
}

data "dynatrace_entity" "service" {
  for_each = var.projects

  entity_selector = "type(\"SERVICE\"),entityName.equals(\"${each.key}\")"
}

resource "dynatrace_key_requests" "key_requests" {
  for_each = var.projects

  service = data.dynatrace_entity.service[each.key].id
  names   = each.value.key_request_names
}
