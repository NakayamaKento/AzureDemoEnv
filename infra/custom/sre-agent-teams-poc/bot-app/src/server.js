'use strict';

const http = require('http');
const { CloudAdapter, ConfigurationBotFrameworkAuthentication, MessageFactory } = require('botbuilder');
const { TeamsBot } = require('./bot');

const port = Number(process.env.PORT || 8080);

const botAuth = new ConfigurationBotFrameworkAuthentication({
  MicrosoftAppId: process.env.MICROSOFT_APP_ID,
  MicrosoftAppType: process.env.MICROSOFT_APP_TYPE,
  MicrosoftAppTenantId: process.env.MICROSOFT_APP_TENANT_ID
});

const adapter = new CloudAdapter(botAuth);
adapter.onTurnError = async (turnContext, error) => {
  console.error('[onTurnError]', error.message, error.stack);
  await turnContext.sendActivity(MessageFactory.text(`Error: ${error.message}`));
};

const bot = new TeamsBot(adapter);

function toBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

function createResBridge(res) {
  let statusCode = 200;
  const headers = {};

  return {
    socket: {},
    status(code) {
      statusCode = code;
      return this;
    },
    set(name, value) {
      if (name) {
        headers[String(name).toLowerCase()] = String(value ?? '');
      }
      return this;
    },
    header(name, value) {
      return this.set(name, value);
    },
    setHeader(name, value) {
      return this.set(name, value);
    },
    getHeader(name) {
      return headers[String(name || '').toLowerCase()];
    },
    writeHead(code, hdrs) {
      statusCode = code;
      if (hdrs && typeof hdrs === 'object') {
        for (const [k, v] of Object.entries(hdrs)) {
          this.set(k, v);
        }
      }
      return this;
    },
    write(chunk) {
      if (!res.headersSent) {
        for (const [k, v] of Object.entries(headers)) {
          res.setHeader(k, v);
        }
        res.statusCode = statusCode;
      }
      if (typeof chunk !== 'undefined' && chunk !== null) {
        res.write(chunk);
      }
      return this;
    },
    send(body) {
      if (!res.headersSent) {
        for (const [k, v] of Object.entries(headers)) {
          res.setHeader(k, v);
        }
        res.statusCode = statusCode;
      }
      const output = typeof body === 'string' ? body : JSON.stringify(body ?? '');
      res.end(output);
      return this;
    },
    json(body) {
      this.set('content-type', 'application/json');
      return this.send(body);
    },
    end() {
      if (!res.headersSent) {
        for (const [k, v] of Object.entries(headers)) {
          res.setHeader(k, v);
        }
        res.statusCode = statusCode;
      }
      res.end();
      return this;
    }
  };
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && (req.url === '/' || req.url === '/healthz')) {
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ status: 'ok' }));
      return;
    }

    if (req.method !== 'POST' || req.url !== '/api/messages') {
      res.statusCode = 404;
      res.end('Not found');
      return;
    }

    const bodyText = await toBody(req);
    const activity = bodyText ? JSON.parse(bodyText) : {};

    const fakeReq = {
      method: 'POST',
      headers: req.headers,
      body: activity,
      get(name) {
        return req.headers[String(name || '').toLowerCase()];
      },
      header(name) {
        return this.get(name);
      }
    };

    const fakeRes = createResBridge(res);

    await adapter.process(fakeReq, fakeRes, async (turnContext) => {
      await bot.run(turnContext);
    });
  } catch (err) {
    console.error('[server]', err?.stack || err);
    res.statusCode = 500;
    res.end(err?.message || 'Unknown error');
  }
});

server.listen(port, () => {
  console.log(`Teams bot server listening on ${port}`);
});
