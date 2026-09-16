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
    this.scrollLeft = 0;
    this.scrollTop = 0;
    this.style = {};
    this.classes = new Set();
    this.classList = { add: x => this.classes.add(x), remove: x => this.classes.delete(x) };
  }
  setAttribute(key, value) { this.attrs[key] = String(value); }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(name, handler) { this.handlers.set(name, handler); }
  click() { return this.handlers.get('click')?.(); }
  dispatch(name, event = {}) { return this.handlers.get(name)?.(event); }
  closest(selector) {
    return selector === '.node,.edge' && /(^| )(node|edge)( |$)/.test(this.attrs.class || '') ? this : null;
  }
}

const elements = new Map();
const document = {
  getElementById(id) {
    if (!elements.has(id)) {
      const element = new Element(id);
      if (id === 'sectionFilter') element.value = 'all';
      elements.set(id, element);
    }
    return elements.get(id);
  },
  createElementNS(_namespace, tag) { return new Element(tag); },
  createElement(tag) { return new Element(tag); },
};

const copied = [];
const context = vm.createContext({ document, navigator: { clipboard: { writeText: async value => copied.push(value) } } });
vm.runInContext(script, context);
const graph = document.getElementById('graph');
const nodes = () => graph.children.filter(x => x.tag === 'g');
const links = () => graph.children.filter(x => x.tag === 'path');
const summary = document.getElementById('summary').textContent;
assert.match(summary, /arquivos/);
assert.ok(nodes().length > 0);

const fileCount = Number(summary.match(/(\d+) arquivos/)?.[1] || 0);
async function run() {
if (fileCount > 250) {
  assert.equal(nodes().length, 2, 'large graph opens with the target and a direct consumer');
  const targetNode = nodes().find(x => x.attrs.class.includes('target'));
  const view = document.getElementById('viewport');
  view.scrollLeft = 0; view.scrollTop = 0;
  view.dispatch('pointerdown', { target: targetNode, pointerId: 1, clientX: 100, clientY: 100 });
  view.dispatch('pointermove', { target: targetNode, clientX: 70, clientY: 70 });
  assert.equal(view.scrollLeft, 0, 'pressing a node does not start graph panning');
  assert.equal(view.scrollTop, 0, 'pressing a node keeps the viewport still');
  targetNode.click();
  assert.equal(nodes().length, fileCount,
    'clicking a node makes its complete selected chain visible');
  assert.equal(links().length, fileCount - 1);
  assert.ok(links().every(x => x.attrs.class.includes('trace')),
    'every edge in the selected chain is highlighted');
  vm.runInContext('gotoTraceStep(traceResult.edges.length-1)', context);
  assert.ok(document.getElementById('trace').children.some(x =>
    x.textContent?.includes('Passo 2201 de 2201')),
    'long selected chains remain navigable through their final declaration');
  document.getElementById('allRoutes').click();
  assert.equal(nodes().length, fileCount, 'all resolved DPR routes remain accessible');
} else {
  assert.ok(links().length > 0);
  document.getElementById('allRoutes').click();
  assert.match(document.getElementById('status').textContent, /Todas as rotas resolvidas/);
  assert.ok(links().every(x => x.attrs.class.includes('trace')),
    'all DPR routes are highlighted without isolating a chain first');
  const directRouteState = links().map(x => x.attrs.class);
  document.getElementById('reset').click();
  document.getElementById('route').click();
  document.getElementById('allRoutes').click();
  assert.deepEqual(links().map(x => x.attrs.class), directRouteState,
    'all routes produces the same graph with or without a previous isolated chain');
  const cuts = document.getElementById('cuts');
  if (summary.includes('Target → Small')) {
    assert.equal(cuts.children.filter(x => x.tag === 'button').length, 2,
      'both converging direct consumers must be reviewed');
    const section = document.getElementById('sectionFilter');
    const allLinks = links().length;
    section.value = 'interface'; section.dispatch('change');
    assert.ok(links().length > 0 && links().length < allLinks, 'interface filter shows only its declarations');
    section.value = 'program'; section.dispatch('change');
    assert.equal(links().length, 2, 'DPR filter shows project entry declarations');
    section.value = 'all'; section.dispatch('change');

    const target = nodes().find(x => x.attrs.class.includes('target'));
    target.click();
    const trace = document.getElementById('trace');
    assert.ok(trace.children.some(x => x.textContent?.includes('Passo 1 de')),
      'selected route starts at its first step');
    const controls = trace.children.find(x => x.id === 'traceControls');
    controls.children[1].click();
    assert.ok(trace.children.some(x => x.textContent?.includes('Passo 2 de')),
      'next navigates through the selected chain');
    document.getElementById('traceControls');
    document.getElementById('zoomIn').click();
    const enlarged = Number(graph.attrs.width);
    document.getElementById('zoomOut').click();
    assert.ok(Number(graph.attrs.width) < enlarged, 'zoom controls change SVG size');
    document.getElementById('fitTrace').click();
    assert.match(document.getElementById('status').textContent, /Cadeia isolada/);
    document.getElementById('fitAll').click();
    assert.ok(Number(graph.attrs.width) <= 900, 'fit visible graph uses viewport width');
    document.getElementById('reset').click();

    const direct = links().filter(x => x.children.some(y => y.tag === 'title' &&
      /Target →/.test(y.textContent)));
    assert.equal(direct.length, 2, 'fixture has two direct target consumers');
    const cut = document.getElementById('cutToggle');
    direct[0].click();
    await document.getElementById('copySource').click();
    assert.match(copied.at(-1), /\.pas:\d+$/i, 'copy includes declaration file and line');
    cut.click();
    assert.match(document.getElementById('simulation').children[1].textContent, /Ainda há caminho/,
      'one cut leaves another route to DPR');
    links().find(x => x.children.some(y => y.tag === 'title' &&
      /Target →/.test(y.textContent) && y.textContent !== direct[0].children.find(z => z.tag === 'title').textContent)).click();
    cut.click();
    assert.match(document.getElementById('simulation').children[1].textContent, /Sem caminho/,
      'both cuts disconnect the resolved graph');
    document.getElementById('cutReset').click();
    assert.match(document.getElementById('simulation').children[1].textContent, /Ainda há caminho/);

    const view = document.getElementById('viewport');
    view.scrollLeft = 50; view.scrollTop = 60;
    view.dispatch('pointerdown', { pointerId: 1, clientX: 100, clientY: 100 });
    view.dispatch('pointermove', { clientX: 80, clientY: 70 });
    assert.equal(view.scrollLeft, 70, 'pointer dragging pans horizontally');
    assert.equal(view.scrollTop, 90, 'pointer dragging pans vertically');
    view.dispatch('pointerup');
  }
}

if (script.includes('MissingUnit')) {
  assert.match(summary, /Resultado parcial/);
  const uncertain = document.getElementById('uncertain');
  assert.ok(uncertain.children.some(x => x.tag === 'button' &&
    x.textContent.includes('MissingUnit')),
    'potentially relevant unresolved references are visible');
}
if (summary.includes('Resultado parcial')) {
  assert.ok(document.getElementById('simulation').children.some(x =>
    x.textContent?.includes('Resultado parcial')),
    'simulation warns that an unresolved graph cannot prove a complete cut');
}

console.log('Visual render tests passed');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
