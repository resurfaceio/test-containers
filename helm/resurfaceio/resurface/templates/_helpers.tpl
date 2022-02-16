{{/*
Expand the name of the chart.
*/}}
{{- define "resurface.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "resurface.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains .Release.Name $name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "resurface.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "resurface.labels" -}}
helm.sh/chart: {{ include "resurface.chart" . }}
{{ include "resurface.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "resurface.selectorLabels" -}}
app.kubernetes.io/name: {{ include "resurface.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Default options: container resources and persistent volumes
*/}}
{{- define "resurface.resources" -}}
{{- $sizeDict := dict }}
{{- if eq .Values.size "orca" -}}
{{- $sizeDict = dict "cpu" 3 "memory" 8 "DB_SIZE" 4 "DB_HEAP" 3 "DB_SLABS" 2 -}}
{{- else if eq .Values.size "humpback" }}
{{- $sizeDict = dict "cpu" 6 "memory" 16 "DB_SIZE" 12 "DB_HEAP" 3 "DB_SLABS" 4 -}}
{{- else -}}
{{- required "Size must be either \"orca\" or \"humpback\"" "" -}}
{{- end }}
          resources:
            requests:
              cpu: {{ .Values.custom.resources.cpu | default (get $sizeDict "cpu") }}
              memory: {{ .Values.custom.resources.memory | default (get $sizeDict "memory") | printf "%vGi" }}
          env:
            - name: DB_SIZE
              value: {{ .Values.custom.config.dbsize | default (get $sizeDict "DB_SIZE") | printf "%dg" }}
            - name: DB_HEAP
              value: {{ .Values.custom.config.dbheap | default (get $sizeDict "DB_HEAP") | printf "%dg" }}
            - name: DB_SLABS
              value: {{ .Values.custom.config.dbslabs | default (get $sizeDict "DB_SLABS") | quote }}
            {{- if .Values.custom.config.tz }}
            - name: TZ
              value: {{ .Values.custom.config.tz | quote }}
            {{- end}}
  volumeClaimTemplates:
    - metadata:
        name: {{ include "resurface.fullname" . }}-pvc
      spec:
        storageClassName: {{ .Values.custom.storage.classname | default (get (dict "azure" "managed-csi" "aws" "gp2" "gcp" "pd-standard") .Values.provider) }}
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: {{ .Values.custom.storage.size | default (get $sizeDict "memory") | printf "%vGi" }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "resurface.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "resurface.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
