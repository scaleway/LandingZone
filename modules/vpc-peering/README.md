# Scaleway VPC Peering Module


Creates and manages Scaleway VPC Connectors to enable network connectivity between VPCs. Supports hub-and-spoke topologies by peering spoke VPCs to a central hub VPC.

## Usage

```hcl
module "vpc_peering" {
  source = "./modules/vpc-peering"

  region = "fr-par"

  peering_connections = {
    hub-to-spoke-1 = {
      name           = "my-peering-1"
      source_vpc_id  = scaleway_vpc.hub.id
      target_vpc_id  = scaleway_vpc.spoke1.id
      tags           = ["hub-spoke"]
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | The region of the VPC connectors. | `string` | `"fr-par"` | no |
| peering_connections | Map of VPC peering connections to create between VPCs. | `map(object)` | `{}` | no |

### `peering_connections` object schema

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the VPC connector. If not provided, will be generated as `peering-<key>`. | `string` | `null` | no |
| source_vpc_id | The ID of the source VPC. | `string` | n/a | yes |
| target_vpc_id | The ID of the target VPC to connect to. | `string` | n/a | yes |
| tags | The tags to associate with the VPC connector. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of created VPC connector IDs. |
| names | Map of created VPC connector names. |
| statuses | Map of created VPC connector statuses. |