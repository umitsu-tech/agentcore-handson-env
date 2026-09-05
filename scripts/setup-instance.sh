#!/bin/bash
# 受講者用インスタンスのセットアップ。AMI を焼くときに 1 回だけ実行する。
#
# 当日 30 台が同時にパッケージを取りに行くと待たされるうえ、失敗した数台の
# デバッグに張り付くことになる。ここで入れたものを AMI に焼き込んでおけば、
# 当日は起動するだけで使える状態になる。
#
# ワークスペース（受講者の EC2 に置くファイル一式）は S3 から取得する。バケットとキーは環境変数で渡す。
# アーカイブは handson-agent/・handson-ui/・agentcore/（agentcore deploy 用の CLI 設定と
# CDK コード一式）の3ディレクトリを含む。
# リポジトリ直下で `tar -czf handson-workspace.tar.gz handson-agent handson-ui agentcore` のように作る
# （node_modules・.venv・frontend/dist・agentcore/.cli・agentcore/.env.local は含めない）。
set -euxo pipefail

ASSET_BUCKET="${ASSET_BUCKET:-}"
ASSET_KEY="${ASSET_KEY:-handson-workspace.tar.gz}"

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
# agentcore deploy は内部で CDK を使うので両方入れる。
# agentcore/ 配下（agentcore.json・cdk/ のコード）は npx @aws/agentcore@latest で
# 生成したものを AMI に焼き込んでいるため、生成時と異なるバージョンの CLI で
# deploy すると噛み合わない可能性がある。バージョンを固定する。
npm install -g aws-cdk @aws/agentcore@0.28.1
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

# --- ワークスペース -----------------------------------------------------------
# handson-agent/・handson-ui/ に加えて agentcore/（agentcore deploy 用の CLI 設定と
# CDK コード）もここで展開される。agentcore/agentcore.json と aws-targets.json には
# handson_PARTICIPANT / 000000000000 のプレースホルダが入っており、実際の値への
# 差し替えは起動時に scripts/configure-instance.sh が行う。
if [ -n "$ASSET_BUCKET" ]; then
  aws s3 cp "s3://${ASSET_BUCKET}/${ASSET_KEY}" /tmp/handson-workspace.tar.gz
  tar -xzf /tmp/handson-workspace.tar.gz -C /home/handson/workspace
  rm -f /tmp/handson-workspace.tar.gz
  chown -R handson:handson /home/handson/workspace

  # 依存の取得と画面のビルドまで済ませておく。当日ここで待たせないため
  pushd /home/handson/workspace/handson-agent
  sudo -u handson env PATH="$PATH" uv sync
  popd

  pushd /home/handson/workspace/handson-ui
  sudo -u handson env PATH="$PATH" uv sync
  sudo -u handson env PATH="$PATH" npm --prefix frontend ci
  sudo -u handson env PATH="$PATH" npm --prefix frontend run build
  popd

  # agentcore deploy は実行のたびに agentcore/cdk で依存の同期（package.json が
  # CLI の同梱テンプレートと食い違っているか、node_modules が無ければ npm install）と
  # npm run build（tsc）を自分で行う。node_modules を先に入れておけば、CLI のバージョンを
  # 固定してある限り package.json は一致し、npm install はスキップされる（node_modules の
  # 有無と依存の差分だけで判断される）。npm run build（tsc）は毎回走るが、node_modules が
  # 揃っていれば数秒で終わるので待ち時間の問題にはならない。package-lock.json が無いので
  # npm ci は使えず、ここでは npm install を使う。
  pushd /home/handson/workspace/agentcore/cdk
  sudo -u handson env PATH="$PATH" npm install
  sudo -u handson env PATH="$PATH" npm run build
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
WorkingDirectory=/home/handson/workspace/handson-ui
Environment=AWS_REGION=ap-northeast-1
Environment=HANDSON_AGENT_DIR=/home/handson/workspace/handson-agent
ExecStart=/usr/local/bin/uv run uvicorn server:app --host 127.0.0.1 --port 3000 --reload --reload-dir /home/handson/workspace/handson-agent
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
