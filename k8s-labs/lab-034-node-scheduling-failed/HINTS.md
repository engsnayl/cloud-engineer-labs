# Hints — Lab 034: Node Scheduling Failed

## Hint 1 — Check why it's pending
`kubectl describe pod -l app=critical-service` shows scheduling failures in the Events section. It tells you exactly why no node was suitable.

## Hint 2 — Node labels and taints
`kubectl get nodes --show-labels` shows node labels. `kubectl describe node <name> | grep Taint` shows taints. Compare with what the pod requires.

## Hint 3 — Fix the constraints
Remove or fix the nodeSelector if the label doesn't exist. Add a toleration for the node's taint. You might need to label a node: `kubectl label node <name> disk-type=nvme`.
