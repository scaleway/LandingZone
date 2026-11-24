# Scaleway VPC Module

Creates a Scaleway VPC with optional Private Networks (with subnets), IAM policies,
and security groups in a single call.

## Features

- **VPC**: with routing, custom route propagation, and transitivity
- **Private Networks**: with optional IPv4/IPv6 subnets
- **IAM Policies**: factory-style `iam_policies` map for one-call IAM wiring (per-VPC)
- **Security Groups**: factory-style `security_groups` map for creating SGs scoped to the VPC's project
- **Optional `project_id`**: if not set, the provider's default project is used

## Usage

```hcl
module "vpc" {
  source = "./modules/vpc"

  name       = "lz-dev-vpc-hub"
  project_id = "11111111-1111-1111-1111-111111111111"  # optional: defaults to provider project
  region     = "fr-par"
  tags       = ["network", "hub"]

  enable_routing                   = true
  enable_custom_routes_propagation = true
  enable_transitivity              = false

  private_networks = {
    hub-net = {
      name             = "hub-net"
      ipv4_subnet_cidr = "10.10.0.0/24"
      tags             = []
      ipam_ips = {
        hub-fw-ip = {
          address = "10.10.0.5"
          is_ipv6 = false
          tags    = ["firewall", "hub"]
        }
        lb1_private = {
          # No address -> auto-allocated by Scaleway IPAM
          tags = ["load-balancer"]
        }
      }
    }
  }

  # --- Optional: inline IAM policies (factory-style) ---
  organization_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  iam_policies = {
    vpc_admins = {
      name     = "lz-dev-vpc-admins"
      group_id = "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
      rules = [
        {
          permission_set_names = ["VPCFullAccess"]
        }
      ]
    }
  }

  # --- Optional: inline security groups (factory-style) ---
  zone = "fr-par-2"
  security_groups = {
    allow-http = {
      name           = "allow-http"
      stateful       = true
      inbound_rules = [
        { action = "accept", protocol = "TCP", port = 80 },
        { action = "accept", protocol = "TCP", port = 443 }
      ]
      outbound_rules = []
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name for the VPC. | `string` | n/a | yes |
| project_id | The ID of the Project the VPC is associated with. | `string` | `null` | no |
| region | The region of the VPC. | `string` | `"fr-par"` | no |
| tags | Tags to associate with the VPC. | `list(string)` | `[]` | no |
| enable_routing | Enable routing between Private Networks in the VPC. | `bool` | `true` | no |
| enable_custom_routes_propagation | Whether the VPC advertises custom routes between its PNs. | `bool` | `true` | no |
| enable_transitivity | Enable packets from peered VPCs to transit through this VPC. | `bool` | `false` | no |
| private_networks | Map of Private Networks to create within the VPC. | `map(object({...}))` | `{}` | no |
| iam_policies | Map of IAM policies to create (factory-style). | `any` | `{}` | no |
| organization_id | Default organization ID for inline IAM policies. | `string` | `null` | no |
| security_groups | Map of security groups to create (factory-style). | `any` | `{}` | no |
| zone | Default zone for security groups. | `string` | `null` | no |

### `iam_policies` object schema (contract: variable is `any`)

```hcl
{
  name           = string
  description    = optional(string)
  tags           = optional(list(string), [])
  user_id        = optional(string)
  group_id       = optional(string)
  application_id = optional(string)
  no_principal   = optional(bool, false)
  rules = [{
    project_ids          = optional(list(string))
    organization_id      = optional(string)
    permission_set_names = list(string)
    condition            = optional(string)
  }]
}
```

> If a rule's `project_ids` is empty but `var.project_id` is set, the VPC's project_id is automatically included.

### `security_groups` object schema (contract: variable is `any`)

```hcl
{
  name                    = string
  description             = optional(string)
  project_id              = optional(string)  # falls back to var.project_id
  zone                    = optional(string)  # falls back to var.zone
  stateful                = optional(bool, true)
  inbound_default_policy  = optional(string, "drop")
  outbound_default_policy = optional(string, "accept")
  enable_default_security = optional(bool, true)
  tags                    = optional(list(string), [])
  inbound_rules = [{
    action     = string
    protocol   = optional(string, "TCP")
    port       = optional(number)
    port_range = optional(string)
    ip_range   = optional(string)
  }]
  outbound_rules = [{
    action     = string
    protocol   = optional(string, "TCP")
    port       = optional(number)
    port_range = optional(string)
    ip_range   = optional(string)
  }]
}
```

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the VPC. |
| name | The name of the VPC. |
| project_id | The project ID of the VPC (null if using provider default). |
| private_network_ids | Map of created Private Network IDs. |
| private_network_names | Map of created Private Network names. |
| iam_policy_ids | Map of IAM policy IDs created for this VPC (keyed by policy key). |
| iam_policy_names | Map of IAM policy names created for this VPC (keyed by policy key). |
| ipam_ip_ids | Map of IPAM IP reservation IDs (keyed by pn_key.ipam_key). |
| ipam_ip_addresses | Map of IPAM IP reservation addresses (keyed by pn_key.ipam_key). |
| security_group_ids | Map of Security Group IDs created for this VPC (keyed by SG key). |
| security_group_names | Map of Security Group names created for this VPC (keyed by SG key). |

## Notes

- **Backward compatibility**: all original variables (`name`, `project_id`, `region`, `tags`, `enable_routing`, `enable_custom_routes_propagation`, `enable_transitivity`, `private_networks`) continue to work unchanged.
- **`project_id` is now optional**: when not set, the provider's default project is used.
- Security groups are created as `scaleway_instance_security_group` resources: attach them to instances via `security_group_id`.
