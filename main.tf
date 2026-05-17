terraform {
  required_version = "~> 1.14.0"

  backend "s3" {
    bucket       = "terraform-state-bucket-44406283"
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

data "dynatrace_entities" "service" {
  for_each        = var.projects
  from            = "now-24h"
  entity_selector = "type(\"SERVICE\"),fromRelationships.isServiceOf(type(\"CLOUD_APPLICATION\"),entityName.equals(\"${each.key}\"))"
}

locals {
  latest_service_id = {
    for service_name, entities_payload in data.dynatrace_entities.service : service_name => length(entities_payload.entities) > 0 ? [
      for entity in entities_payload.entities : entity.entity_id
    ][index([for entity in entities_payload.entities : entity.last_seen_tms], max([for entity in entities_payload.entities : entity.last_seen_tms]...))] : null
  }
}

resource "dynatrace_key_requests" "key_requests" {
  for_each = { for service_name, config in var.projects : service_name => config if local.latest_service_id[service_name] != null }
  service  = local.latest_service_id[each.key]
  names    = each.value.key_request_names
}
