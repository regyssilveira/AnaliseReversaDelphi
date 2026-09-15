// SPDX-License-Identifier: Apache-2.0

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const file = process.argv[2] || 'bin/workflow-test/graph.html';
const html = fs.readFileSync(file, 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert.ok(script, 'generated HTML must contain the navigation script');

const start = script.indexOf('function inProject');
const end = script.indexOf('function traceNodes');
assert.ok(start >= 0 && end > start, 'generated HTML must contain trace functions');
const functions = script.slice(start, end);

function check(edges, selected, projectRoot, program) {
  const out = new Map();
  for (const [from, to] of edges) {
    if (!out.has(from)) out.set(from, []);
    out.get(from).push({ from, to });
  }
  return vm.runInNewContext(functions + '\ntrace(selected)', {
    out, selected, projectRoot, program,
  });
}

const dpr = check([
  ['Lib.pas', 'C:/project/A.pas'],
  ['C:/project/A.pas', 'C:/project/App.dpr'],
], 'Lib.pas', 'C:/project/', 'C:/project/App.dpr');
assert.equal(dpr.kind, 'DPR');
assert.equal(dpr.edges.length, 2);

const local = check([
  ['Lib.pas', 'C:/project/A.pas'],
], 'Lib.pas', 'C:/project/', 'C:/project/App.dpr');
assert.equal(local.kind, 'PROJECT');
assert.equal(local.edges.length, 1);

const missing = check([
  ['Lib.pas', 'Other.pas'],
], 'Lib.pas', 'C:/project/', 'C:/project/App.dpr');
assert.equal(missing, null);

console.log('Visual trace tests passed');
