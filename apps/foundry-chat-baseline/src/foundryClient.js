const { DefaultAzureCredential, getBearerTokenProvider } = require('@azure/identity');

// Foundry エージェント呼び出し: prompt タイプのエージェントは Azure OpenAI Chat Completions API を使用
const AGENT_INSTRUCTIONS = process.env.FOUNDRY_AGENT_INSTRUCTIONS ||
  'You are a helpful AI assistant. Answer questions concisely and helpfully.';
const MODEL_DEPLOYMENT = process.env.FOUNDRY_MODEL_DEPLOYMENT || 'gpt-4.1-mini';
const OPENAI_API_VERSION = '2024-10-21';

// 会話履歴を保持するメモリストア（簡易版）
const conversationHistory = new Map();

async function invokeAgent(message, conversationId) {
  const projectEndpoint = (process.env.FOUNDRY_PROJECT_ENDPOINT || '').replace(/\/$/, '');

  if (!projectEndpoint || !projectEndpoint.includes('ai.azure.com')) {
    console.warn('Foundry endpoint not configured. Returning demo response.');
    return {
      answer: 'デモモード: FOUNDRY_PROJECT_ENDPOINT が未設定です。',
      conversationId: conversationId || 'demo-' + Date.now()
    };
  }

  const accountHost = projectEndpoint.replace('https://', '').split('.services.ai.azure.com')[0];
  const openAiEndpoint = 'https://' + accountHost + '.openai.azure.com';
  const chatUrl = openAiEndpoint + '/openai/deployments/' + MODEL_DEPLOYMENT + '/chat/completions?api-version=' + OPENAI_API_VERSION;

  console.log('Calling Azure OpenAI: ' + chatUrl);

  const credential = new DefaultAzureCredential();
  const tokenProvider = getBearerTokenProvider(credential, 'https://cognitiveservices.azure.com/.default');
  const token = await tokenProvider();

  const sessionId = conversationId || 'new-' + Date.now();
  if (!conversationHistory.has(sessionId)) {
    conversationHistory.set(sessionId, []);
  }
  const history = conversationHistory.get(sessionId);

  const messages = [
    { role: 'system', content: AGENT_INSTRUCTIONS },
    ...history,
    { role: 'user', content: message }
  ];

  const response = await fetch(chatUrl, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ messages, max_tokens: 1000, temperature: 0.7 })
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error('Foundry API error (' + response.status + '): ' + text);
  }

  const data = await response.json();
  const answer = (data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content)
    ? data.choices[0].message.content.trim()
    : '応答を取得できませんでした。';

  history.push({ role: 'user', content: message });
  history.push({ role: 'assistant', content: answer });
  if (history.length > 20) { history.splice(0, 2); }

  return { answer, conversationId: sessionId };
}

module.exports = { invokeAgent };
