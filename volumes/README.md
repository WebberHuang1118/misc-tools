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
