# Automating Dynatrace Key Requests

The goal is to automate the creation of "Key Requests" for a service in Dynatrace using Terraform. Currently, key requests are managed manually in the Dynatrace UI. We want to transition this process to an automated approach using Terraform.

To create a Terraform configuration for this task, we need the environment URL where the updates should be applied, an API token to allow Terraform to modify the key requests, a Service Name to target the specific service, and the list of APIs (endpoints) that need to be updated.

1. Environment URL: We can take this directly from the URL of the Dynatrace environment. 

    Example: https://ucr29527.apps.dynatrace.com/

2. API token: We can generate this from the access tokens in Dynatrace. While generating the new token, we have to allow the permissions that this token needs to access. As mentioned in the Terraform registry documentation https://registry.terraform.io/providers/dynatrace-oss/dynatrace/latest/docs/resources/key_requests, we have to give the permissions of settings.read and settings.write. And we will store this token in jenkins credentials so that it will not be exposed.

3. Service Name: Instead of manually looking up a long Service ID, we will use the Service Name as it appears in Dynatrace. Terraform will then use a "Data Source" to find the correct ID automatically during execution.

    Example: 
    ```hcl
    data "dynatrace_entity" "service" {
      type = "SERVICE"
      name = var.service_name 
    }
    ```

4. List of APIs: Select the APIs that need to be marked as key requests. These names will be stored in the terraform.tfvars file, making it easy to add or remove endpoints in the future.


Now that we have all the required details, we can prepare the Terraform code for our task.

We need three files:
1. main.tf: For the provider and main resource logic. We can also create a separate `provider.tf`, but in this case, I am adding it directly to `main.tf`. 
2. variables.tf: To define the variables. This allows us to provide details during execution so we don't expose sensitive data in our files.
3. terraform.tfvars: To store the environment URL and service names. Use this file for easy management without touching the main code.

main.tf:

```hcl
# We are specifying the provider version so that we don't have issues in the future.
# Storing the state file in s3 bucket so that we can share this state file across the team and avoid the storing in jenkins server
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

# The provider connects to the Dynatrace environment.
# We use var.dt_env_url and var.dynatrace_api_token which will be provided during execution by using the tfvars file.
provider "dynatrace" {
  dt_env_url   = var.dt_env_url
  dt_api_token = var.dynatrace_api_token
}

# This block searches Dynatrace for the service id by its name.
data "dynatrace_entity" "service" {
  type = "SERVICE"
  name = var.service_name 
}

# We use the resource "dynatrace_key_requests" to create the key requests.
# It uses the SERVICE ID found by the data source above.

resource "dynatrace_key_requests" "api_gateway_key_requests" {
  service = data.dynatrace_entity.service.id
  names   = var.key_request_names
}
```

variables.tf:

```hcl
# API token generated from Dynatrace (String type)
variable "dynatrace_api_token" {
  type = string
  sensitive = true     # This is optional. It hides the token from the logs.
}

# Service name as it appears in Dynatrace
variable "service_name" {
  type = string
}

# URL of the Dynatrace environment
variable "dt_env_url" {
  type = string
}

# List of APIs (endpoints) to mark as key requests
variable "key_request_names" {
  type = list(string)
}
```

terraform.tfvars:

```hcl
# Example values
dt_env_url        = "https://ucr29527.apps.dynatrace.com/"
service_name      = "api-gateway-service"
key_request_names = ["/login", "/saveUser"]
```

Automation and Execution:

To automate this process, we use a terraform.tfvars file to provide the values for dt_env_url, service_name, and key_request_names. For security, the dynatrace_api_token is provided via an environment variable in jenkins.

When the code is pushed to Git, the Jenkins pipeline will automatically run:
1. terraform init
2. terraform validate
3. terraform plan
4. terraform apply -auto-approve

If we have separate files for different environments (like qa.tfvars or staging.tfvars), we can run:

terraform apply -auto-approve -var-file="qa.tfvars"
