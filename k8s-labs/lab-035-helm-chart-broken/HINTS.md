# Hints — K8s Lab 035: Broken Helm Chart

## Hint 1 — Start with helm template
`helm template webapp ./webapp-chart` shows you ALL the errors without installing anything. Fix them one at a time.

## Hint 2 — Chart.yaml issues
- `apiVersion: v2` is required for Helm 3 (v1 is Helm 2)
- Add `name: webapp` — this is a required field
- `appVersion` should be a string: `appVersion: "1.0"`

## Hint 3 — Template syntax errors
- `{{ .Values.image.tag }` is missing a closing brace — should be `{{ .Values.image.tag }}`
- `.Values.image.imagePullPolicy` doesn't exist in values.yaml — it's `.Values.image.pullPolicy`

## Hint 4 — Values and selectors
- `appLabel` has a space ("web app") which is invalid for K8s labels — change to "webapp"
- Service port should be an integer: `port: 80` not `port: "80"`
- Service selector must match deployment labels: use `{{ .Values.appLabel }}` not `{{ .Release.Name }}`
