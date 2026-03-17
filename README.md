# salt-orchestration-k8s
This Salt orchestration workflow automates patching and rebooting of Kubernetes clusters. It currently supports vanilla [Kubernetes](https://github.com/kubernetes/kubernetes) as well as [rke2](https://github.com/rancher/rke2).

*Note: This currently does not handle Kubernetes cluster version upgrades using Kubeadm*

## To Implement
  - Place the `orchestrate` folder in your Salt fileserver or add the contents to your existing orchestration directory if you have one.
    - The `k8s-upgrade-cluster.sls` can be renamed to your liking. It can also be duplicated and configured for another cluster if you have more than one to manage
  - Place the `k8s-mgmt` bash script under `/usr/local/sbin/` on your control plane nodes

### How to configure the k8s-upgrade-clusters.sls file
Fill in the lists named `control_plane` and `worker_nodes` with the names of your nodes. Alternatively, the node lists can be defined in pillar using the example that is commented out. Review the list of options below to determine if they apply to your environemnt.

### Options
These options can be adjusted in the `orchestrate/k8s-upgrade-cluster.sls` file
  - minion_k8s_names_match
    - If your minion names and k8s node names match, leave this set to `True`. If your k8s node names are the plain hostname and the minion names are fqdn, set to `False`
  - skip_reboot
     - If you do not want to reboot each node after updates are applied, append this to the orchestration command
       - `pillar='{"skip_reboot": True}`
  - clean_standalone_pods
    - If set to `True`, the precheck step will delete any pods without controllers that are found
      - These tend to cause issues with draining worker nodes as there is no controller to assist in scheduling on another node.
    - If set to `False`, the precheck step will only report any pods without controllers that are found

## To Run

* Execute the following command from either **screen** or **tmux** to ensure that a lost SSH session to the Salt master does not interrupt the orchestration.
* A debug level of `info` is set so you can keep an eye on the progress
```shell
salt-run state.orchestrate orchestrate.k8s-upgrade-cluster.sls -l info
```

## Orchestration Workflow Steps

### Pre-check Stage
1. Verify that all control plane nodes are responding. Orchestration fails if any do not respond
2. Check if there any pods deployed without controllers that will cause issues draining worker nodes
    * If `clean_standalone_pods` is set to True, these pods will be deleted. If there are any PVCs attached to these pods, they will be reported so they can be manually cleaned up

### Node Upgrade Stage

Node upgrades are executed serially based on the combined list of control plane nodes and worker nodes, starting with the control plane nodes.

If any of these steps fail for a control plane node, the entire orchestration will fail and stop. Worker nodes are allowed to fail and the workflow will move on to the next one.

1. Check that the node responds to `test.ping`
2. Cordon and drain the node
    * The `--ignore-daemonsets` and `--delete-emptydir-data` options are used and the drain will timeout after 5 minutes
3. Run `pkg.upgrade` state module to apply all available updates
    * If the server is based on Debian, it will also add `dist_upgrade=True`)
4. Reboot the node (If skip_reboot is not True)
5. Wait for the node to reconnect to the Salt Master
    * This will wait for up to 15 minutes before the state fails
6. Uncordon the node
7. Wait before proceeding to the next node
    * Between control plane nodes: **3 minutes**
    * Between worker nodes: **10 seconds**

### Troubleshooting

If you need to view all of the orchestration state output after the command completes:

1. Find the job ID included on the "Runner Completed" line at the end of the orchestration output
    * Example: [INFO _] Runner Completed: 000000000000000
    * Alternatively, use this command to review previous job IDs
      * salt-run jobs.list_jobs
2. Run the following command using the job ID found above
    * salt-run jobs.lookup_jid 000000000000000

## k8s-mgmt Script

*Requires `bash` and `jq` to be available*

This script lives on the control plane nodes to handle some of the more complicated logic for interacting with the k8s nodes during the workflow. It detects the path to the kubectl binary and control plane kubeconfig. Currently it supports vanilla Kubernetes and rke2.

Workflow types:
  - `precheck`: Find pods without controllers and list attached PVCs
  - `precheck_clean`: Find **and delete** pods without controllers and list attached PVCs
  - `cordon`: Make a node unschedulable
  - `drain`: Evict pods and cordon a node
    - The `--ignore-daemonsets` and `--delete-emptydir-data` options are used and the drain will timeout after 5 minutes
  - `uncordon`: Confirm a node is ready and make it schedulable

Prior to each action that is taken, the script validates API connectivity and the control plane health before taking any actions. It will also verify that the node is in the expected state before moving forward. In all cases it will wait up to 200 seconds and if the expected state is not reached within that time, the script will exit with an errorlevel of 1. 

Examples:
```shell
# Perform a precheck for pods without controllers
  k8s-mgmt -t precheck

# Perform a precheck for pods without controllers and delete them
  k8s-mgmt -t precheck_clean

# Cordon a node named worker-node-1
  k8s-mgmt -t cordon -n worker-node-1

# Drain a node named worker-node-1
  k8s-mgmt -t drain -n worker-node-1

# Uncordon a node named worker-node-1
  k8s-mgmt -t uncordon -n worker-node-1
```
