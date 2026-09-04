# AgentCore ハンズオン環境

Amazon Bedrock AgentCore のハンズオンを開催するための環境を Terraform で構築します。受講者はブラウザだけで参加でき、AWS の認証情報も手元の開発環境のセットアップも必要ありません。

![構成図](docs/images/architecture.png)

## この環境でできること

受講者は配布された URL を開いてパスワードを入力すると、ブラウザ上で VS Code（code-server）が立ち上がります。そこには Strands Agent の雛形と、エージェントの動きを可視化する画面が用意してあります。

まず手元でエージェントを動かしてループの仕組みを掴み、ツールを足して挙動が変わることを確かめ、最後に `agentcore deploy` の 1 行で自分のエージェントを Amazon Bedrock AgentCore Runtime に載せます。載せたあとも、呼び出しの様子は同じ画面で見られます。

主催者は開催前に `terraform apply` で受講者数ぶんの環境をまとめて作り、終わったら `terraform destroy` で消します。EC2 は起動している時間だけの課金なので、半日のハンズオンなら短時間の利用料で済みます。

## 設計の要点

**受講者に AWS の認証情報を配りません。** EC2 にインスタンスプロファイルを付けてあるので、EC2 の中で実行する AWS CLI も `agentcore deploy` もその権限で動きます。受講者が IAM ユーザーを受け取ったり、アクセスキーを設定したりする手順がまるごと不要になります。

**受講者の PC に何もインストールしません。** 入口は ALB で HTTPS を終端し、`user01.handson.example.com` のようなサブドメインで受講者ごとの EC2 に振り分けます。必要なのはブラウザだけなので、会社支給の PC でソフトを入れられない参加者も同じ手順で進められます。

**開発環境は AMI に焼いておきます。** code-server や AgentCore CLI のセットアップを起動のたびに実行すると、当日に人数ぶんの待ち時間とセットアップ失敗が発生します。事前に AMI を作っておけば、起動した時点で使える状態になります。

## ディレクトリ構成

```
.
├── README.md                     このファイル
├── CLAUDE.md                     エージェント向けの作業ルールと現在の状況
└── docs/
    ├── curriculum.md             ハンズオンの中身と組み立て
    ├── architecture.md           構成の詳細と、そう決めた理由
    ├── operations.md             事前準備・当日・後片付けの手順
    └── images/
        ├── architecture.drawio   構成図のソース
        ├── architecture.png      構成図
        ├── handson-flow.drawio   流れ図のソース
        └── handson-flow.png      ハンズオンの流れ
```

Terraform のコードと受講者に配る教材はこれから追加します。

## 前提条件

- AWS アカウント（主催者のもの1つ。受講者ぶんのアカウントは不要）
- Terraform
- 独自ドメイン（サブドメインを1つ使います）
- ハンズオンで使う AWS リージョンで Amazon Bedrock のモデルアクセスが有効になっていること

## ドキュメント

- [ハンズオンの中身](docs/curriculum.md) — 何をやってもらうか、なぜその順番か
- [構成の詳細](docs/architecture.md) — 何をどう組んでいるか、なぜその選択をしたか
- [運用手順](docs/operations.md) — 開催前の準備、当日の流れ、後片付け

## ステータス

設計フェーズです。構成図とドキュメントが先行していて、Terraform のコードと教材はこれから作ります。作業は [Issue](../../issues) で管理しています。
