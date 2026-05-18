terraform {
  required_version = "~> 1.14.0"

  backend "s3" {
    # This block is intentionally empty.
    # Configuration is loaded from .conf files using -backend-config during 'terraform init'
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

locals {
  csv_raw      = [for row in csvdecode(file("${path.module}/services.csv")) : row if trimspace(row.workload) != "" && trimspace(row.endpoint) != ""]
  csv_projects = { for name, endpoints in { for row in local.csv_raw : row.workload => row.endpoint... } : name => distinct(endpoints) }
}

data "dynatrace_entities" "service" {
  for_each        = local.csv_projects
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
  for_each = { for service_name, endpoints in local.csv_projects : service_name => endpoints if local.latest_service_id[service_name] != null }
  service  = local.latest_service_id[each.key]
  names    = each.value
}
