'use strict';
/**
 * SreAgentClient — Azure SRE Agent データプレーン API クライアント
 *
 * 認証: Managed Identity（UAMI）→ https://azuresre.dev/.default トークン
 * エンドポイント: 環境変数 SRE_AGENT_ENDPOINT から取得
 *
 * 主要 API:
 *   POST {endpoint}/api/v1/threads/{threadId}/messages  — メッセージ送信
 *   GET  {endpoint}/api/v1/threads/{threadId}/messages  — メッセージ一覧取得
 */

const { ManagedIdentityCredential } = require('@azure/identity');

const SRE_AUDIENCE = 'https://azuresre.dev/.default';
const POLL_INTERVAL_MS = 3_000;

class SreAgentClient {
  constructor() {
    // UAMI の clientId を明示指定（複数 UAMI がある場合の曖昧性を排除）
    this.credential = new ManagedIdentityCredential(process.env.AZURE_CLIENT_ID);
  }

  /** Bearer トークン取得 */
  async _getToken() {
    const tokenResponse = await this.credential.getToken(SRE_AUDIENCE);
    return tokenResponse.token;
  }

  /** 共通 fetch ラッパー */
  async _fetch(path, options = {}) {
    const endpoint = process.env.SRE_AGENT_ENDPOINT;
    if (!endpoint) throw new Error('SRE_AGENT_ENDPOINT が設定されていません');

    const token = await this._getToken();
    const url   = `${endpoint.replace(/\/$/, '')}${path}`;

    const res = await fetch(url, {
      ...options,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...(options.headers ?? {})
      }
    });

    if (!res.ok) {
      const errBody = await res.text().catch(() => '');
      throw new Error(`SRE Agent API ${res.status}: ${errBody}`);
    }

    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }

  /**
   * SRE Agent 側にスレッドを新規作成し、生成されたスレッド ID を返す
   * @returns {Promise<string>} threadId
   */
  async createThread(startMessage) {
    const data = await this._fetch('/api/v1/threads', {
      method: 'POST',
      body: JSON.stringify({
        StartMessage: {
          Text: startMessage
        }
      })
    });
    // レスポンス形式例: { id: '...', threadId: '...', thread_id: '...' } を想定
    const threadId = data?.id ?? data?.threadId ?? data?.thread_id;
    if (!threadId) {
      console.warn('[sreAgent] createThread response:', JSON.stringify(data));
      throw new Error('createThread: スレッド ID をレスポンスから取得できませんでした');
    }
    console.log(`[sreAgent] createThread: ${threadId}`);
    return threadId;
  }

  /**
   * スレッドにメッセージを送信する
   * @param {string} threadId
   * @param {string} message
   */
  async sendMessage(threadId, message) {
    return this._fetch(`/api/v1/threads/${threadId}/messages`, {
      method: 'POST',
      body: JSON.stringify({ text: message })
    });
  }

  /**
   * スレッドのメッセージ一覧を取得する
   * @param {string} threadId
   * @returns {{ messages: Array<{role:string, content:string, id:string}> }}
   */
  async getMessages(threadId) {
    const data = await this._fetch(`/api/v1/threads/${threadId}/messages`);
    // レスポンス形式: { messages: [...] } または { value: [...] } を想定
    const messages = data?.messages ?? data?.value ?? [];
    return { messages };
  }

  /**
   * 現在のメッセージ数を返す（ポーリング基準点）
   * @param {string} threadId
   */
  async getMessageCount(threadId) {
    try {
      const { messages } = await this.getMessages(threadId);
      return messages.length;
    } catch {
      return 0; // スレッドが存在しない（初回）は 0
    }
  }

  /**
   * SRE Agent の応答をポーリングで待つ
   * @param {string} threadId
   * @param {number} beforeCount  送信前のメッセージ数
   * @param {number} maxWaitMs    タイムアウト（ミリ秒）
   * @returns {Promise<string>}   エージェント応答テキスト
   */
  async pollForResponse(threadId, beforeCount, maxWaitMs = 120_000) {
    const deadline = Date.now() + maxWaitMs;

    while (Date.now() < deadline) {
      await new Promise(r => setTimeout(r, POLL_INTERVAL_MS));

      const { messages } = await this.getMessages(threadId);

      // beforeCount より後に追加されたエージェント応答メッセージを探す
      const newAgentMsgs = messages
        .slice(beforeCount)
        .filter((m) => {
          const role = String(m.role ?? m.author?.role ?? '').toLowerCase();
          return role === 'assistant' || role === 'sreagent' || role === 'agent';
        });

      if (newAgentMsgs.length > 0) {
        // 最後のエージェントメッセージを返す（text優先、互換でcontentも考慮）
        const last = newAgentMsgs[newAgentMsgs.length - 1];
        if (typeof last.text === 'string' && last.text.trim()) {
          return last.text;
        }
        if (typeof last.content === 'string' && last.content.trim()) {
          return last.content;
        }
        return JSON.stringify(last.content ?? last.text ?? last);
      }
    }

    return (
      '⏰ SRE Agent からの応答がタイムアウトしました（120 秒）。\n\n' +
      `調査は継続中の可能性があります。SRE Agent ポータルで確認してください:\n` +
      `https://sre.azure.com`
    );
  }
}

module.exports = { SreAgentClient };
