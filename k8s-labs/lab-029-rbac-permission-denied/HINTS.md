# Hints — Lab 029: RBAC Permission Denied

## Hint 1 — Test permissions
`kubectl auth can-i list pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa` shows if the SA has permission. Check each verb: get, list, watch.

## Hint 2 — Two issues
1. The Role is in the 'default' namespace but the RoleBinding is in 'monitoring'. Role and RoleBinding must be in the same namespace. 2. The Role is missing the 'list' verb.

## Hint 3 — Fix the Role
Delete the Role from default namespace, recreate it in monitoring namespace with all three verbs (get, list, watch), and reapply.
