#!/bin/bash
# 受講者用インスタンスのセットアップ。AMI を焼くときに 1 回だけ実行する。
#
# 当日 30 台が同時にパッケージを取りに行くと待たされるうえ、失敗した数台の
# デバッグに張り付くことになる。ここで入れたものを AMI に焼き込んでおけば、
# 当日は起動するだけで使える状態になる。
#
# 教材は S3 から取得する。バケットとキーは環境変数で渡す。
set -euxo pipefail

ASSET_BUCKET="${ASSET_BUCKET:-}"
ASSET_KEY="${ASSET_KEY:-handson-agent.tar.gz}"

dnf update -y
dnf install -y git tar gzip

# --- 受講者が作業するユーザー -------------------------------------------------
useradd --create-home --shell /bin/bash handson || true
install -d -o handson -g handson /home/handson/workspace

# --- Node.js（AgentCore CLI と画面のビルドに必要） -----------------------------
# AL2023 の既定は古いので、NodeSource から 22 系を入れる
curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
dnf install -y nodejs
node --version

# --- Python と uv -------------------------------------------------------------
# pip は入れない。依存の解決も仮想環境も uv がやるので使う場面がない
dnf install -y python3.12
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
uv --version

# --- AWS CDK と AgentCore CLI -------------------------------------------------
# agentcore deploy は内部で CDK を使うので両方入れる
npm install -g aws-cdk @aws/agentcore
cdk --version
agentcore --version

# --- code-server --------------------------------------------------------------
# インストーラが HOME を参照するが、cloud-init の実行環境には設定されていない。
# set -u と組み合わさって unbound variable で落ちるため、明示的に渡す。
export HOME="${HOME:-/root}"
# 入っている状態で流し直すと rpm -U が失敗して止まるので、その場合は飛ばす
if ! command -v code-server > /dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi

install -d -o handson -g handson /home/handson/.config/code-server
cat > /home/handson/.config/code-server/config.yaml <<'CONFIG'
bind-addr: 0.0.0.0:8080
auth: password
cert: false
password: CHANGE_ME_AT_BOOT
CONFIG
chown -R handson:handson /home/handson/.config
chmod 600 /home/handson/.config/code-server/config.yaml

systemctl enable code-server@handson

# --- 教材 ---------------------------------------------------------------------
if [ -n "$ASSET_BUCKET" ]; then
  aws s3 cp "s3://${ASSET_BUCKET}/${ASSET_KEY}" /tmp/handson-agent.tar.gz
  tar -xzf /tmp/handson-agent.tar.gz -C /home/handson/workspace
  rm -f /tmp/handson-agent.tar.gz
  chown -R handson:handson /home/handson/workspace

  # 依存の取得と画面のビルドまで済ませておく。当日ここで待たせないため
  pushd /home/handson/workspace/handson-agent
  sudo -u handson env PATH="$PATH" uv sync
  sudo -u handson env PATH="$PATH" npm --prefix frontend ci
  sudo -u handson env PATH="$PATH" npm --prefix frontend run build
  popd
fi

# --- ハンズオン UI を自動起動 --------------------------------------------------
cat > /etc/systemd/system/handson-ui.service <<'UNIT'
[Unit]
Description=Handson UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=handson
WorkingDirectory=/home/handson/workspace/handson-agent
Environment=AWS_REGION=ap-northeast-1
ExecStart=/usr/local/bin/uv run uvicorn ui:app --host 127.0.0.1 --port 3000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable handson-ui

# --- 使用量の記録（AMI のサイズを決める材料にする） ---------------------------
{
  echo "=== ディスク ==="
  df -h /
  echo "=== 大きいディレクトリ ==="
  du -sh /home/handson/workspace /usr/lib/node_modules /usr/lib/code-server 2>/dev/null || true
  echo "=== メモリ ==="
  free -m
} > /var/log/handson-setup-usage.log 2>&1

echo "セットアップ完了"
