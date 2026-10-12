#!/usr/bin/env bash
# launch_test_container.sh <name> <seccomp-profile.json|unconfined>  -- mirrors the live Hermes sandbox flags
N=${1:?}; P=${2:?}; HERE=$(cd "$(dirname "$0")/.." && pwd)
docker rm -f "$N" >/dev/null 2>&1; mkdir -p "$HERE/scratch_ws"
SEC=unconfined; [ "$P" != unconfined ] && SEC=$(readlink -f "$P"); SECARG="seccomp=$SEC"; [ "$P" = default ] && SECARG="no-new-privileges"
docker run -d --init --name "$N" --security-opt "$SECARG" --cap-drop ALL --cap-add DAC_OVERRIDE --cap-add CHOWN --cap-add FOWNER \
  --security-opt no-new-privileges --pids-limit 512 --network hermes-sbx --user 1000:1000 \
  --tmpfs /tmp:rw,nosuid,size=512m --tmpfs /var/tmp:rw,noexec,nosuid,size=256m --tmpfs /run:rw,noexec,nosuid,size=64m \
  -v "$HERE/scratch_ws":/workspace:rw -v "$HOME/Documents":/ro/Documents:ro \
  --gpus=all --device=/dev/nvidia0 --device=/dev/nvidia1 --device=/dev/nvidiactl --device=/dev/nvidia-uvm --device=/dev/nvidia-uvm-tools \
  -w /workspace hermes-sandbox:nim sleep infinity
