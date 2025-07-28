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

{% set reboot_list = controlplane_nodes + worker_nodes %}

# Verify control plane nodes are up. Fail hard if any of these do not respond
check_controlplane_pings:
  salt.function:
    - name: test.ping
    - tgt: {{ controlplane_nodes }}
    - tgt_type: list
    - failhard: True
    - expect_minions: True

# Run the orchestration state for every minion in the reboot_list
{% for minion in reboot_list %}
{{ minion }}_maintenance:
  salt.runner:
    - name: state.orchestrate
    - mods: orchestrate.k8s.upgrade-workflow
    - pillar:
        minion: {{ minion }}
        controlplane_nodes: {{ controlplane_nodes }}
    {% if minion in controlplane_nodes %}
    # If the minion is critical (control plane) fail hard if the minion is not online
    - failhard: True
    {% endif %}
    - require:
      - salt: check_controlplane_pings
{% endfor %}
