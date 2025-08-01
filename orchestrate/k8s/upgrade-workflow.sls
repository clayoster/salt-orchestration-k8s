# Retrieve variables passed to this orchestration state from orchestration.k8s-upgrade-cluster
{% set minion = salt['pillar.get']('minion') %}
{% set k8s_node_name = salt['pillar.get']('k8s_node_name') %}
{% set controlplane_nodes = salt['pillar.get']('controlplane_nodes') %}

# Verify that the minion is responding before continuing
{{ minion }}_check_minion_pings:
  salt.function:
    - name: test.ping
    - tgt: {{ minion }}
    {% if minion in controlplane_nodes %}
    # If the minion is a control plane node, fail hard if this state is not successful
    - failhard: True
    {% endif %}

# Drain and cordon the node using the k8s-mgmt script on the first control plane node
{{ minion }}_k8s_prep_reboot:
  salt.function:
    - name: cmd.run
    # Target at the first control plane node
    - tgt: {{ controlplane_nodes[0] }}
    - arg:
        - /usr/local/sbin/k8s-mgmt -n {{ k8s_node_name }} -t drain
    {% if minion in controlplane_nodes %}
    # If the minion is a control plane node, fail hard if this state is not successful
    - failhard: True
    {% endif %}
    - require:
      - salt: {{ minion }}_check_minion_pings

# Install all available package updates
{{ minion }}_upgrade_packages:
  salt.function:
    - name: pkg.upgrade
    - tgt: {{ minion }}
    - kwarg:
        refresh: True
    - require:
      - {{ minion }}_k8s_prep_reboot

# Initiate a reboot
{{ minion }}_reboot:
  salt.function:
    - name: cmd.run
    - tgt: {{ minion }}
    - arg:
        - 'sleep 3s && reboot'
    - kwarg:
        bg: True
    - require:
      - salt: {{ minion }}_upgrade_packages

# Wait for the minion to start responding to Salt again
{{ minion }}_wait_for_online:
  salt.wait_for_event:
    - name: salt/minion/*/start
    # This state expects a list of minions, but we just want to watch for one
    - id_list: ['{{ minion }}']
    - timeout: 900  # wait up to 15 minutes
    - require:
      - salt: {{ minion }}_reboot

# Uncordon the node
{{ minion }}_k8s_prep_startup:
  salt.function:
    - name: cmd.run
    # Target at the first control plane node
    - tgt: {{ controlplane_nodes[0] }}
    # Add a grace period of 10 seconds before uncordoning the node
    - arg:
        - sleep 10 && /usr/local/sbin/k8s-mgmt -n {{ k8s_node_name }} -t uncordon
    {% if minion in controlplane_nodes %}
    # If the minion is a control plane node, fail hard if this state is not successful
    - failhard: True
    {% endif %}
    - require:
      - salt: {{ minion }}_wait_for_online

# Wait for the node to settle before moving on
{{ minion }}_wait:
  salt.function:
    - name: test.sleep
    - tgt: {{ minion }}
    - arg:
        {% if minion in controlplane_nodes %}
        # Pause a little longer between control plane nodes
        - 180
        {% else %}
        - 10
        {% endif %}
    - require:
      - {{ minion }}_k8s_prep_startup
