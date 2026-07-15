const { app } = require('@azure/functions');
const { AppConfigurationClient } = require('@azure/app-configuration');
const { CosmosClient } = require('@azure/cosmos');
const { DefaultAzureCredential } = require('@azure/identity');
const { BlobServiceClient } = require('@azure/storage-blob');

const allowedFaultModes = new Set(['none', 'api', 'queue', 'worker', 'cosmos', 'storage', 'latency']);
let appConfigClient;
let cosmosClient;
let blobServiceClient;
let appInsightsClient;

function normalizeFaultMode(mode) {
  const value = String(mode || 'none').trim().toLowerCase();
  return allowedFaultModes.has(value) ? value : 'none';
}

function getCredential() {
  return new DefaultAzureCredential();
}

function getAppConfigurationClient() {
  const endpoint = process.env.APP_CONFIG_ENDPOINT;
  if (!endpoint) {
    return null;
  }

  if (!appConfigClient) {
    appConfigClient = new AppConfigurationClient(endpoint, getCredential());
  }

  return appConfigClient;
}

async function getFaultMode() {
  const client = getAppConfigurationClient();
  if (!client) {
    return normalizeFaultMode(process.env.FAULT_MODE || 'none');
  }

  try {
    const setting = await client.getConfigurationSetting({ key: 'fault:mode' });
    return normalizeFaultMode(setting.value);
  } catch (error) {
    return normalizeFaultMode(process.env.FAULT_MODE || 'none');
  }
}

function getTelemetryClient() {
  if (appInsightsClient !== undefined) {
    return appInsightsClient;
  }

  const connectionString = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;
  if (!connectionString) {
    appInsightsClient = null;
    return null;
  }

  try {
    const appInsights = require('applicationinsights');
    appInsights
      .setup(connectionString)
      .setAutoCollectDependencies(true)
      .setAutoCollectExceptions(true)
      .setAutoCollectConsole(true, true)
      .start();
    appInsightsClient = appInsights.defaultClient;
  } catch (error) {
    appInsightsClient = null;
  }

  return appInsightsClient;
}

function trackEvent(name, properties = {}, measurements = {}) {
  const client = getTelemetryClient();
  if (client) {
    client.trackEvent({ name, properties, measurements });
  }
}

function trackMetric(name, value, properties = {}) {
  const client = getTelemetryClient();
  if (client) {
    client.trackMetric({ name, value, properties });
  }
}

function parseOrder(message) {
  if (typeof message === 'string') {
    return JSON.parse(message);
  }

  return message;
}

async function applyLatencyIfNeeded(mode) {
  if (mode !== 'latency') {
    return;
  }

  const delayMs = Number(process.env.FAULT_LATENCY_MS || 1500);
  await new Promise((resolve) => setTimeout(resolve, delayMs));
}

function getCosmosContainer() {
  const endpoint = process.env.COSMOS_ENDPOINT;
  const databaseId = process.env.COSMOS_DATABASE || 'orders';
  const containerId = process.env.COSMOS_CONTAINER || 'orders';

  if (!endpoint) {
    return null;
  }

  if (!cosmosClient) {
    cosmosClient = new CosmosClient({ endpoint, aadCredentials: getCredential() });
  }

  return cosmosClient.database(databaseId).container(containerId);
}

async function writeOrder(order) {
  const container = getCosmosContainer();
  if (!container) {
    return { stored: false, reason: 'COSMOS_ENDPOINT is not configured' };
  }

  const document = {
    ...order,
    status: 'processed',
    processedAt: new Date().toISOString(),
    schemaVersion: 1
  };

  await container.items.upsert(document);
  return { stored: true, id: document.id };
}

function getBlobServiceClient() {
  const storageAccountName = process.env.STORAGE_ACCOUNT_NAME;
  if (!storageAccountName) {
    return null;
  }

  if (!blobServiceClient) {
    blobServiceClient = new BlobServiceClient(
      `https://${storageAccountName}.blob.core.windows.net`,
      getCredential()
    );
  }

  return blobServiceClient;
}

async function writeReceipt(order) {
  const client = getBlobServiceClient();
  if (!client) {
    return { written: false, reason: 'STORAGE_ACCOUNT_NAME is not configured' };
  }

  const containerName = process.env.RECEIPTS_CONTAINER || 'receipts';
  const containerClient = client.getContainerClient(containerName);
  const blobClient = containerClient.getBlockBlobClient(`${order.tenantId}/${order.id}.json`);
  const content = JSON.stringify({
    orderId: order.id,
    tenantId: order.tenantId,
    totalAmount: order.totalAmount,
    processedAt: new Date().toISOString()
  }, null, 2);

  await blobClient.upload(content, Buffer.byteLength(content), {
    blobHTTPHeaders: { blobContentType: 'application/json' }
  });

  return { written: true, path: `${containerName}/${order.tenantId}/${order.id}.json` };
}

async function processOrderMessage(message, context = console) {
  const started = Date.now();
  const order = parseOrder(message);
  const mode = await getFaultMode();

  if (!order?.id || !order?.tenantId) {
    throw new Error('Order message must include id and tenantId');
  }

  if (mode === 'worker') {
    throw new Error('Worker fault mode is enabled');
  }

  await applyLatencyIfNeeded(mode);

  if (mode === 'cosmos') {
    throw new Error('Cosmos fault mode is enabled');
  }
  const cosmos = await writeOrder(order);

  if (mode === 'storage') {
    throw new Error('Storage fault mode is enabled');
  }
  const storage = await writeReceipt(order);

  const latencyMs = Date.now() - started;
  trackMetric('orders_processed', 1, { faultMode: mode });
  trackMetric('order_process_latency_ms', latencyMs, { faultMode: mode });
  trackEvent('OrderProcessed', { orderId: order.id, faultMode: mode }, { latencyMs });

  context.log?.(`Processed order ${order.id} in ${latencyMs}ms`);
  return { processed: true, cosmos, storage, latencyMs, faultMode: mode };
}

app.serviceBusQueue('processOrder', {
  connection: 'ServiceBusConnection',
  queueName: process.env.SERVICE_BUS_QUEUE_NAME || process.env.ServiceBusQueueName || 'orders',
  handler: processOrderMessage
});

module.exports = {
  normalizeFaultMode,
  processOrderMessage
};
