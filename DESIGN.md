# 楽市楽問 UI Design Specification

## 1. Purpose

本書は、画面追加・改修時にデザインの一貫性を維持するための基準を定義する。

対象は
**見た目・レイアウト・コンポーネント・状態表現**。実装フレームワークやバックエンド仕様は規定しない。

------------------------------------------------------------------------

## 2. Design Concept

### Core identity

**Japanese AI Marketplace × Dark Premium × Manga / Battle Graphic**

基本構成は、黒を主体とした高密度なプロダクトUIに、金・赤をアクセントとして使用する。

-   **Black**: UIの基盤。背景、パネル、ナビゲーション。
-   **Gold**: ブランド、主要CTA、選択状態、価値・評価。
-   **Red**: 勢い、注目、強調、バトル・SPECIAL表現。
-   **White**: 主情報、可読性、検索・入力領域。
-   **Graphic texture**:
    斜線、ブラシ、ハーフトーン、漫画的な集中線を限定的に使用。

重要な原則：

> 通常操作領域は静かに、成果・訴求領域だけ大胆にする。

全面を漫画表現にせず、情報UIと広告的グラフィックを明確に分離する。

------------------------------------------------------------------------

## 3. Visual Hierarchy

画面の視覚優先順位は以下。

1.  **Primary Action / Primary Result**
2.  **Current Context**
3.  **Main Content**
4.  **Secondary Navigation**
5.  **Metadata / Utility**

強調方法を混在させない。

-   Primary CTA → Gold fill
-   Critical / Special emphasis → Red
-   Selected navigation → Gold line / subtle gold background
-   Standard content → White / gray
-   Metadata → muted gray

------------------------------------------------------------------------

## 4. Color System

実装時は色を直接記述せずDesign Token化する。

``` css
:root {
  --color-bg: #070707;
  --color-bg-elevated: #0d0d0d;
  --color-surface: #121212;
  --color-surface-hover: #181818;
  --color-border: #292929;

  --color-text-primary: #f2f2f2;
  --color-text-secondary: #a7a7a7;
  --color-text-muted: #707070;

  --color-brand-gold: #d7a43b;
  --color-brand-gold-light: #efc66c;
  --color-brand-red: #d51d25;

  --color-success: #4f9a58;
  --color-warning: #d7a43b;
  --color-danger: #d51d25;
}
```

数値はスクリーンショットからの近似値であり、既存コードに正式なブランドカラーがある場合は既存Tokenを優先する。

### Gold usage

Goldは以下に限定する。

-   Primary CTA
-   Logo / brand accents
-   Selected state
-   Rating
-   Important numeric value
-   Decorative lines

Goldを本文色として大量使用しない。

### Red usage

Redはさらに限定する。

-   SPECIAL / Battle
-   Attention graphic
-   強いキャンペーン訴求
-   Error / destructive action

通常CTAにRedを使わない。

------------------------------------------------------------------------

## 5. Typography

### General

日本語UIでは可読性を最優先する。

推奨：

``` css
font-family:
  "Noto Sans JP",
  "Hiragino Kaku Gothic ProN",
  sans-serif;
```

### Hierarchy

  Role                Weight   Approx. size
  --------------- ---------- --------------
  Hero headline     800--900       48--72px
  Page title             700       28--34px
  Section title          700       18--22px
  Card title        600--700       14--18px
  Body              400--500       13--16px
  Metadata               400       11--13px

HeroやSPECIAL領域では極太・斜体・ブラシ系のDisplay
Typographyを使用してよい。

通常UIでは使用しない。

------------------------------------------------------------------------

## 6. Layout System

### Desktop

基本構造：

``` text
┌─────────────────────────────────────────────────────┐
│ Global Header                                       │
├──────────────┬─────────────────────┬────────────────┤
│ Navigation   │ Main Content        │ Context Panel  │
│ / History    │                     │ optional       │
└──────────────┴─────────────────────┴────────────────┘
```

### Width behavior

-   Global header: full width
-   Main content: fluid
-   Sidebar: fixed / semi-fixed
-   Content max width: page typeごとに設定
-   Major sections間は24--32px程度を基本単位とする

### Grid

8px gridを基本とする。

``` text
4px   micro
8px   base
12px  compact
16px  standard
24px  section
32px  major
48px+ hero
```

------------------------------------------------------------------------

## 7. Global Header

共通ヘッダーはブランド認識と主要導線に集中する。

構成：

``` text
Logo
Primary Navigation
Search
Notification
Theme / Utility
User
```

### Rules

-   背景はほぼBlack。
-   下境界は非常に弱い。
-   Logoは左端。
-   Navigationは横並び。
-   Searchはデスクトップでは中央〜右側に十分な幅を確保。
-   User controlsは右端。
-   Goldは常時大量表示せず、現在地またはCTAに限定。

