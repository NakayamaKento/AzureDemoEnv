'use strict';
/**
 * TeamsBot — Teams からのメッセージを受信し SRE Agent API に転送する
 *
 * フロー:
 *  1. Teams メッセージ受信
 *  2. conversation → SRE Agent スレッド ID のマッピングを取得/作成
 *  3. SRE Agent にメッセージ送信
 *  4. 即時「調査中...」返信（Bot Framework 15 秒タイムアウト対策）
 *  5. SRE Agent の応答をポーリング
 *  6. 応答をプロアクティブメッセージで Teams に送信
 */

const { ActivityHandler, TurnContext, MessageFactory } = require('botbuilder');
const { SreAgentClient } = require('./sreAgentClient');
const { ThreadStore } = require('./threadStore');

class TeamsBot extends ActivityHandler {
  /**
   * @param {import('botbuilder').CloudAdapter} adapter
   */
  constructor(adapter) {
    super();
    this.adapter    = adapter;
    this.sreClient  = new SreAgentClient();
    this.threadStore = new ThreadStore();

    // ── メッセージ受信ハンドラー ─────────────────────────────────────────
    this.onMessage(async (turnContext, next) => {
      const userText       = (turnContext.activity.text ?? '').trim();
      const conversationId = turnContext.activity.conversation.id;

      if (!userText) {
        await next();
        return;
      }

      // SRE Agent が使用可能かチェック
      if (!process.env.SRE_AGENT_ENDPOINT) {
        await turnContext.sendActivity(
          MessageFactory.text(
            '⚠️ SRE Agent エンドポイントが未設定です。deploy.ps1 の完了後に再試行してください。'
          )
        );
        await next();
        return;
      }

      // (a) スレッド ID を取得または作成
      let threadId;
      try {
        threadId = await this.threadStore.getOrCreateThread(conversationId);
      } catch (err) {
        console.error('[threadStore]', err);
        await turnContext.sendActivity(
          MessageFactory.text('⚠️ スレッドストアへのアクセスに失敗しました。しばらく後に再試行してください。')
        );
        await next();
        return;
      }

      // (b) 会話リファレンスを保存（プロアクティブ返信用）
      const conversationRef = TurnContext.getConversationReference(turnContext.activity);

      // (c) 即時「調査中」返信（15 秒タイムアウト対策）
      await turnContext.sendActivity(
        MessageFactory.text('🔍 SRE Agent が調査中です。しばらくお待ちください...')
      );

      // (d) SRE Agent へ非同期送信 → ポーリング → プロアクティブ返信
      this._processWithSreAgent(threadId, userText, conversationRef, conversationId).catch((err) => {
        console.error('[_processWithSreAgent]', err);
      });

      await next();
    });

    // ── メンバー追加時の挨拶 ─────────────────────────────────────────────
    this.onMembersAdded(async (turnContext, next) => {
      for (const member of turnContext.activity.membersAdded ?? []) {
        if (member.id !== turnContext.activity.recipient.id) {
          await turnContext.sendActivity(
            MessageFactory.text(
              '👋 こんにちは！Azure SRE Agent Teams Bot です。\n\n' +
              '英語でご質問をどうぞ。例:\n' +
              '> What Azure resources are in my subscription?'
            )
          );
        }
      }
      await next();
    });
  }

  /**
   * SRE Agent にメッセージを送り、応答をプロアクティブに Teams へ返す
   * @param {string} threadId
   * @param {string} userText
   * @param {import('botbuilder').ConversationReference} conversationRef
   * @param {string} conversationId
   */
  async _processWithSreAgent(threadId, userText, conversationRef, conversationId) {
    let agentResponse;
    let currentThreadId = threadId;
    try {
      // SRE Agent へメッセージ送信
      const beforeCount = await this.sreClient.getMessageCount(currentThreadId);
      await this.sreClient.sendMessage(currentThreadId, userText);

      // 応答ポーリング（最大 120 秒、3 秒間隔）
      agentResponse = await this.sreClient.pollForResponse(currentThreadId, beforeCount, 120_000);
    } catch (err) {
      // 404 = SRE Agent 側にスレッドが存在しない → スレッドを新規作成してリトライ
      if (err.message.includes('404') && conversationId) {
        console.log(`[sreAgent] Thread ${currentThreadId} not found. Creating new thread...`);
        try {
          // POST /api/v1/threads に StartMessage を含めてスレッド作成＋初回送信を同時実行
          currentThreadId = await this.sreClient.createThread(userText);
          await this.threadStore.saveThread(conversationId, currentThreadId);
          // createThread でメッセージ送信済み → beforeCount=1 でポーリング開始
          agentResponse = await this.sreClient.pollForResponse(currentThreadId, 1, 120_000);
        } catch (retryErr) {
          console.error('[sreAgent] retry failed:', retryErr);
          agentResponse = `⚠️ SRE Agent からの応答取得に失敗しました: ${retryErr.message}`;
        }
      } else {
        console.error('[sreAgent]', err);
        agentResponse = `⚠️ SRE Agent からの応答取得に失敗しました: ${err.message}`;
      }
    }

    // プロアクティブメッセージで Teams に返信
    try {
      await this.adapter.continueConversationAsync(
        process.env.MICROSOFT_APP_ID,
        conversationRef,
        async (proactiveCtx) => {
          await proactiveCtx.sendActivity(MessageFactory.text(agentResponse));
        }
      );
    } catch (err) {
      console.error('[proactive]', err);
    }
  }
}

module.exports = { TeamsBot };
