# 受講者に AWS の認証情報を配らないかわりに、EC2 のインスタンスプロファイルへ
# ハンズオンに必要な権限を持たせる。EC2 の中で叩く AWS CLI も agentcore deploy も
# このロールの権限で動くので、受講者が自分の認証情報を持つ必要がない。
resource "aws_iam_role" "instance" {
  name = "${local.name}-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# 管理者が Session Manager で入れるようにする。受講者はこの経路を使わない。
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "agentcore" {
  name = "${local.name}-agentcore"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AgentCore"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateAgentRuntime",
          "bedrock-agentcore:UpdateAgentRuntime",
          "bedrock-agentcore:DeleteAgentRuntime",
          "bedrock-agentcore:GetAgentRuntime",
          "bedrock-agentcore:ListAgentRuntimes",
          "bedrock-agentcore:ListAgentRuntimeVersions",
          "bedrock-agentcore:CreateAgentRuntimeEndpoint",
          "bedrock-agentcore:UpdateAgentRuntimeEndpoint",
          "bedrock-agentcore:DeleteAgentRuntimeEndpoint",
          "bedrock-agentcore:GetAgentRuntimeEndpoint",
          "bedrock-agentcore:ListAgentRuntimeEndpoints",
          "bedrock-agentcore:InvokeAgentRuntime",
        ]
        Resource = "*"
      },
      {
        # agentcore deploy は Runtime 作成にあわせて既定のワークロードアイデンティティも
        # 作る（aws/agentcore-cli の docs/policies/iam-policy-user.json の
        # AgentCoreResourceManagement 相当。identity/credential provider を使わなくても
        # 無条件で要る）。agentcore.json の tags もここで付与される。
        Sid    = "AgentCoreWorkloadIdentityAndTags"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateWorkloadIdentity",
          "bedrock-agentcore:DeleteWorkloadIdentity",
          "bedrock-agentcore:TagResource",
          "bedrock-agentcore:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        # AgentCore Runtime の実行ロールは CLI が自動で作る。事前に作って渡すことが
        # できないため（aws/agentcore-cli #870）、作成権限を持たせる必要がある。
        # 対象は BedrockAgentCore 系のロール名に限定する。
        Sid    = "AgentCoreExecutionRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/*BedrockAgentCore*"
      },
      {
        Sid      = "PassExecutionRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/*BedrockAgentCore*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "bedrock-agentcore.amazonaws.com"
          }
        }
      },
      {
        # agentcore deploy は内部で AWS CDK を使ってデプロイする。
        # そのため CloudFormation と、ブートストラップで作られるロールを引く権限が要る。
        Sid    = "CdkDeploy"
        Effect = "Allow"
        Action = [
          "cloudformation:CreateStack",
          "cloudformation:UpdateStack",
          "cloudformation:DeleteStack",
          "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackEvents",
          "cloudformation:DescribeStackResources",
          "cloudformation:GetTemplate",
          "cloudformation:CreateChangeSet",
          "cloudformation:DescribeChangeSet",
          "cloudformation:ExecuteChangeSet",
          "cloudformation:DeleteChangeSet",
          "cloudformation:GetTemplateSummary",
        ]
        Resource = "*"
      },
      {
        Sid      = "AssumeCdkBootstrapRoles"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/cdk-*"
      },
      {
        # agentcore deploy（内部の CDK）はデプロイ前に CDKToolkit のブートストラップ
        # バージョンを SSM パラメータで確認する。
        Sid    = "CdkBootstrapVersionLookup"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/cdk-bootstrap/*"
      },
      {
        Sid    = "AgentCodeBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:CreateBucket",
          "s3:PutLifecycleConfiguration",
          "s3:GetBucketLocation",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::bedrock-agentcore-*",
          "arn:${data.aws_partition.current.partition}:s3:::bedrock-agentcore-*/*",
          "arn:${data.aws_partition.current.partition}:s3:::cdk-*",
          "arn:${data.aws_partition.current.partition}:s3:::cdk-*/*",
        ]
      },
      {
        # 東京は In-Region 呼び出しに非対応なので推論プロファイル経由で呼ぶ。
        # プロファイル本体と、その先で実際に叩かれる基盤モデルの両方を許可する。
        Sid    = "InvokeModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/${var.model_inference_profile}",
          "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*",
        ]
      },
      {
        Sid    = "ReadOwnLogs"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:StartLiveTail",
        ]
        Resource = "*"
      },
      {
        # Runtime のロググループは CLI がデプロイ時に自分で作る（aws/agentcore-cli の
        # docs/policies/iam-policy-user.json の LogsStreamingAndSearch 相当のうち、
        # デプロイに要る書き込み系だけを切り出した）。
        Sid    = "AgentCoreExecutionLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/*",
          "arn:${data.aws_partition.current.partition}:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/*:*",
        ]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name
}