------------------------------------------------------------------------

## 8. Navigation

### Primary navigation

通常状態：

-   White / light gray text
-   Background transparent

Hover：

-   text brightens
-   subtle surface background

Active：

-   Gold accent
-   必要に応じてbottom border / side border

### Side navigation

マイページでは左Sidebarを使用。

``` text
Dashboard
────────────
Publisher Menu
  Skills
  Drafts
  Revenue
  Analytics
  Reviews
  Transactions
────────────
Account
  Profile
  Settings
  API
  Billing
  Notifications
  Security
```

現在位置はGoldのvertical indicatorとsurface highlightで示す。

------------------------------------------------------------------------

## 9. Cards

カードは情報の基本単位。

``` css
background: var(--color-surface);
border: 1px solid var(--color-border);
border-radius: 8px;
```

原則として強いdrop shadowは使用しない。

階層は、

-   background difference
-   border
-   spacing

で作る。

### Card anatomy

``` text
┌──────────────────────────────┐
│ Icon   Title          Status │
│        Category              │
│                              │
│ Primary information          │
│                              │
│ Metadata / actions           │
└──────────────────────────────┘
```

------------------------------------------------------------------------

## 10. Buttons

### Primary

Gold background + dark text。

用途：

-   検索
-   実行
-   出品開始
-   新規作成
-   最重要Action

### Secondary

Dark surface + border + light text。

### Tertiary

Transparent / text button。

### Destructive

Red。ただし通常操作では極力登場させない。

### Rule

同一領域にPrimary Buttonを複数置かない。

------------------------------------------------------------------------

## 11. Search

検索はMarketplaceの中心機能として大きく扱う。

トップページではHeroの主要UI。

``` text
[ Search icon | Query                         | Type ▼ ][ 検索 ]
```

通常画面ではGlobal Header内のcompact searchに縮小する。

検索フィールド：

-   light surfaceまたはwhite
-   dark text
-   明確なplaceholder
-   Search CTAと一体化して見せる

------------------------------------------------------------------------

## 12. Marketplace Home

トップページは他画面より広告的・視覚的にしてよい。

構成：

``` text
Header

Hero
 ├─ Brand statement
 ├─ Search
 ├─ Popular queries
 └─ Seller CTA

Marketplace metrics

Popular categories

Featured agents / skills

Trust / Monetization / Community
```

### Hero

漫画的表現はHeroに集中する。

使用可能：

-   diagonal panels
-   brush strokes
-   halftone
-   red / gold geometry
-   oversized typography

ただし検索UIの可読性を阻害しない。

------------------------------------------------------------------------

## 13. Chat

チャットは**作業画面**なのでHero的装飾を抑える。

Desktop advanced layout：

``` text
┌──────────────┬──────────────────┬────────────────────┐
│ Agent /      │ Conversation     │ Result / Artifact  │
│ History      │                  │ Preview            │
└──────────────┴──────────────────┴────────────────────┘
```

### Left panel

-   Current agent
-   Agent status
-   Chat history
-   Settings / secondary action

### Center

-   Conversation title
-   Model / token metadata
-   User messages
-   Agent messages
-   Composer

### Right result panel

通常チャットとは異なり、**成果物を独立表示する場所**。

ここでは大胆なGraphic Styleを許容する。

例：

``` text
SPECIAL MOVE
RESULT
Best Answer
```

ただしこれは「特別な成果表示」であり、通常の回答すべてに適用しない。

### Compact chat

画面幅またはモードに応じ、

``` text
History | Conversation | Settings
```

の3column構成も許容する。

------------------------------------------------------------------------

## 14. Message Design

User messageとAgent messageを明確に分離する。

### User

-   compact
-   dark raised surface
-   right / visually separated
-   avatar optional

### Agent

-   larger content area
-   heading hierarchyを保持
-   lists / code / structured contentを読みやすくする

Agent回答は広告カード化しすぎない。

文章そのものの可読性を優先する。

------------------------------------------------------------------------

## 15. Composer

画面下部に固定またはconversation末尾に配置。

``` text
┌──────────────────────────────────────┐
│ メッセージを入力してください…   📎  ➤ │
└──────────────────────────────────────┘
```

Send buttonのみGold emphasis。

Attachment等はsecondary control。

------------------------------------------------------------------------

## 16. My Page / Dashboard

Dashboardは装飾より**情報密度**を優先する。

構成：

``` text
Page Header

Profile Summary

Monthly Summary | Revenue Chart

Published Skills | Recent Reviews

Quick Actions   | Notices
```

### KPI

数値を最大要素にする。

``` text
¥128,600
↑ 24.5%
先月比
```

Goldを数値そのものに多用せず、White primary + Gold/Green accentを使う。

### Charts

-   dark background
-   minimal axes
-   one accent series
-   excessive grid linesを避ける

