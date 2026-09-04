#!/bin/bash
# 受講者用インスタンスの初期セットアップ。
#
# Terraform の templatefile から user_data として渡される。テンプレート構文は
# コメント行の中でも展開されるので、シェル側で同じ形を書きたいときは
# $$ と %% でエスケープすること。コマンド置換の $(...) は解釈されないのでそのまま書ける。
#
# 開発環境一式（Python / uv / AgentCore CLI など）はここでは入れない。
# 当日 30 台が同時にパッケージを取りに行くと待たされるうえ、失敗した数台の
# デバッグに張り付くことになるため、それらは AMI に焼き込む（Issue #5）。
# このスクリプトは AMI ができるまでの間、単体で動作確認するために使う。
set -euxo pipefail

dnf update -y

# 受講者が作業するユーザー。code-server はこのユーザーで動かす
useradd --create-home --shell /bin/bash handson || true
install -d -o handson -g handson /home/handson/workspace

curl -fsSL https://code-server.dev/install.sh | sh

install -d -o handson -g handson /home/handson/.config/code-server
cat > /home/handson/.config/code-server/config.yaml <<'CONFIG'
bind-addr: 0.0.0.0:8080
auth: password
cert: false
CONFIG

# パスワードは Terraform が生成したものを使う。
# 平文で置くことになるが、インスタンスへの経路は ALB からの 8080 だけで、
# メタデータも IMDSv2 必須にしてある。
echo "password: ${code_server_password}" >> /home/handson/.config/code-server/config.yaml
chown -R handson:handson /home/handson/.config
chmod 600 /home/handson/.config/code-server/config.yaml

systemctl enable --now "code-server@handson"

# ALB のヘルスチェックが通るまで待つ。code-server は /healthz を返す
for _ in $(seq 1 30); do
  if curl -fsS http://localhost:8080/healthz > /dev/null; then
    echo "code-server is up"
    break
  fi
  sleep 2
done
