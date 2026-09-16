// SPDX-License-Identifier: Apache-2.0

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync(process.argv[2] || 'bin/workflow-test/graph.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert.ok(script, 'generated HTML must contain a script');

class Element {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.handlers = new Map();
    this.attrs = {};
    this.value = '';
    this.checked = false;
    this.clientWidth = 900;
    this.clientHeight = 600;
  }
  setAttribute(key, value) { this.attrs[key] = String(value); }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(name, handler) { this.handlers.set(name, handler); }
  click() { this.handlers.get('click')?.(); }
}

const elements = new Map();
const document = {
  getElementById(id) {
    if (!elements.has(id)) elements.set(id, new Element(id));
    return elements.get(id);
  },
  createElementNS(_namespace, tag) { return new Element(tag); },
  createElement(tag) { return new Element(tag); },
};

vm.runInNewContext(script, { document });
const graph = document.getElementById('graph');
const nodes = () => graph.children.filter(x => x.tag === 'g');
const links = () => graph.children.filter(x => x.tag === 'path');
const summary = document.getElementById('summary').textContent;
assert.match(summary, /arquivos/);
assert.ok(nodes().length > 0);

const fileCount = Number(summary.match(/(\d+) arquivos/)?.[1] || 0);
if (fileCount > 250) {
  assert.equal(nodes().length, 2, 'large graph opens with the target and a direct consumer');
  const firstConsumer = nodes().find(x => !x.attrs.class.includes('target'));
  firstConsumer.click();
  assert.equal(nodes().length, 3, 'selecting a consumer expands the next step');
  document.getElementById('allRoutes').click();
  assert.equal(nodes().length, fileCount, 'all resolved DPR routes remain accessible');
} else {
  assert.ok(links().length > 0);
  document.getElementById('allRoutes').click();
  assert.match(document.getElementById('status').textContent, /Todas as rotas resolvidas/);
  const cuts = document.getElementById('cuts');
  if (summary.includes('Target → Small')) {
    assert.equal(cuts.children.filter(x => x.tag === 'button').length, 2,
      'both converging direct consumers must be reviewed');
  }
}

if (script.includes('MissingUnit')) {
  assert.match(summary, /Resultado parcial/);
  const uncertain = document.getElementById('uncertain');
  assert.ok(uncertain.children.some(x => x.tag === 'button' &&
    x.textContent.includes('MissingUnit')),
    'potentially relevant unresolved references are visible');
}

console.log('Visual render tests passed');
