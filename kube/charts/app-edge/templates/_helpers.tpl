{{- /*
The address of an edge node in the tunnel network when `nodes.<name>.tunnelAddress` is not set: the number at the end of its name
is the host number in the network of `tunnel.address`/`tunnel.prefixLength` (`edge1` in 10.99.0.0/24 is 10.99.0.1), like the default of
`bcl.edge.address` of the NixOS module.
Arguments: `root` (the context of the chart) and `name`.
*/}}
{{- define "app-edge.tunnelAddress" -}}
{{- $octets := splitList "." .root.Values.tunnel.address }}
{{- $ip := add (mul (int (index $octets 0)) 16777216) (mul (int (index $octets 1)) 65536) (mul (int (index $octets 2)) 256) (int (index $octets 3)) }}
{{- $size := 1 }}
{{- range until (int (sub 32 (int .root.Values.tunnel.prefixLength))) }}
  {{- $size = mul $size 2 }}
{{- end }}
{{- $suffix := regexFind "[0-9]+$" .name }}
{{- if not $suffix }}
  {{- fail (printf "the edge node %q has no tunnelAddress and no number at the end of its name to get one from" .name) }}
{{- end }}
{{- $n := add (sub $ip (mod $ip $size)) (atoi $suffix) }}
{{- printf "%d.%d.%d.%d" (mod (div $n 16777216) 256) (mod (div $n 65536) 256) (mod (div $n 256) 256) (mod $n 256) }}
{{- end }}
