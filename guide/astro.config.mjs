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
      // コードブロックは暗い背景にして紙色の本文と対比を付ける（mcks.log のダーク側の色）。影は消す
      expressiveCode: {
        themes: ['github-dark'],
        styleOverrides: {
          borderRadius: '8px',
          borderColor: '#343228',
          codeBackground: '#24231c',
          frames: {
            shadowColor: 'transparent',
            editorTabBarBackground: '#1b1a15',
            editorTabBarBorderBottomColor: '#343228',
            editorActiveTabBackground: '#24231c',
            editorActiveTabForeground: '#edeadf',
            editorActiveTabIndicatorTopColor: '#82b391',
            editorActiveTabIndicatorBottomColor: 'transparent',
            terminalTitlebarBackground: '#1b1a15',
            terminalTitlebarBorderBottomColor: '#343228',
            terminalBackground: '#24231c',
          },
        },
      },
      // プロジェクターで見せるので常にライトテーマに固定する（切り替えボタンも消す）
      components: {
        ThemeProvider: './src/components/ThemeProvider.astro',
        ThemeSelect: './src/components/ThemeSelect.astro',
        Pagination: './src/components/Pagination.astro',
        Footer: './src/components/Footer.astro',
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
