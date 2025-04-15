# Check Orphans Script

This script is designed to check and validate Longhorn Orphan Custom Resources (CRs) against a provided list of replica data names. It identifies whether the orphan CRs exist, their conditions, and provides a summary of the findings.

## Features
- Fetches all current Longhorn Orphan CRs from the specified Kubernetes namespace.
- Matches replica data names from the input file against the fetched orphan CRs.
- Displays detailed information about each match, including conditions such as `DataCleanable` and `Error` statuses.
- Provides a summary of found and missing orphan CRs, as well as cleanable and error-free counts.

## Prerequisites
- Kubernetes CLI (`kubectl`) installed and configured to access the cluster.
- `jq` installed for JSON parsing.

## Usage

```bash
./check_orphans.sh [input_file]
```

### Parameters
- `input_file` (optional): Path to the file containing the list of replica data names. Defaults to `orphan_paths.txt` if not provided.

### Input File Format
The input file should contain lines with the following format:
```
<size> <path>
```
Example:
```
100M /var/lib/longhorn/replicas/replica1
200M /var/lib/longhorn/replicas/replica2
```

## Output
The script outputs the following information:
1. For each replica data name:
   - Whether it was found (`FOUND`) or missing (`MISSING`).
   - The corresponding orphan CR name and its conditions (if found).
   - Whether the orphan is cleanable or error-free.
2. A summary of the results, including counts of found, cleanable, error-free, and missing orphan CRs.

## Example
```bash
./check_orphans.sh orphan_paths.txt
```

### Sample Output
```
Fetching current Longhorn Orphan CRs from cluster...

Checking each replica data name...
[FOUND]  replica1                              100M      
          CR: orphan-cr-1
              Conditions: DataCleanable:True Error:False 
                  --> This orphan is cleanable.
                  --> This orphan has no errors.
[MISSING] replica2                              200M      
          --> No matching Orphan CR

Check complete.
Summary:
  Found: 1
    DataCleanable is True: 1
    Error is False: 1
  Missing: 1
```

## Notes
- Ensure the Kubernetes context is set to the correct cluster before running the script.
- The namespace for Longhorn Orphan CRs is set to `longhorn-system` by default. Modify the `LONGHORN_NS` variable in the script if needed.