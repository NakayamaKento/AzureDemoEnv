const latencyBucketsMs = [100, 250, 500, 750, 1000, 1500, 3000, Number.POSITIVE_INFINITY];
const successCounters = new Map();
const failureCounters = new Map();
const latencyHistograms = new Map();

function escapeLabelValue(value) {
  return String(value).replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll('"', '\\"');
}

function labelSet(labels) {
  const entries = Object.entries(labels).sort(([left], [right]) => left.localeCompare(right));
  return `{${entries.map(([name, value]) => `${name}="${escapeLabelValue(value)}"`).join(',')}}`;
}

function increment(map, labels) {
  const key = labelSet(labels);
  map.set(key, (map.get(key) || 0) + 1);
}

function observeLatency(latencyMs, labels) {
  const key = labelSet(labels);
  const histogram = latencyHistograms.get(key) || {
    labels,
    count: 0,
    sum: 0,
    buckets: latencyBucketsMs.map(() => 0)
  };

  histogram.count += 1;
  histogram.sum += latencyMs;
  latencyBucketsMs.forEach((upperBound, index) => {
    if (latencyMs <= upperBound) {
      histogram.buckets[index] += 1;
    }
  });
  latencyHistograms.set(key, histogram);
}

function recordOrderSuccess(latencyMs, faultMode, queued) {
  increment(successCounters, { fault_mode: faultMode, operation: 'submit_order', queued: String(queued) });
  observeLatency(latencyMs, { fault_mode: faultMode });
}

function recordOrderFailure(latencyMs, faultMode) {
  increment(failureCounters, { fault_mode: faultMode, operation: 'submit_order' });
  observeLatency(latencyMs, { fault_mode: faultMode });
}

function renderCounter(lines, name, help, counters) {
  lines.push(`# HELP ${name} ${help}`, `# TYPE ${name} counter`);
  for (const [labels, value] of counters) {
    lines.push(`${name}${labels} ${value}`);
  }
}

function renderMetrics() {
  const lines = [];
  renderCounter(lines, 'orders_submitted_total', 'Successfully submitted orders.', successCounters);
  renderCounter(lines, 'order_submit_failures_total', 'Failed order submission attempts.', failureCounters);
  lines.push(
    '# HELP order_submit_duration_milliseconds Order submission duration in milliseconds.',
    '# TYPE order_submit_duration_milliseconds histogram'
  );

  for (const histogram of latencyHistograms.values()) {
    latencyBucketsMs.forEach((upperBound, index) => {
      const le = Number.isFinite(upperBound) ? String(upperBound) : '+Inf';
      lines.push(`order_submit_duration_milliseconds_bucket${labelSet({ ...histogram.labels, le })} ${histogram.buckets[index]}`);
    });
    lines.push(
      `order_submit_duration_milliseconds_sum${labelSet(histogram.labels)} ${histogram.sum}`,
      `order_submit_duration_milliseconds_count${labelSet(histogram.labels)} ${histogram.count}`
    );
  }

  return `${lines.join('\n')}\n`;
}

module.exports = {
  recordOrderFailure,
  recordOrderSuccess,
  renderMetrics
};