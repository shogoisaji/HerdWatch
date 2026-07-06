# HerdWatch

herdr上で並走するAIコーディングエージェントの状態を、ピクセルアートの家畜キャラクターとして専用ウィンドウに常時可視化するmacOSアプリ。「どのpaneが完了したか・どれを見るべきか」を一瞥で判断し、タップで該当paneへ即ジャンプするために存在する。

## Language

**エージェント (Agent)**:
herdrのpane内で動くAIコーディングプロセス1つ（例: 1つのClaude Codeセッション）。同一性はセッション（`agent_session`、なければ `pane_id|検出ラベル`）で判定する。同じpaneでプロセスを起動し直したら別のエージェント。
_Avoid_: pane（paneはエージェントの「居場所」であり本体ではない）

**キャラクター (Character)**:
エージェント1体に1:1で割り当てられる家畜ピクセルアートの個体（種×カラーパレット）。初見時にランダム割当・永続化され、rerollで振り直せる。
_Avoid_: スプライト（スプライトは描画素材、キャラクターは割当済みの個体）

**放牧場 (Pasture)**:
全workspaceの全エージェントのキャラクターが暮らす単一ウィンドウ。workspaceによる固定の柵・仕切りは持たないが、再配置（scatter）時はworkspace単位の帯にまとめて配置し、同じworkspaceのキャラがまとまって見えるようにする。

**状態 (State)**:
herdrが報告するエージェントのライフサイクル: `idle` / `working` / `blocked` / `done` / `unknown`。HerdWatchは独自解釈を加えず鏡写しにする。
_Avoid_: ステータス表記の混在（コード上は `AgentState`）

**確認済み**:
herdr側でdoneのpaneを閲覧し、herdrがdoneを解除した状態。HerdWatch独自の「未読」概念は存在しない（→ ADR-0001）。
_Avoid_: 既読、アプリ内未読
