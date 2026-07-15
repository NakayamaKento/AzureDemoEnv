const assert = require('assert');

for (const name of [
  'APPLICATIONINSIGHTS_CONNECTION_STRING',
  'APP_CONFIG_ENDPOINT',
  'COSMOS_ENDPOINT',
  'SERVICE_BUS_NAMESPACE',
  'ServiceBusConnection__fullyQualifiedNamespace'
]) {
  delete process.env[name];
}
process.env.FAULT_MODE = 'none';

const { createApp, normalizeFaultMode } = require('./server');

async function request(baseUrl, path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    headers: {
      'connection': 'close',
      'content-type': 'application/json'
    },
    ...options
  });
  const body = await response.json();
  return { response, body };
}

async function main() {
  assert.strictEqual(normalizeFaultMode('api'), 'api');
  assert.strictEqual(normalizeFaultMode('unexpected'), 'none');

  const app = createApp();
  const server = await new Promise((resolve) => {
    const startedServer = app.listen(0, () => resolve(startedServer));
  });

  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    const health = await request(baseUrl, '/healthz');
    assert.strictEqual(health.response.status, 200);
    assert.ok(health.body.status);

    const order = await request(baseUrl, '/api/orders', {
      method: 'POST',
      body: JSON.stringify({ customerId: 'smoke-test' })
    });
    assert.strictEqual(order.response.status, 202);
    assert.ok(order.body.order.id);

    const invalidFault = await request(baseUrl, '/api/faults', {
      method: 'POST',
      body: JSON.stringify({ mode: 'unexpected' })
    });
    assert.strictEqual(invalidFault.response.status, 400);

    const invalidDemo = await request(baseUrl, '/api/demo/run', {
      method: 'POST',
      body: JSON.stringify({ count: 0 })
    });
    assert.strictEqual(invalidDemo.response.status, 400);

    const enableApiFault = await request(baseUrl, '/api/faults', {
      method: 'POST',
      body: JSON.stringify({ mode: 'api' })
    });
    assert.strictEqual(enableApiFault.response.status, 200);

    const degradedDemo = await request(baseUrl, '/api/demo/run', {
      method: 'POST',
      body: JSON.stringify({ count: 2 })
    });
    assert.strictEqual(degradedDemo.response.status, 503);

    const clearFault = await request(baseUrl, '/api/faults', {
      method: 'POST',
      body: JSON.stringify({ mode: 'none' })
    });
    assert.strictEqual(clearFault.response.status, 200);

    const demo = await request(baseUrl, '/api/demo/run', {
      method: 'POST',
      body: JSON.stringify({ count: 2 })
    });
    assert.strictEqual(demo.response.status, 200);
    assert.strictEqual(demo.body.requested, 2);
  } finally {
    await new Promise((resolve) => {
      server.close(resolve);
      server.closeAllConnections?.();
    });
  }

  console.log('API smoke test passed');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
