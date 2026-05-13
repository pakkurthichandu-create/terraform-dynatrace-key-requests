terraform {
  backend "s3" {
    bucket = "my-terraform-state-bucket"
    key    = "key-requests.tfstate"
    region = "us-east-1"
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
  type = "SERVICE"
  name = var.service_name
}

resource "dynatrace_key_requests" "api_gateway_key_requests" {
  service = data.dynatrace_entity.service.id
  names   = var.key_request_names
}
