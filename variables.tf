variable "dynatrace_api_token" {
  type        = string
  description = "The Dynatrace API token (stored in Jenkins credentials)"
  sensitive   = true
  validation {
    condition     = length(trimspace(var.dynatrace_api_token)) > 0
    error_message = "dynatrace_api_token must not be empty."
  }
}

variable "dt_env_url" {
  type        = string
  description = "The Dynatrace environment URL"
  validation {
    condition     = startswith(var.dt_env_url, "https://")
    error_message = "dt_env_url must start with https://"
  }
}
