q# Microsoft Azure Container Service Engine - Kubernetes Upgrade

## Overview

This document describes how to upgrade kubernetes version on a running cluster.

Supported scenarios:
- upgrade from v1.5.x to the latest supported version in v1.6 stream
- upgrade from v1.6.x to the latest supported version in v1.7 stream
- upgrade from v1.7.x to the latest supported version in v1.8 stream

The cluster definition file examples demonstrate initial cluster configurations:
- **kubernetes1.5.json** - Kubernetes cluster v1.5 with Linux agent pool
- **kubernetes1.5-win.json** - Kubernetes cluster v1.5 with Windows agent pool
- **kubernetes1.5-hybrid.json** - Kubernetes cluster v1.5 with Linux and Windows agent pools
- **kubernetes1.6.json** - Kubernetes cluster v1.6 with Linux agent pool
- **kubernetes1.7.json** - Kubernetes cluster v1.7 with Linux agent pool

For upgrade that spans over more than a single minor version, this operation should be called several times, each time advancing the minor version by one. For example, to upgrade from ``1.6.x`` to ``1.8.z`` one should first upgrade the cluster to ``1.7.y``, followed by upgrading it to ``1.8.z``

To get the list of all available Kubernetes versions and upgrades, run the *orchestrators* command and specify Kubernetes orchestrator type. The output is a JSON object:
```
./bin/acs-engine orchestrators --orchestrator Kubernetes
{
  "orchestrators": [
    {
      "orchestratorType": "Kubernetes",
      "orchestratorVersion": "1.7.9",
      "default": true,
      "upgrades": [
        {
          "orchestratorVersion": "1.7.10"
        },
        {
          "orchestratorVersion": "1.8.1"
        },
        {
          "orchestratorVersion": "1.8.0"
        },
        {
          "orchestratorVersion": "1.8.2"
        },
        {
          "orchestratorVersion": "1.8.4"
        }
      ]
    },
    {
      "orchestratorType": "Kubernetes",
      "orchestratorVersion": "1.5.8",
      "upgrades": [
        {
          "orchestratorType": "",
          "orchestratorVersion": "1.6.11"
        },
        {
          "orchestratorVersion": "1.6.9"
        },
        {
          "orchestratorVersion": "1.6.12"
        },
        {
          "orchestratorVersion": "1.6.6"
        }
      ]
    },
    ...
    ...
    ...
  ]
}
```

To get the information specific to the cluster, provide its current orchestrator version:
```
./bin/acs-engine orchestrators --orchestrator Kubernetes --version 1.7.8
{
  "orchestrators": [
    {
      "orchestratorType": "Kubernetes",
      "orchestratorVersion": "1.7.8",
      "upgrades": [
        {
          "orchestratorVersion": "1.7.10"
        },
        {
          "orchestratorVersion": "1.8.0"
        },
        {
          "orchestratorVersion": "1.8.2"
        },
        {
          "orchestratorVersion": "1.8.4"
        },
        {
          "orchestratorVersion": "1.7.9"
        },
        {
          "orchestratorVersion": "1.8.1"
        }
      ]
    }
  ]
}
```

Once the desired Kubernetes version is finalized, call the *upgrade* command:
```
./bin/acs-engine upgrade \
  --subscription-id <subscription id> \
  --deployment-dir <acs-engine output directory > \
  --location <resource group location> \
  --resource-group <resource group name> \
  --upgrade-version <desired Kubernetes version> \
  --auth-method client_secret \
  --client-id <service principal id> \
  --client-secret <service principal secret>
```
For example,
```
./bin/acs-engine upgrade \
  --subscription-id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --deployment-dir ./_output/test \
  --location westus \
  --resource-group test-upgrade \
  --upgrade-version 1.8.4 \
  --auth-method client_secret \
  --client-id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --client-secret xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

By its nature, the upgrade operation is long running and potentially could fail for various reasons, such as temporary lack of resources, etc. In this case, rerun the command. The *upgrade* command is idempotent, and will pick up execution from the point it failed on. 

[This directory](https://github.com/Azure/acs-engine/tree/master/examples/k8s-upgrade) contains the following files:
- **README.md** - this file
- **k8s-upgrade.sh** - script invoking upgrade operation
- **\*.json** - cluster definition examples for various orchestrator versions and configurations: Linux clusters, Windows clusters, hybrid clusters.
- **\*.env** - files with environment variables per corresponding cluster definition **.json** file, to set desired kubernetes version passed over to **k8s-upgrade.sh** by the test framework.
