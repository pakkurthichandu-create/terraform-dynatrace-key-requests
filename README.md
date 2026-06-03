# Automating Dynatrace Key Requests

The goal is to automate the creation of "Key Requests" for a service in Dynatrace using Terraform. This project transitions the manual management in the Dynatrace UI to an automated approach.

Building the configuration requires the environment URL, an API token, the Workload Name, and the list of APIs (endpoints).

1. Environment URL: Obtained directly from the URL of the Dynatrace environment. 

    Example: https://ucr29527.apps.dynatrace.com/

2. API token: Generated from access tokens in Dynatrace. Per the documentation (https://registry.terraform.io/providers/dynatrace-oss/dynatrace/latest/docs/resources/key_requests), the token requires settings.read, settings.write, and entities.read for data source. Storing this token in Jenkins credentials prevents exposure.

3. Workload Name: Instead of manual ID lookups, the Kubernetes Workload Name (from the CSV) is used. Terraform then uses a "Data Source" to find the correct linked Service ID automatically.

    Example: 
    ```hcl
    data "dynatrace_entities" "service" {
      for_each        = local.csv_projects
      from            = "now-24h"
      entity_selector = "type(\"SERVICE\"),fromRelationships.isServiceOf(type(\"CLOUD_APPLICATION\"),entityName.equals(\"${each.key}\"))"
    }
    ```

4. List of APIs: Select the APIs that need to be marked as key requests. These names are stored in the services.csv file, making it easy to add or remove endpoints in the future.


With the required details prepared, the Terraform configuration consists of the following files:

1. **main.tf**: Contains the provider configuration, data sources, and core resource logic. 
2. **variables.tf**: Defines required input variables, ensuring sensitive data is not hardcoded.
3. **terraform.tfvars**: Stores non-sensitive configuration values like the environment URL.
4. **services.csv**: Maps workload names to their required endpoints for automated discovery and creation.
5. **backend-prod.conf**: Stores S3 bucket details for secure remote state management.
6. **outputs.tf**: Summarizes the execution results, listing successfully marked services and any missing/inactive ones.

main.tf:

```hcl
# Provider version is specified to ensure stability and future compatibility.
# State file is stored in an S3 bucket for team collaboration and persistence.
terraform {
  required_version = "~> 1.14.0"

  backend "s3" {
    # Configuration is loaded from .conf files for security and portability.
  }

  required_providers {
    dynatrace = {
      source  = "dynatrace-oss/dynatrace"
      version = "1.96.0"
    }
  }
}

# The provider establishes connection to the Dynatrace environment.
# Variables dt_env_url and dynatrace_api_token are provided during execution via environment variables or tfvars.
provider "dynatrace" {
  dt_env_url   = var.dt_env_url
  dt_api_token = var.dynatrace_api_token
}

# Searches Dynatrace for the service ID based on the Workload Name.
data "dynatrace_entities" "service" {
  for_each        = local.csv_projects
  from            = "now-24h"
  entity_selector = "type(\"SERVICE\"),fromRelationships.isServiceOf(type(\"CLOUD_APPLICATION\"),entityName.equals(\"${each.key}\"))"
}

# Iterates through service results to identify the most recently active ID.
# Handles empty results by assigning a null value.
locals {
  # CSV Parsing logic
  csv_raw      = [for row in csvdecode(file("${path.module}/services.csv")) : row if trimspace(row.workload) != "" && trimspace(row.endpoint) != ""]
  csv_projects = { for name, endpoints in { for row in local.csv_raw : row.workload => row.endpoint... } : name => distinct(endpoints) }

  # Discovery logic
  latest_service_id = {
    for service_name, entities_payload in data.dynatrace_entities.service : service_name => length(entities_payload.entities) > 0 ? [
      for entity in entities_payload.entities : entity.entity_id
    ][index([for entity in entities_payload.entities : entity.last_seen_tms], max([for entity in entities_payload.entities : entity.last_seen_tms]...))] : null
  }
}

# The dynatrace_key_requests resource creates the key requests in Dynatrace.
# Execution is restricted to services successfully discovered in the data source.
resource "dynatrace_key_requests" "key_requests" {
  for_each = { for service_name, endpoints in local.csv_projects : service_name => endpoints if local.latest_service_id[service_name] != null }
  service  = local.latest_service_id[each.key]
  names    = each.value
}
```

variables.tf:

```hcl
# Dynatrace API token with required scopes for environment modification.
variable "dynatrace_api_token" {
  type      = string
  sensitive = true
  validation {
    condition     = length(trimspace(var.dynatrace_api_token)) > 0
    error_message = "dynatrace_api_token must not be empty."
  }
}

# URL for the target Dynatrace environment.
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
```

outputs.tf:

```hcl
# Displays services successfully updated in Dynatrace.
output "successfully_marked_services" {
  description = "Services found and successfully marked in Dynatrace"
  value = {
    for name, id in local.latest_service_id : name => {
      service_id = id
      endpoints  = local.csv_projects[name]
    } if id != null
  }
}

# Displays services requested but not found in Dynatrace.
output "failed_or_inactive_services" {
  description = "Services in CSV that were NOT found (Check for typos or inactivity in the last 24h)"
  value = [
    for name, id in local.latest_service_id : name if id == null
  ]
}
```

### Steps to Execute

**Step 1: Provide the API Token.**
Securely provide the Dynatrace API token as an environment variable to ensure it is not exposed in local files.
```bash
export TF_VAR_dynatrace_api_token="<your_token>"
```

**Step 2: Create a backend configuration file.**
Create a file named `backend-prod.conf` in the local `terraform/` directory. This file contains the S3 bucket details.

Example (`backend-prod.conf`):
```hcl
bucket       = "terraform-state-bucket-44406283"
key          = "key-requests.tfstate"
region       = "us-east-1"
use_lockfile = true
encrypt      = true
```

**Step 3: Initialize Terraform.**
Run the initialization command and provide the path to the configuration file created in Step 2.
```bash
terraform init -backend-config="./backend-prod.conf"
```

**Step 4: Execute Plan.**
Preview the changes before applying them. If the plan shows unexpected changes (such as deleting or recreating existing key requests), refer to the **Migration of Existing Data** section below to "adopt" them into Terraform instead of recreating them.
```bash
terraform plan
```

**Step 5: Execute Apply.**
Apply the changes to the Dynatrace environment once the plan is verified.
```bash
terraform apply -auto-approve
```

### Migration of Existing Data (Adoption Strategy)

If key requests are already marked manually in the Dynatrace UI, **do not delete them.** Deleting and recreating key requests assigns a new ID, which disrupts existing Dashboards and historical metrics.

Follow this "Adoption" workflow to integrate existing configurations into Terraform:

1. **Dry Run**: Run `terraform plan`. If Terraform attempts to "Create" a key request that already exists in the UI, use the import process instead.
2. **Bulk Import**: For large-scale migrations (e.g., 200+ services), use an `import` block within the configuration for each service to avoid manual command-line overhead.

**Approach 1: Command Line Import**
Utilize the following command for individual resource adoption:
`terraform import 'dynatrace_key_requests.key_requests["server-registry-qa"]' <SERVICE_ID>`

**Approach 2: Declarative Import Block **
Incorporate an `import` block into the configuration for a managed adoption process:
```hcl
import {
  to = dynatrace_key_requests.key_requests["server-registry-qa"]
  id = "<SERVICE_ID>"
}
```
*(Note: You can remove the import block once the state is successfully updated.)*

**Large Scale Migration (200+ Services)**: If we have hundreds of services to import, do not write these blocks manually. It is better to write a small script (Python or Bash) that reads our service list, queries the Dynatrace API for the IDs, and automatically generates these `import` blocks into a temporary `.tf` file.
