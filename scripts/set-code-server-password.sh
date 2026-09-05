#!/bin/bash
# AMI に焼いた環境を前提に、起動時にパスワードを差し込むだけのスクリプト。
# templatefile 経由なので `$` は `$$` にエスケープする。
#
# AMI（scripts/setup-instance.sh で作る）には code-server が
# code-server@handson として有効化済みで、config.yaml には
# password: CHANGE_ME_AT_BOOT というプレースホルダが入っている。
# ここでは Terraform が生成したパスワードに差し替えて再起動するだけ。
set -euo pipefail

CONFIG_FILE=/home/handson/.config/code-server/config.yaml

sed -i "s/^password: CHANGE_ME_AT_BOOT$/password: ${code_server_password}/" "$CONFIG_FILE"
chown handson:handson "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

systemctl restart code-server@handson

# ALB のヘルスチェックが通るまで待つ。code-server は /healthz を返す
for _ in $(seq 1 30); do
  if curl -fsS http://localhost:8080/healthz > /dev/null; then
    echo "code-server is up"
    break
  fi
  sleep 2
done
