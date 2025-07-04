1. Group replicas with prefix (volume name)
    kubectl get replicas -n longhorn-system -o json | jq '
    .items | 
    group_by(.spec.volumeName)[] | 
    map({name: .metadata.name, prefix: .spec.volumeName, state: .status.currentState}) | 
    group_by(.prefix) | 
    map({
    prefix: .[0].prefix, 
    replicas: map({name: .name, state: .state})
    })'

2. $ bash gradual-create-pods.sh 20

3. ./get_replicas_by_instance_manager.sh instance-manager-5f62ba68b81a4af34ec17

4. ./check_engines.sh instance-manager-e-4cd9dd17035535524f0c706f69928da5

5. Check if storage network has duplicated IPs
    $ ./check_lhnet1_duplicates.sh

6. Find volume with specific replica numbers
    $ ./find_replica_count_volumes.sh <#replica>

7. Find volume's details with assigned volume name
    $ ./find_volume_details.sh <volume name>