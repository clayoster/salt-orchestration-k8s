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

{% for minion in reboot_list %}

{{ minion }}_check_minion_pings:
  salt.function:
    - name: test.ping
    - tgt: {{ minion }}
    #- tgt_type: list
    {% if minion in controlplane_nodes %}
    # If the minion is critical (control plane) fail hard if the minion is not online
    - failhard: True
    {% endif %}
    - require:
      - salt: check_controlplane_pings

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
        #- 'sleep 3s && shutdown -r -t 0'
        - 'sleep 3s && reboot'
    - kwarg:
        bg: True
    - require:
      - salt: {{ minion }}_upgrade_packages

# Define a list for use in wait_for_event
{% set minion_reboot = [minion] %}

{{ minion }}_wait_for_online:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list: {{ minion_reboot }}
    - timeout: 900  # wait up to 15 minutes
    - require:
      - salt: {{ minion }}_reboot

{{ minion }}_k8s_prep_startup:
  salt.function:
    - name: cmd.run
    # Target at the first control plane node
    - tgt: {{ controlplane_nodes[0] }}
    - arg:
        - /usr/local/sbin/k8s-mgmt -n {{ minion }} -t uncordon
    {% if minion in controlplane_nodes %}
    # If the minion is critical (control plane) fail hard if the minion is not online
    - failhard: True
    {% endif %}
    - require:
      - {{ minion }}_upgrade_packages

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

{% endfor %}
