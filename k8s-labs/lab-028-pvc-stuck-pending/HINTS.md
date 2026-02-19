# Hints — Lab 028: PVC Stuck Pending

## Hint 1 — Describe the PVC
`kubectl describe pvc db-pvc` shows WHY it's pending. Look at the Events section.

## Hint 2 — Three mismatches between PV and PVC
Compare `kubectl get pv db-pv -o yaml` with the PVC: 1. Access mode: PV has ReadWriteOnce, PVC has ReadWriteMany. 2. Size: PV has 10Gi, PVC requests 20Gi. 3. StorageClass: PV has fast-storage, PVC has standard.

## Hint 3 — Delete and recreate the PVC
You need to delete the PVC first (`kubectl delete pvc db-pvc`), fix the YAML to match the PV, then apply again.
