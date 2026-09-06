// 受講者向け手順書のサイト設定。
// S3 + CloudFront OAC はフォルダ形式の URL（/step1/）で index.html を補わないので、
// build.format を 'file' にして step1.html のようにファイル名で出力する。
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  build: { format: 'file' },
  trailingSlash: 'never',
  integrations: [
    starlight({
      title: 'AgentCore ハンズオン',
      locales: { root: { label: '日本語', lang: 'ja' } },
      customCss: ['./src/styles/custom.css'],
      // コードブロックはライト 1 つだけ。枠は影を消して線だけにする
      expressiveCode: {
        themes: ['github-light'],
        styleOverrides: {
          borderRadius: '8px',
          borderColor: '#e4e1d4',
          codeBackground: '#f7f6ef',
          frames: {
            shadowColor: 'transparent',
            editorTabBarBackground: '#f1efe6',
            editorActiveTabBackground: '#f7f6ef',
            editorActiveTabIndicatorTopColor: '#4a7c59',
            editorActiveTabIndicatorBottomColor: 'transparent',
            terminalTitlebarBackground: '#f1efe6',
            terminalBackground: '#f7f6ef',
          },
        },
      },
      // プロジェクターで見せるので常にライトテーマに固定する（切り替えボタンも消す）
      components: {
        ThemeProvider: './src/components/ThemeProvider.astro',
        ThemeSelect: './src/components/ThemeSelect.astro',
      },
      sidebar: [
        { label: 'はじめに', link: '/' },
        { label: '事前準備', link: '/prep' },
        {
          label: 'ハンズオン',
          items: [
            { label: '1. 手元での実行', link: '/step1' },
            { label: '2. ツールの追加', link: '/step2' },
            { label: '3. 会話の継続', link: '/step3' },
            { label: '4. Runtime へのデプロイ', link: '/step4' },
            { label: '5. 振り返りと片付け', link: '/step5' },
          ],
        },
        { label: 'トラブルシューティング', link: '/trouble' },
        { label: '受講者情報（合言葉が要る）', link: '/participants' },
      ],
      pagination: true,
      lastUpdated: false,
      credits: false,
    }),
  ],
});