------------------------------------------------------------------------

## 17. Status System

状態は色だけに依存しない。

``` text
● オンライン
公開中
下書き
審査中
停止
```

Badge / icon / labelを併用する。

Success系はGreen、重要なブランド状態はGold。

------------------------------------------------------------------------

## 18. Iconography

アイコンは原則outline。

-   stroke widthを統一
-   Gold / White
-   小サイズでも認識可能な単純形状
-   decorative iconとfunctional iconを混同しない

カテゴリーアイコンは多少キャラクター性を持たせてよい。

------------------------------------------------------------------------

## 19. Graphic Language

ブランド固有表現：

``` text
Diagonal cuts
Brush strokes
Halftone dots
Speed lines
Red shards
Gold lines
Comic panels
```

### 使用場所

推奨：

-   Hero
-   Campaign
-   Result celebration
-   Promotional card
-   Seller guide

避ける：

-   Form
-   Settings
-   Long text
-   Tables
-   Chat body
-   Analytics

**Graphic intensityは情報密度と反比例させる。**

------------------------------------------------------------------------

## 20. Border / Radius

全体として角丸は控えめ。

``` text
Small control: 4–6px
Card:          6–10px
Input:         6–8px
Pill:          fully rounded only for tags/status
```

柔らかいSaaS UIではなく、シャープで機械的な印象を維持する。

------------------------------------------------------------------------

## 21. Responsive Behavior

Desktopを基準とするが、狭い画面では情報優先順位に従って削る。

``` text
3 column
↓
2 column
↓
1 column
```

優先順位：

``` text
Main Content
Current Context
Primary Action
Navigation
Secondary metadata
Decorative graphics
```

装飾は最初に削除してよい。

------------------------------------------------------------------------

## 22. Accessibility

最低要件：

-   Body textと背景は十分なcontrastを確保。
-   Gold文字を小サイズ本文に使用しない。
-   Statusを色だけで表現しない。
-   Keyboard focusを明示。
-   Interactive elementは最低44px程度のhit areaを目標。
-   Motion / flashing effectsを主要情報伝達に使用しない。

------------------------------------------------------------------------

## 23. Component Inventory

実装時は最低限以下を共通Component化する。

``` text
GlobalHeader
PrimaryNav
SideNav

SearchBar
Button
IconButton
Input
Select
Tag
StatusBadge

Card
MetricCard
SkillCard
AgentCard
ReviewItem

ChatHistory
ChatMessage
ChatComposer
AgentSummary

ResultPanel

ProfileHeader
KPI
ChartCard
NoticeList

SectionHeader
EmptyState
LoadingState
ErrorState
```

------------------------------------------------------------------------

## 24. Design Tokens

最低限以下をToken化する。

``` text
color.*
spacing.*
font.*
font-size.*
font-weight.*
radius.*
border.*
layout.*
z-index.*
motion.*
```

Component内部にbrand colorのhex値を直接散在させない。

------------------------------------------------------------------------

## 25. Implementation Rules for AI Agents

UIを生成・修正するAI Agentは以下を守ること。

1.  既存ComponentとDesign Tokenを先に確認する。
2.  同じ目的のComponentを新規作成しない。
3.  Black / Gold / Redという理由だけで装飾を増やさない。
4.  通常UIでは情報可読性を最優先する。
5.  漫画的Graphic StyleはHero / Promotion /
    Result等の限定領域に使用する。
6.  Primary CTAは1領域1個を原則とする。
7.  Desktopでは情報密度を維持する。
8.  Responsive時は装飾から削る。
9.  スクリーンショットをピクセル単位で模倣するのではなく、本Design
    Systemへ正規化する。
10. 不明なブランド値を推測して固定しない。既存コードにTokenがあればそれを正とする。

------------------------------------------------------------------------

## 26. Page Character

各画面の性格を明確に分ける。

  Page              Character                      Graphic intensity   Information density
  ----------------- ---------------------------- ------------------- ---------------------
  Marketplace Top   Discovery / Promotion                       High                Medium
  Chat              Work / Conversation                  Low--Medium                  High
  Result            Achievement / Presentation                  High                Medium
  My Page           Management / Analytics                       Low                  High
  Settings          Utility                                  Minimal                  High

これによりブランド表現を維持しながら、全画面が広告ページ化することを防ぐ。

------------------------------------------------------------------------

## 27. Final Principle

楽市楽問のUIは単なる「黒＋金＋赤」ではない。

デザインの核は、

> **静かな高密度UIの上に、必要な瞬間だけ漫画的なエネルギーを爆発させること。**

通常操作：

``` text
Quiet
Structured
Dense
Precise
```

訴求・成果：

``` text
Bold
Graphic
Red / Gold
Dynamic
```

このコントラストを全画面で維持する。
