output "marked_service_ids" {
  description = "A map of service names, their Dynatrace IDs, and the endpoints marked as key requests."
  value = {
    for name, id in local.latest_service_id : name => {
      service_id = id
      endpoints  = var.projects[name].key_request_names
    } if id != null
  }
}
