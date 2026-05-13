variable "dynatrace_api_token" {
  type        = string
  description = "The Dynatrace API token (stored in Jenkins credentials)"
  sensitive   = true
}

variable "service_name" {
  type        = string
  description = "The display name of the service as seen in Dynatrace"
}

variable "dt_env_url" {
  type        = string
  description = "The Dynatrace environment URL"
}

variable "key_request_names" {
  type        = list(string)
  description = "A list of endpoint names to be marked as key requests"
}