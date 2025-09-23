# This state needs to be executed on the target minion to 
# determine the os family grain properly
install_all_updates:
  pkg.uptodate:
    - refresh: True
    {% if grains['os_family'] == 'Debian' %}
    - dist_upgrade: True
    {% endif %}
