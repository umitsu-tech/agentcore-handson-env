# 受講者情報の表（手順書サイトの /participants.html が読む /participants/data.json）。
# 受講環境と寿命を揃えるため、この環境の apply で置き、destroy で消す（Issue #76）。
# guide_bucket_name を渡さない検証時は count = 0 で、表そのものを作らない。

variable "guide_bucket_name" {
  description = "受講者情報の表を置く手順書サイト（terraform/guide）のバケット名。`terraform -chdir=terraform/guide output -raw bucket_name` の値。null なら表は作らない"
  type        = string
  default     = null
}

locals {
  # participant_urls / participant_ui_urls / participant_passwords（outputs.tf）と同じ元の値
  # （local.participants と random_password.code_server）から、id 順の一覧を組み立てる。
  # 出力側の値は変えず、ここでは表の JSON を作るためだけに使う。
  participant_rows = [
    for id in sort(var.participants) : {
      id         = id
      editor_url = "https://${local.participants[id].hostname}"
      ui_url     = "https://${local.participants[id].hostname}/proxy/3000/"
      password   = random_password.code_server[id].result
    }
  ]
}

# ページに出す「…時点」の時刻。毎回の apply で更新されると destroy するまで差分が出続けるので、
# timestamp() ではなく time_static を使う。triggers が変わったとき（表の中身が変わったとき）だけ
# リソースが置き換わり、rfc3339 がそのときの時刻で更新される。受講者の一覧だけでなく、
# パスワードを作り直したときにも更新されるよう、表の中身のハッシュを見る（パスワードを含むので
# plan では sensitive と表示される）。
resource "time_static" "participants_generated_at" {
  count = var.guide_bucket_name != null ? 1 : 0

  triggers = {
    rows = sha256(jsonencode(local.participant_rows))
  }
}

resource "aws_s3_object" "participants_data" {
  count = var.guide_bucket_name != null ? 1 : 0

  bucket        = var.guide_bucket_name
  key           = "participants/data.json"
  content_type  = "application/json; charset=utf-8"
  cache_control = "no-cache"

  # パスワードを作り直すと EC2 も作り直しになる（user_data に入っているため）。表が先に
  # 新しいパスワードになってログインできない時間ができないよう、EC2 の作成を待ってから置く
  depends_on = [aws_instance.participant]

  content = jsonencode({
    generated_at = time_static.participants_generated_at[0].rfc3339
    participants = local.participant_rows
  })

  # CloudFront（/participants* だけ CachingOptimized、最小 TTL 1 秒）はオリジンが no-cache を
  # 返すとその最小 TTL しかキャッシュしない。次のアクセスでオリジンへ聞きに行くので、
  # apply のたびにキャッシュ削除（invalidation）をしなくても数秒で新しい内容に切り替わる。
}
