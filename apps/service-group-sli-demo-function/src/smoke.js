const assert = require('assert');

for (const name of [
  'APPLICATIONINSIGHTS_CONNECTION_STRING',
  'APP_CONFIG_ENDPOINT',
  'COSMOS_ENDPOINT',
  'STORAGE_ACCOUNT_NAME'
]) {
  delete process.env[name];
}
process.env.FAULT_MODE = 'none';

const { normalizeFaultMode, processOrderMessage } = require('./functions/processOrder');

async function main() {
  assert.strictEqual(normalizeFaultMode('worker'), 'worker');
  assert.strictEqual(normalizeFaultMode('bad'), 'none');

  const result = await processOrderMessage({
    id: 'smoke-order-001',
    tenantId: 'contoso-retail',
    customerId: 'smoke-test',
    items: [{ sku: 'SKU-1', quantity: 1 }],
    totalAmount: 29.95,
    submittedAt: new Date().toISOString()
  }, console);

  assert.strictEqual(result.processed, true);
  assert.strictEqual(result.cosmos.stored, false);
  assert.strictEqual(result.storage.written, false);
  console.log('Function smoke test passed');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
