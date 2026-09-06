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
      // プロジェクターで見せるので常にライトテーマに固定する（切り替えボタンも消す）
      components: {
        ThemeProvider: './src/components/ThemeProvider.astro',
        ThemeSelect: './src/components/ThemeSelect.astro',
      },
      sidebar: [
        { label: 'はじめに', link: '/' },
        { label: '準備。配られた URL を開く', link: '/prep' },
        {
          label: 'ハンズオン',
          items: [
            { label: '1. 手元でエージェントを動かす', link: '/step1' },
            { label: '2. ツールを 1 つ足す', link: '/step2' },
            { label: '3. 会話を続けてみる', link: '/step3' },
            { label: '4. Runtime に載せる', link: '/step4' },
            { label: '5. 振り返りと片付け', link: '/step5' },
          ],
        },
        { label: '困ったとき', link: '/trouble' },
        { label: '受講者情報（合言葉が要る）', link: '/participants' },
      ],
      pagination: true,
      lastUpdated: false,
      credits: false,
    }),
  ],
});
