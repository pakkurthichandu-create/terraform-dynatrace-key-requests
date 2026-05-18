output "successfully_marked_services" {
  description = "Services found and successfully marked in Dynatrace"
  value = {
    for name, id in local.latest_service_id : name => {
      service_id = id
      endpoints  = local.csv_projects[name]
    } if id != null
  }
}

output "failed_or_inactive_services" {
  description = "Services in CSV that were NOT found (Check for typos or inactivity in the last 24h)"
  value = [
    for name, id in local.latest_service_id : name if id == null
  ]
}
