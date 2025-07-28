{% set minion = salt['pillar.get']('minion') %}
{% set controlplane_nodes = salt['pillar.get']('controlplane_nodes') %}

{{ minion }}_check_minion_pings:
  salt.function:
    - name: test.ping
    - tgt: {{ minion }}
    #- tgt_type: list
    {% if minion in controlplane_nodes %}
    # If the minion is critical (control plane) fail hard if the minion is not online
    - failhard: True
    {% endif %}

{{ minion }}_k8s_prep_reboot:
  salt.function:
    - name: cmd.run
    # Target at the first control plane node
    - tgt: {{ controlplane_nodes[0] }}
    - arg:
        - /usr/local/sbin/k8s-mgmt -n {{ minion }} -t drain
    {% if minion in controlplane_nodes %}
    # If the minion is critical (control plane) fail hard if the minion is not online
    - failhard: True
    {% endif %}
    - require:
      - salt: {{ minion }}_check_minion_pings

{{ minion }}_upgrade_packages:
  salt.function:
    - name: pkg.upgrade
    - tgt: {{ minion }}
    - kwarg:
        refresh: True
    - require:
      - {{ minion }}_k8s_prep_reboot

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

{{ minion }}_wait_for_online:
  salt.wait_for_event:
    - name: salt/minion/*/start
    # This state expects a list of minions, but we just want to watch for one
    - id_list: ['{{ minion }}']
    - timeout: 900  # wait up to 15 minutes
    - require:
      - salt: {{ minion }}_reboot

{{ minion }}_k8s_prep_startup:
  salt.function:
    - name: cmd.run
    # Target at the first control plane node
    - tgt: {{ controlplane_nodes[0] }}
    # Add a grace period before uncordoning the node
    - arg:
        - sleep 10 && /usr/local/sbin/k8s-mgmt -n {{ minion }} -t uncordon
    {% if minion in controlplane_nodes %}
    # If the minion is critical (control plane) fail hard if the minion is not online
    - failhard: True
    {% endif %}
    - require:
      - salt: {{ minion }}_wait_for_online

# wait for the node to settle before moving on
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
