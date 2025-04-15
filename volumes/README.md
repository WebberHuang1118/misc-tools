# Volumes Directory

This directory contains various scripts and resources for managing and analyzing Longhorn volumes. Below is a brief description of each script and file:

## Scripts

- **check_engines.sh**: Checks the status of engines in the Longhorn system.
- **check_lhnet1_duplicates.sh**: Identifies duplicate entries in the `lhnet1` network configuration.
- **count_instance.sh**: Counts the number of instances in the Longhorn system.
- **count_replicas.sh**: Counts the number of replicas for each volume.
- **find_longhorn_volumes_with_param.sh**: Finds Longhorn volumes based on specific parameters.
- **find_replica_count_volumes.sh**: Identifies volumes with a specific replica count.
- **find_volume_details.sh**: Retrieves detailed information about Longhorn volumes.
- **get_replicas_by_instance_manager.sh**: Lists replicas managed by each instance manager.
- **gradual-create-pods.sh**: Gradually creates pods for testing or deployment purposes.

## Subdirectories

### orphan/
- **check_orphans.sh**: Identifies orphaned volumes or replicas.
- **orphan_paths.txt**: Contains paths to orphaned resources.
- **README.md**: Documentation for managing orphaned resources.

## Documentation

- **online-resizing.md**: Guide for resizing volumes online.
- **README.md.bak**: Backup of the original README file.

## Notes

This directory is intended for use with Longhorn, a distributed block storage system for Kubernetes. Ensure you have the necessary permissions and context before running any scripts.