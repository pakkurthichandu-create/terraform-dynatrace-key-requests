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

variable "projects" {
  description = "Per-service key request configuration"
  type = map(object({
    key_request_names = list(string)
  }))
  validation {
    condition = alltrue([
      for project_key, project in var.projects :
      length(trimspace(project_key)) > 0 &&
      length(project.key_request_names) > 0 &&
      alltrue([for name in project.key_request_names : length(trimspace(name)) > 0])
    ])
    error_message = "Each project key (service name) must be non-empty, and each project must have a non-empty key_request_names list with non-empty strings."
  }
}
