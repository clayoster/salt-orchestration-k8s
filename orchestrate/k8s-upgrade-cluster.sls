# Define lists of control plane and worker nodes
{% set controlplane_nodes = [
    "kube-cp1.test.com",
    "kube-cp2.test.com",
    "kube-cp3.test.com"
    ] %}

{% set worker_nodes = [
    "kube-worker1.test.com",
    "kube-worker2.test.com",
    "kube-worker3.test.com"
    ] %}

# Alternatively, these lists can be defined in pillar
{# set controlplane_nodes = salt['pillar.get']('k8s:controlplane_nodes') #}
{# set worker_nodes = salt['pillar.get']('k8s:worker_nodes') #}

# Define an upgrade_list that includes the control plane nodes first, then the worker nodes
{% set upgrade_list = controlplane_nodes + worker_nodes %}

# If the k8s node names match the minion name, leave this as is.
# If the k8s node names are the hostname and the minions are a fqdn, set to False
{% set minion_k8s_names_match = True %}

# Allow reboot to be skipped by passing this to the orchestration state:
#   pillar='{"skip_reboot": True}'
{% set skip_reboot = salt['pillar.get']('skip_reboot', False) %}

# Verify control plane nodes are up. Fail hard if any of these do not respond
check_controlplane_pings:
  salt.function:
    - name: test.ping
    - tgt: {{ controlplane_nodes }}
    - tgt_type: list
    - failhard: True
    - expect_minions: True

# Run the orchestration state for every minion in the upgrade_list. Executed sequentially
# and beginning with the control plane nodes.
{% for minion in upgrade_list %}
# set the k8s_node_name variable
{% if minion_k8s_names_match %}
{% set k8s_node_name = minion %}
{% else %}
{% set k8s_node_name = minion.split('.')[0] %}
{% endif %}

# Call the upgrade-workflow orchestration state
{{ minion }}_maintenance:
  salt.runner:
    - name: state.orchestrate
    - mods: orchestrate.k8s.upgrade-workflow
    - pillar:
        minion: {{ minion }}
        k8s_node_name: {{ k8s_node_name }}
        controlplane_nodes: {{ controlplane_nodes }}
        skip_reboot: {{ skip_reboot }}
    {% if minion in controlplane_nodes %}
    # If the minion is a control plane node, fail hard if this state is not successful
    - failhard: True
    {% endif %}
    - require:
      - salt: check_controlplane_pings
{% endfor %}
