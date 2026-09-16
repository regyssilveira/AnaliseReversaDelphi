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
    isProjectOrigin: path => path.toLowerCase().startsWith(projectRoot.toLowerCase()),
    originOf: () => 'unknown',
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
assert.equal(missing.kind, 'NO_CONSUMER');
assert.equal(missing.endpoint, 'Other.pas');

const sibling = check([
  ['Lib.pas', 'C:/project-old/Sibling.pas'],
], 'Lib.pas', 'C:/project/', 'C:/project/App.dpr');
assert.equal(sibling.kind, 'NO_CONSUMER',
  'a similarly named sibling directory is outside the project');

const cutStart = script.indexOf('function directCuts');
const cutEnd = script.indexOf('function showCuts');
assert.ok(cutStart >= 0 && cutEnd > cutStart, 'generated HTML must expose direct cut declarations');
const cuts = vm.runInNewContext(script.slice(cutStart, cutEnd) + '\n directCuts("Target")', {
  out: new Map([
    ['Target', [
      { from: 'Target', to: 'A', source: 'A.pas', line: 3 },
      { from: 'Target', to: 'B', source: 'B.pas', line: 4 },
      { from: 'Target', to: 'Orphan', source: 'Orphan.pas', line: 5 },
    ]],
  ]),
  toDpr: new Set(['Target', 'A', 'B', 'App.dpr']),
});
assert.deepEqual(Array.from(cuts, x => x.source), ['A.pas', 'B.pas']);

const routeStart = script.indexOf('const dprEdges=');
const routeEnd = script.indexOf(';', routeStart);
assert.ok(routeStart >= 0 && routeEnd > routeStart, 'generated HTML must retain all DPR routes');
const routeEdges = [
  { from: 'Target', to: 'A' }, { from: 'Target', to: 'B' },
  { from: 'A', to: 'App.dpr' }, { from: 'B', to: 'App.dpr' },
  { from: 'Target', to: 'Orphan' },
];
const dprEdges = vm.runInNewContext(script.slice(routeStart, routeEnd + 1) + '\n dprEdges', {
  edges: routeEdges,
  toDpr: new Set(['Target', 'A', 'B', 'App.dpr']),
});
assert.equal(dprEdges.size, 4);
assert.ok(!dprEdges.has(routeEdges[4]));

const modeStart = script.indexOf('let selected=null');
const modeEnd = script.indexOf(';', modeStart);
assert.ok(modeStart >= 0 && modeEnd > modeStart, 'generated HTML must select an initial navigation mode');
function initialMode(count) {
  return vm.runInNewContext(script.slice(modeStart, modeEnd + 1) + '\nmode', {
    nodes: new Map(Array.from({ length: count }, (_, i) => [String(i), {}])),
    target: 'Target',
    Map, Set,
  });
}
assert.equal(initialMode(4), 'explore');
assert.equal(initialMode(302), 'explore');

const exploreBranch = script.split('\n').find(x => x.includes('else if(mode==="explore")'));
assert.ok(exploreBranch, 'generated HTML must expand visible consumers on demand');
function explore(expanded, highlighted = []) {
  return vm.runInNewContext(`let visible; if(mode==="all"){} ${exploreBranch}\nvisible`, {
    mode: 'explore', expanded: new Set(expanded),
    highlighted: new Set(highlighted),
    out: new Map([
      ['Target', [{ from: 'Target', to: 'A' }, { from: 'Target', to: 'B' }]],
      ['A', [{ from: 'A', to: 'App.dpr' }]],
    ]),
    Set,
  });
}
assert.deepEqual([...explore(['Target'])].sort(), ['A', 'B', 'Target']);
assert.deepEqual([...explore(['Target', 'A'])].sort(), ['A', 'App.dpr', 'B', 'Target']);
assert.deepEqual([...explore(['Target'], ['Target', 'A', 'App.dpr'])].sort(),
  ['A', 'App.dpr', 'B', 'Target'], 'the selected chain remains visible in explore mode');

const orderStart = script.indexOf('function destinationRank');
const orderEnd = script.indexOf('function render');
assert.ok(orderStart >= 0 && orderEnd > orderStart, 'generated HTML must contain crossing reduction');
const groups = new Map([[0, ['A', 'B']], [1, ['X', 'Y']]]);
vm.runInNewContext(script.slice(orderStart, orderEnd) + '\nreduceCrossings(groups,levels,visible)', {
  groups,
  levels: new Map([['A', 0], ['B', 0], ['X', 1], ['Y', 1]]),
  visible: new Set(['A', 'B', 'X', 'Y']),
  incoming: new Map([['X', [{ from: 'B' }]], ['Y', [{ from: 'A' }]]]),
  out: new Map([['A', [{ to: 'Y' }]], ['B', [{ to: 'X' }]]]),
  nodes: new Map(), program: 'App.dpr', isProjectOrigin: () => false, originOf: () => 'unknown',
});
assert.deepEqual(Array.from(groups.get(1)), ['Y', 'X'],
  'barycentric ordering places nodes near their connected parents');

console.log('Visual trace tests passed');
