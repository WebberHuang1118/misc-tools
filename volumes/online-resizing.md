1. Adding kubevirt CR spec.configuration.developerConfiguration.featureGates with "ExpandDisks"
2. Update Harvester webhook depolyment with https://github.com/WebberHuang1118/harvester/commit/daea7ddcceb71deb1728833b065c7d279ffeef31
3. LH PVC should be able to resize online
4. Expand filesystem
    4.1 EXT4: $ resize2fs /dev/<device>
5. Kubevirt PR: https://github.com/kubevirt/kubevirt/pull/5981