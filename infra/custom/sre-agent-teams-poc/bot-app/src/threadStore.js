'use strict';
/**
 * ThreadStore — Teams conversationId ↔ SRE Agent threadId のマッピング管理
 *
 * ストレージ: Azure Table Storage（ConversationThreadMap テーブル）
 *   PartitionKey: 'conversations'
 *   RowKey:       conversationId（Teams の conversation.id）
 *   sreThreadId:  SRE Agent スレッド ID（client 生成 UUID）
 */

const { TableClient } = require('@azure/data-tables');
const { ManagedIdentityCredential } = require('@azure/identity');
const { randomUUID } = require('crypto');

const TABLE_NAME       = 'ConversationThreadMap';
const PARTITION_KEY    = 'conversations';

class ThreadStore {
  constructor() {
    const accountName = process.env.STORAGE_ACCOUNT_NAME;
    if (!accountName) throw new Error('STORAGE_ACCOUNT_NAME が設定されていません');

    const endpoint   = `https://${accountName}.table.core.windows.net`;
    const credential = new ManagedIdentityCredential(process.env.AZURE_CLIENT_ID);

    this.client = new TableClient(endpoint, TABLE_NAME, credential);
  }

  /**
   * conversationId に紐づく SRE Agent スレッド ID を返す。
   * 存在しない場合は新規 UUID を生成して保存する。
   * @param {string} conversationId
   * @returns {Promise<string>} threadId
   */
  async getOrCreateThread(conversationId) {
    // スラッシュ等の記号を除去（Table Storage の RowKey 制限対応）
    const safeKey = conversationId.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 200);

    try {
      const entity = await this.client.getEntity(PARTITION_KEY, safeKey);
      // 旧形式の thread-<uuid> が残っている場合は GUID 形式へ移行する
      const normalizedThreadId = this._normalizeThreadId(entity.sreThreadId);
      if (normalizedThreadId !== entity.sreThreadId) {
        await this.client.upsertEntity({
          partitionKey: PARTITION_KEY,
          rowKey: safeKey,
          sreThreadId: normalizedThreadId,
          createdAt: entity.createdAt ?? new Date().toISOString()
        });
      }
      return normalizedThreadId;
    } catch (err) {
      // 404 = 新規会話 → スレッドを作成
      if (err.statusCode === 404 || err.code === 'ResourceNotFound') {
        const threadId = randomUUID();
        await this.client.upsertEntity({
          partitionKey: PARTITION_KEY,
          rowKey: safeKey,
          sreThreadId: threadId,
          createdAt: new Date().toISOString()
        });
        return threadId;
      }
      throw err;
    }
  }

  /**
   * conversationId に紐づくスレッド ID を上書き保存する（SRE Agent 生成 ID で置換する場合に使用）
   * @param {string} conversationId
   * @param {string} threadId
   */
  async saveThread(conversationId, threadId) {
    const safeKey = conversationId.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 200);
    await this.client.upsertEntity({
      partitionKey: PARTITION_KEY,
      rowKey: safeKey,
      sreThreadId: threadId,
      createdAt: new Date().toISOString()
    });
    console.log(`[threadStore] saveThread: ${safeKey} -> ${threadId}`);
  }

  _normalizeThreadId(threadId) {
    const value = String(threadId ?? '').trim();
    if (!value) {
      return randomUUID();
    }

    if (value.startsWith('thread-')) {
      return value.slice('thread-'.length);
    }

    return value;
  }
}

module.exports = { ThreadStore };
