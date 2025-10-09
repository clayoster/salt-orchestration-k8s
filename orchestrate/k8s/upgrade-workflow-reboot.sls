# Separate state file so cmd.run can be used to require a 3 second
# sleep before issuing the reboot command. This gives the minion some
# time to process the reboot command before the minion goes offline.
k8s-reboot:
  cmd.run:
    - name: 'sleep 3s && reboot'
    - bg: True
