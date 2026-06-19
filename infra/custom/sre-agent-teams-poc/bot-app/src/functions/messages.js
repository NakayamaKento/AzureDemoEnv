'use strict';
/**
 * Azure Functions v4 HTTP トリガー — Bot Framework メッセージエンドポイント
 * POST /api/messages
 *
 * Bot Service → Teams → ここに届く → SRE Agent API → Teams にプロアクティブ返信
 */

const { app } = require('@azure/functions');
const {
  CloudAdapter,
  ConfigurationBotFrameworkAuthentication,
  TurnContext,
  MessageFactory
} = require('botbuilder');
const { TeamsBot } = require('../bot');

// ── Bot Framework 認証設定（UAMI ベース — クライアントシークレット不要）──
const botAuth = new ConfigurationBotFrameworkAuthentication({
  MicrosoftAppId:       process.env.MICROSOFT_APP_ID,
  MicrosoftAppType:     process.env.MICROSOFT_APP_TYPE,     // 'UserAssignedMSI'
  MicrosoftAppTenantId: process.env.MICROSOFT_APP_TENANT_ID
});

const adapter = new CloudAdapter(botAuth);

// ── エラーハンドラー ──────────────────────────────────────────────────────
adapter.onTurnError = async (turnContext, error) => {
  console.error('[onTurnError]', error.message, error.stack);
  await turnContext.sendActivity(
    MessageFactory.text(`⚠️ エラーが発生しました: ${error.message}`)
  );
};

// ── Bot インスタンス ─────────────────────────────────────────────────────
const bot = new TeamsBot(adapter);

// ── HTTP トリガー登録 ────────────────────────────────────────────────────
app.http('messages', {
  methods: ['POST'],
  authLevel: 'anonymous',
  // Functions host adds the /api prefix automatically.
  route: 'messages',
  handler: async (request) => {
    try {
      const bodyText = await request.text();
      const activity = JSON.parse(bodyText);
      const authHeader = request.headers.get('authorization') ?? '';

      let statusCode = 200;
      let responseBody = '';
      const responseHeaders = {};

      const fakeReq = {
        method: 'POST',
        headers: {
          authorization: authHeader
        },
        body: activity,
        get(name) {
          const key = String(name || '').toLowerCase();
          return this.headers[key];
        },
        header(name) {
          return this.get(name);
        }
      };

      const fakeRes = {
        socket: {},
        status(code) {
          statusCode = code;
          return this;
        },
        set(name, value) {
          if (name) {
            responseHeaders[String(name).toLowerCase()] = String(value ?? '');
          }
          return this;
        },
        header(name, value) {
          if (typeof name === 'string') {
            return this.set(name, value);
          }
          return this;
        },
        setHeader(name, value) {
          return this.set(name, value);
        },
        getHeader(name) {
          return responseHeaders[String(name || '').toLowerCase()];
        },
        writeHead(code, headers) {
          statusCode = code;
          if (headers && typeof headers === 'object') {
            for (const [k, v] of Object.entries(headers)) {
              this.set(k, v);
            }
          }
          return this;
        },
        write(chunk) {
          if (typeof chunk !== 'undefined' && chunk !== null) {
            responseBody += String(chunk);
          }
          return this;
        },
        send(body) {
          if (typeof body !== 'undefined' && body !== null) {
            responseBody = typeof body === 'string' ? body : JSON.stringify(body);
          }
          return this;
        },
        json(body) {
          this.set('content-type', 'application/json');
          return this.send(body);
        },
        end() {
          return this;
        }
      };

      await adapter.process(fakeReq, fakeRes, async (turnContext) => {
        await bot.run(turnContext);
      });

      return {
        status: statusCode,
        body: responseBody
      };
    } catch (err) {
      console.error('[messages handler]', err?.stack || err);
      return { status: 500, body: err?.message || 'Unknown error' };
    }
  }
});
