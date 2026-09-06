#!/bin/bash
# AMI に焼いた環境を前提に、起動時に受講者固有の値を差し込むスクリプト。
# templatefile 経由なので `$` は `$$` にエスケープする（波かっこを使わない
# 素の `$VAR` の形はエスケープ不要）。
#
# AMI（scripts/setup-instance.sh で作る）には code-server が
# code-server@handson として有効化済みで、config.yaml には
# password: CHANGE_ME_AT_BOOT というプレースホルダが入っている。
# ワークスペースの agentcore/agentcore.json と aws-targets.json にも
# handsonPARTICIPANT / 000000000000 というプレースホルダが焼き込まれている。
# ここではそれらを Terraform が渡した受講者固有の値に差し替える。
set -euo pipefail

CONFIG_FILE=/home/handson/.config/code-server/config.yaml
AGENTCORE_JSON=/home/handson/workspace/agentcore/agentcore.json
AWS_TARGETS_JSON=/home/handson/workspace/agentcore/aws-targets.json

# --- code-server のパスワード --------------------------------------------------
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

# --- agentcore CLI の設定 -------------------------------------------------------
# プロジェクト名（CloudFormation のスタック名にもなる）は受講者ごとに一意にする
# 必要があるため、AMI では handsonPARTICIPANT というプレースホルダにしてあり、
# ここで実名に差し替える。
sed -i "s/handsonPARTICIPANT/handson${participant}/" "$AGENTCORE_JSON"
# aws-targets.json のアカウント ID も同様にプレースホルダから実アカウントへ差し替える。
sed -i "s/000000000000/${account_id}/" "$AWS_TARGETS_JSON"

# --- workspace の README -------------------------------------------------------
# scripts/setup-instance.sh が書いた README.md には UI の URL のプレースホルダが
# 入っているので、受講者のホスト名から実 URL に差し替える。URL に `/` を含むため
# sed の区切り文字は `|` を使う。
sed -i "s|HANDSON_UI_URL_PLACEHOLDER|https://${hostname}/proxy/3000/|" /home/handson/workspace/README.md

# --- 受講者キーの記録 -----------------------------------------------------------
# 他のスクリプトやハンズオン UI から参照できるよう、受講者キーをファイルに残しておく。
install -d -m 755 /etc/handson
printf '%s\n' "${participant}" > /etc/handson/participant
chmod 644 /etc/handson/participant
