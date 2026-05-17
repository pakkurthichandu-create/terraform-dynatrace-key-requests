# Automating Dynatrace Key Requests

The goal is to automate the creation of "Key Requests" for a service in Dynatrace using Terraform. Currently, key requests are managed manually in the Dynatrace UI. We want to transition this process to an automated approach using Terraform.

To create a Terraform configuration for this task, we need the environment URL where the updates should be applied, an API token to allow Terraform to modify the key requests, a Service Name to target the specific service, and the list of APIs (endpoints) that need to be updated.

1. Environment URL: We can take this directly from the URL of the Dynatrace environment. 

    Example: https://ucr29527.apps.dynatrace.com/

2. API token: We can generate this from the access tokens in Dynatrace. While generating the new token, we have to allow the permissions that this token needs to access. As mentioned in the Terraform registry documentation https://registry.terraform.io/providers/dynatrace-oss/dynatrace/latest/docs/resources/key_requests, we have to give the permissions of settings.read and settings.write. And need entities.read for data source. And we will store this token in jenkins credentials so that it will not be exposed.

3. Service Name: Instead of manually looking up a long Service ID, we will use the Service Name as it appears in Dynatrace. Terraform will then use a "Data Source" to find the correct ID automatically during execution.

    Example: 
    ```hcl
    data "dynatrace_entities" "service" {
      for_each        = var.projects
      from            = "now-24h"
      entity_selector = "type(\"SERVICE\"),fromRelationships.isServiceOf(type(\"CLOUD_APPLICATION\"),entityName.equals(\"${each.key}\"))"
    }
    ```

4. List of APIs: Select the APIs that need to be marked as key requests. These names will be stored in the terraform.tfvars file, making it easy to add or remove endpoints in the future.


Now that we have all the required details, we can prepare the Terraform code for our task.

We need four files:
1. main.tf: For the provider and main resource logic. We can also create a separate `provider.tf`, but in this case, I am adding it directly to `main.tf`. 
2. variables.tf: To define the variables. This allows us to provide details during execution so we don't expose sensitive data in our files.
3. terraform.tfvars: To store the environment URL and service names. Use this file for easy management without touching the main code.
4. outputs.tf: To show a summary of the results in the terminal. This tells us exactly which Service IDs and endpoints were marked so we can verify the work easily.

main.tf:

```hcl
# We are specifying the provider version so that we don't have issues in the future.
# Storing the state file in s3 bucket so that we can share this state file across the team and avoid the storing in jenkins server
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

# The provider connects to the Dynatrace environment.
# We use var.dt_env_url and var.dynatrace_api_token which will be provided during execution by using the tfvars file.
provider "dynatrace" {
  dt_env_url   = var.dt_env_url
  dt_api_token = var.dynatrace_api_token
}

# This block searches Dynatrace for the service id by its name.
data "dynatrace_entities" "service" {
  for_each        = var.projects
  from            = "now-24h"
  entity_selector = "type(\"SERVICE\"),fromRelationships.isServiceOf(type(\"CLOUD_APPLICATION\"),entityName.equals(\"${each.key}\"))"
}

# This local calculates the most recent service ID and handles empty results safely.
locals {
  latest_service_id = {
    for service_name, entities_payload in data.dynatrace_entities.service : service_name => length(entities_payload.entities) > 0 ? [
      for entity in entities_payload.entities : entity.entity_id
    ][index([for entity in entities_payload.entities : entity.last_seen_tms], max([for entity in entities_payload.entities : entity.last_seen_tms]...))] : null
  }
}

# We use the resource "dynatrace_key_requests" to create the key requests.
# It only runs for services that were actually found in Dynatrace.
resource "dynatrace_key_requests" "key_requests" {
  for_each = { for service_name, config in var.projects : service_name => config if local.latest_service_id[service_name] != null }
  service  = local.latest_service_id[each.key]
  names    = each.value.key_request_names
}
```

variables.tf:

```hcl
# API token generated from Dynatrace
variable "dynatrace_api_token" {
  type      = string
  sensitive = true
  validation {
    condition     = length(trimspace(var.dynatrace_api_token)) > 0
    error_message = "dynatrace_api_token must not be empty."
  }
}

# Per-service key request configuration
variable "projects" {
  type = map(object({
    key_request_names = list(string)
  }))
}

# URL of the Dynatrace environment
variable "dt_env_url" {
  type = string
  validation {
    condition     = startswith(var.dt_env_url, "https://")
    error_message = "dt_env_url must start with https://"
  }
}
```

terraform.tfvars:

```hcl
# Example values
dt_env_url = "https://ucr29527.apps.dynatrace.com/"

projects = {
  "api-gateway-service" = {
    key_request_names = ["/login", "/saveUser"]
  }
}
```

outputs.tf:

```hcl
# This shows exactly which services and endpoints were successfully updated.
output "marked_service_ids" {
  description = "A map of service names, their Dynatrace IDs, and the endpoints marked as key requests."
  value = {
    for name, id in local.latest_service_id : name => {
      service_id = id
      endpoints  = var.projects[name].key_request_names
    } if id != null
  }
}
```

Automation and Execution:

To automate this process, we use a terraform.tfvars file to provide the values for dt_env_url, service_name, and key_request_names. For security, the dynatrace_api_token is provided via an environment variable in jenkins.

When the code is pushed to Git, the Jenkins pipeline will automatically run:
1. terraform init
2. terraform validate
3. terraform plan
4. terraform apply

If we have separate files for different environments (like qa.tfvars or staging.tfvars), we can run:

terraform apply -auto-approve -var-file="qa.tfvars"

---

### Migration of Existing Data (Adoption Strategy)

If we already have key requests marked manually in the Dynatrace UI, **do not delete them.** Deleting and recreating will give them a new ID, which will break our current Dashboards and historical metrics.

Instead, follow this "Adoption" workflow:

1. **Dry Run**: Run `terraform plan`. If Terraform says it wants to "Create" a service that we know is already marked in the UI, we should import it instead.
2. **Bulk Import**: For many services (like 200+), do not run the import command manually. Instead, use an `import` block in our code for each service.

**Example Command (Approach 1):**
`terraform import 'dynatrace_key_requests.key_requests["server-registry-qa"]' <SERVICE_ID>`

**Example Code (Approach 2 - Recommended for Dashboards):**
Add this to your configuration temporarily to "adopt" the existing request:
```hcl
import {
  to = dynatrace_key_requests.key_requests["server-registry-qa"]
  id = "<SERVICE_ID>"
}
```
*(Note: You can remove the import block once the state is successfully updated.)*

**Large Scale Migration (200+ Services)**: If we have hundreds of services to import, do not write these blocks manually. It is better to write a small script (Python or Bash) that reads our service list, queries the Dynatrace API for the IDs, and automatically generates these `import` blocks into a temporary `.tf` file.
