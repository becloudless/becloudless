
function y {
	types=(
			"video/anime"
			"video/clip"
			"video/crime"
			"video/doc"
			"video/history"
			"video/house"
			"video/interview"
			"video/movie"
			"video/tv"
			"video/science"
			"video/tech"
		)

	found=false
	for type in "${types[@]}"; do
		if [ "$type" = "$1" ]; then
			found=true
			break
		fi
	done
	if ! $found; then
    echo "wrong group: video/clip|video/house|video/doc|video/interview|video/history|video/science|video/tech"
    return
	fi

#  -i
#  local ARGS="-f 'bestvideo[ext=mp4][vcodec!*=av01]+bestaudio[ext=m4a]/mp4'"
#  if [[ "$1" == "audio/book" ]]; then
#    ARGS="--extract-audio --audio-format mp3"
#  fi

	export KUBECONFIG=/home/n0rad/Work/Perso/infra/.kube/bcl2.config

	kubectl get po -n dl -lrun=oneshot --field-selector=status.phase==Succeeded -o jsonpath="{.items[*].metadata.ownerReferences[0].name}" | xargs kubectl delete hr -n dl

  kubectl apply -f - <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: Hebclelease
metadata:
  name: yt-dlp-oneshot-$(date +'%d%m%Y%H%M%S')
  namespace: dl
spec:
  interval: 60m
  chart:
    spec:
      chart: charts/yt-dlp
      reconcileStrategy: Revision
      interval: 1m
      sourceRef:
        kind: GitRepository
        name: infra
        namespace: flux-system
  values:
    mainWorkload:
      type: Job
      container:
        env:
          ONESHOT: true
      pod:
        labels:
          run: oneshot
    playlists:
      ${1##*/}:
        - url: $2
EOF
}
