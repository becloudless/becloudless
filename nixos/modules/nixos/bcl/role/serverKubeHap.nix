{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverKube;
  nodeName = n: "${cfg.clusterName}${toString n}";
in
{
  config = lib.mkIf (config.bcl.role.name == "serverKube") {
    environment.etc."kubernetes/manifests/haproxy-apiserver.yaml".text = ''
        apiVersion: v1
        kind: Pod
        metadata:
          annotations:
            scheduler.alpha.kubernetes.io/critical-pod: ""
          labels:
            component: haproxy
            tier: control-plane
          name: haproxy
          namespace: kube-system
        spec:
          containers:
          - image: haproxy:2.6.6
            livenessProbe:
              failureThreshold: 8
              httpGet:
                host: 127.0.0.1
                path: /
                port: 1936
                scheme: HTTP
              initialDelaySeconds: 15
              timeoutSeconds: 15
            name: haproxy-apiserver
            resources:
              requests:
                cpu: 250m
            volumeMounts:
            - mountPath: /usr/local/etc/haproxy
              name: hap-config
              readOnly: true
          hostNetwork: true
          priorityClassName: system-cluster-critical
          volumes:
          - name: hap-config
            hostPath:
              path: /etc/haproxy
      '';

    environment.etc."haproxy/haproxy.cfg" = {
      mode = "0644"; # copy file
      text = ''
        defaults
            maxconn 20000
            mode    tcp
            option  dontlognull
            timeout http-request 10s
            timeout queue        1m
            timeout connect      10s
            timeout client       86400s
            timeout server       86400s
            timeout tunnel       86400s

        listen stats-health
          mode http
          bind 127.0.0.1:1936
          monitor-uri /
          stats enable
          stats uri /stats

        frontend k8s-api
          bind :8443
          mode tcp
          default_backend k8s-api

        backend k8s-api
          option  httpchk GET /readyz HTTP/1.0
          option  log-health-checks
          http-check expect status 200
          mode tcp
          balance roundrobin
          default-server verify none check-ssl inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 5000 maxqueue 5000 weight 100
          server ${nodeName 1} ${nodeName 1}:6443 check
          server ${nodeName 2} ${nodeName 2}:6443 check
          server ${nodeName 3} ${nodeName 3}:6443 check
          server ${nodeName 4} ${nodeName 4}:6443 check
          server ${nodeName 5} ${nodeName 5}:6443 check
          server ${nodeName 6} ${nodeName 6}:6443 check
          server ${nodeName 7} ${nodeName 7}:6443 check
      '';
    };
  };
}