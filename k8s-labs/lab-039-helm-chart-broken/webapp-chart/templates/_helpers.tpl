{{/*
Common labels
*/}}
{{- define "webapp.labels" -}}
app: {{ .Values.appLabel }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}
