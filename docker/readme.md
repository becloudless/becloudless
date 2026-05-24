

```bash
# init buildx
docker buildx create --name mybuilder --bootstrap --use
# allow sudo on cross build
docker run --privileged multiarch/qemu-user-static:latest --reset -p yes --credential yes
```
