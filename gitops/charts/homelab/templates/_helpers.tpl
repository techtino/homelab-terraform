{{/*
Every routed name, as name => { namespace, service, port, auth }.
*/}}
{{- define "homelab.routes" -}}
{{- $routes := dict -}}
{{- range $name, $app := .Values.apps -}}
{{- $_ := set $routes $name (dict "namespace" $.Release.Namespace "service" $name "port" ($app.port | default 80) "auth" ($app.auth | default false)) -}}
{{- end -}}
{{- range $name, $route := .Values.routes -}}
{{- $_ := set $routes $name (dict "namespace" $route.namespace "service" ($route.service | default $name) "port" $route.port "auth" ($route.auth | default false)) -}}
{{- end -}}
{{- range $name, $svc := .Values.external -}}
{{- $_ := set $routes $name (dict "namespace" "traefik" "service" $name "port" $svc.port "auth" false) -}}
{{- end -}}
{{- toYaml $routes -}}
{{- end -}}
