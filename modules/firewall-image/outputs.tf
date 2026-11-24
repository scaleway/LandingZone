output "snapshot_ids" {
  description = "Map of zone => SBS snapshot ID (imported from object storage)"
  value = {
    for z, snap in scaleway_block_snapshot.this : z => {
      snapshot_id = split("/", snap.id)[1]
    }
  }
}

output "snapshot_ids_full" {
  description = "Map of zone => full regional SBS snapshot ID (zone-prefixed, e.g. fr-par-1/<uuid>), for direct use in snapshot_id_override so stage-3 volumes keep their exact source reference."
  value = {
    for z, snap in scaleway_block_snapshot.this : z => snap.id
  }
}

output "volume_ids" {
  description = "Map of zone => SBS volume ID, ready for instance root_volume"
  value = {
    for z, vol in scaleway_block_volume.this : z => {
      volume_id = split("/", vol.id)[1]
    }
  }
}

output "object_key" {
  description = "Object key of the uploaded QCOW2 in the bucket."
  value       = local.qcow_filename
}
