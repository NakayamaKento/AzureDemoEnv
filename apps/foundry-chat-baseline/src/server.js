const path = require('path');
const express = require('express');
const { invokeAgent } = require('./foundryClient');

const app = express();
const port = Number(process.env.PORT || process.env.WEBSITES_PORT || 3000);

app.use(express.json({ limit: '1mb' }));
app.use(express.static(path.join(__dirname, '..', 'public')));

app.get('/healthz', (_req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.post('/api/chat', async (req, res) => {
  try {
    const message = (req.body?.message || '').trim();
    const conversationId = req.body?.conversationId || null;

    if (!message) {
      return res.status(400).json({ error: 'message is required' });
    }

    const result = await invokeAgent(message, conversationId);
    return res.status(200).json(result);
  } catch (error) {
    return res.status(500).json({
      error: error.message || 'unknown error'
    });
  }
});

app.listen(port, () => {
  console.log(`foundry-chat-baseline listening on ${port}`);
});