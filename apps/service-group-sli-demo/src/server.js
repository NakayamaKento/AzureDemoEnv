const path = require('path');
const crypto = require('crypto');
const express = require('express');
const { AppConfigurationClient } = require('@azure/app-configuration');
const { CosmosClient } = require('@azure/cosmos');
const { DefaultAzureCredential } = require('@azure/identity');
const { ServiceBusClient } = require('@azure/service-bus');

const allowedFaultModes = new Set(['none', 'api', 'queue', 'worker', 'cosmos', 'storage', 'latency']);
const tenantId = process.env.DEMO_TENANT_ID || 'contoso-retail';
let inMemoryFaultMode = process.env.FAULT_MODE || 'none';
let serviceBusClient;
let cosmosClient;
let appConfigClient;
let appInsightsClient;

function asyncHandler(handler) {
  return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
}

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
    return normalizeFaultMode(inMemoryFaultMode);
  }

  try {
    const setting = await client.getConfigurationSetting({ key: 'fault:mode' });
    return normalizeFaultMode(setting.value);
  } catch (error) {
    return normalizeFaultMode(inMemoryFaultMode);
  }
}

async function setFaultMode(mode) {
  const normalizedMode = normalizeFaultMode(mode);
  inMemoryFaultMode = normalizedMode;

  const client = getAppConfigurationClient();
  if (client) {
    await client.setConfigurationSetting({ key: 'fault:mode', value: normalizedMode });
  }

  return normalizedMode;
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
      .setAutoCollectRequests(true)
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

function getServiceBusClient() {
  const namespace = process.env.SERVICE_BUS_NAMESPACE || process.env.ServiceBusConnection__fullyQualifiedNamespace;
  if (!namespace) {
    return null;
  }

  if (!serviceBusClient) {
    serviceBusClient = new ServiceBusClient(namespace, getCredential());
  }

  return serviceBusClient;
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

async function applyLatencyIfNeeded(mode) {
  if (mode !== 'latency') {
    return;
  }

  const delayMs = Number(process.env.FAULT_LATENCY_MS || 1500);
  await new Promise((resolve) => setTimeout(resolve, delayMs));
}

function createOrderPayload(body = {}) {
  const itemCount = Array.isArray(body.items) && body.items.length > 0 ? body.items.length : 1;
  const items = Array.from({ length: itemCount }).map((_, index) => ({
    sku: body.items?.[index]?.sku || `SKU-${index + 1}`,
    quantity: Number(body.items?.[index]?.quantity || 1)
  }));

  return {
    id: crypto.randomUUID(),
    tenantId,
    customerId: body.customerId || `customer-${Math.floor(Math.random() * 1000)}`,
    items,
    totalAmount: Number(body.totalAmount || (items.length * 29.95).toFixed(2)),
    status: 'submitted',
    submittedAt: new Date().toISOString()
  };
}

async function submitOrder(order, mode) {
  if (mode === 'queue') {
    const error = new Error('Queue fault mode is enabled');
    error.statusCode = 503;
    throw error;
  }

  const client = getServiceBusClient();
  const queueName = process.env.SERVICE_BUS_QUEUE_NAME || process.env.ServiceBusQueueName || 'orders';
  if (!client) {
    return { queued: false, reason: 'SERVICE_BUS_NAMESPACE is not configured' };
  }

  const sender = client.createSender(queueName);
  try {
    await sender.sendMessages({
      messageId: order.id,
      contentType: 'application/json',
      subject: 'order-submitted',
      body: order,
      applicationProperties: {
        tenantId: order.tenantId,
        faultMode: mode
      }
    });
    return { queued: true, queueName };
  } finally {
    await sender.close();
  }
}

async function readOrder(orderId) {
  const container = getCosmosContainer();
  if (!container) {
    return null;
  }

  const response = await container.item(orderId, tenantId).read();
  return response.resource || null;
}

function createApp() {
  const app = express();

  app.use(express.json({ limit: '1mb' }));
  app.use(express.static(path.join(__dirname, '..', 'public')));

  app.get('/healthz', asyncHandler(async (_req, res) => {
    const mode = await getFaultMode();
    res.status(200).json({
      status: mode === 'api' ? 'degraded' : 'ok',
      faultMode: mode,
      tenantId,
      timestamp: new Date().toISOString()
    });
  }));

  app.get('/api/faults', asyncHandler(async (_req, res) => {
    const mode = await getFaultMode();
    res.status(200).json({ mode, allowedModes: Array.from(allowedFaultModes) });
  }));

  app.post('/api/faults', asyncHandler(async (req, res) => {
    const requestedMode = String(req.body?.mode || '').trim().toLowerCase();
    if (!allowedFaultModes.has(requestedMode)) {
      return res.status(400).json({
        error: 'invalid fault mode',
        allowedModes: Array.from(allowedFaultModes)
      });
    }

    const mode = await setFaultMode(requestedMode);
    trackEvent('FaultModeChanged', { mode });
    return res.status(200).json({ mode });
  }));

  app.post('/api/orders', asyncHandler(async (req, res) => {
    const started = Date.now();
    const mode = await getFaultMode();

    try {
      if (mode === 'api') {
        const error = new Error('API fault mode is enabled');
        error.statusCode = 503;
        throw error;
      }

      await applyLatencyIfNeeded(mode);
      const order = createOrderPayload(req.body);
      const queueResult = await submitOrder(order, mode);
      const latencyMs = Date.now() - started;

      trackMetric('orders_submitted', 1, { faultMode: mode, queued: String(queueResult.queued) });
      trackMetric('order_submit_latency_ms', latencyMs, { faultMode: mode });
      trackEvent('OrderSubmitted', { orderId: order.id, faultMode: mode, queued: String(queueResult.queued) });

      res.status(202).json({ order, queue: queueResult, latencyMs, faultMode: mode });
    } catch (error) {
      const latencyMs = Date.now() - started;
      trackMetric('order_submit_failures', 1, { faultMode: mode });
      trackEvent('OrderSubmitFailed', { faultMode: mode, message: error.message }, { latencyMs });
      res.status(error.statusCode || 500).json({ error: error.message, faultMode: mode, latencyMs });
    }
  }));

  app.get('/api/orders/:id', asyncHandler(async (req, res) => {
    try {
      const order = await readOrder(req.params.id);
      if (!order) {
        return res.status(404).json({ error: 'order not found or Cosmos DB is not configured' });
      }
      return res.status(200).json({ order });
    } catch (error) {
      return res.status(500).json({ error: error.message });
    }
  }));

  app.post('/api/demo/run', asyncHandler(async (req, res) => {
    const requestedCount = Number(req.body?.count ?? 5);
    if (!Number.isInteger(requestedCount) || requestedCount < 1 || requestedCount > 50) {
      return res.status(400).json({ error: 'count must be an integer between 1 and 50' });
    }

    const initialMode = await getFaultMode();
    if (initialMode === 'api') {
      return res.status(503).json({ error: 'API fault mode is enabled', faultMode: initialMode });
    }

    const count = requestedCount;
    const results = [];

    for (let index = 0; index < count; index += 1) {
      const mode = await getFaultMode();
      const order = createOrderPayload({ customerId: `demo-${index + 1}` });
      try {
        await applyLatencyIfNeeded(mode);
        const queue = await submitOrder(order, mode);
        results.push({ id: order.id, accepted: true, queue });
      } catch (error) {
        results.push({ id: order.id, accepted: false, error: error.message });
      }
    }

    const accepted = results.filter((result) => result.accepted).length;
    trackMetric('demo_orders_requested', count);
    trackMetric('demo_orders_accepted', accepted);
    return res.status(200).json({ requested: count, accepted, results });
  }));

  app.use((error, _req, res, _next) => {
    const statusCode = Number.isInteger(error.statusCode) ? error.statusCode : 500;
    trackEvent('UnhandledApiError', { message: error.message, statusCode: String(statusCode) });
    res.status(statusCode).json({
      error: statusCode >= 500 ? 'internal server error' : error.message
    });
  });

  return app;
}

if (require.main === module) {
  const port = Number(process.env.PORT || process.env.WEBSITES_PORT || 3000);
  createApp().listen(port, () => {
    console.log(`service-group-sli-demo listening on ${port}`);
  });
}

module.exports = {
  allowedFaultModes,
  createApp,
  createOrderPayload,
  normalizeFaultMode
};
