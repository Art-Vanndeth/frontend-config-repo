{{- define "cstad-frontend.fullname" -}}
{{- printf "%s-%s" .Chart.Name .Values.environment | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cstad-frontend.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
environment: {{ .Values.environment }}
{{- end -}}

