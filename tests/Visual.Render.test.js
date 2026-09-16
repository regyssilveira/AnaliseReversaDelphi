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
  setAttribute(key, value) {
    this.attrs[key] = String(value);
    if (key === 'class') this.classes = new Set(String(value).split(/\s+/).filter(Boolean));
  }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(name, handler) { this.handlers.set(name, handler); }
  click() { return this.handlers.get('click')?.(); }
  dispatch(name, event = {}) { return this.handlers.get(name)?.(event); }
  closest(selector) {
    return selector === '.node,.edge' && /(^| )(node|edge)( |$)/.test(this.attrs.class || '') ? this : null;
  }
  querySelectorAll(selector) {
    const wanted = selector.split(',').map(x => x.trim().replace(/^\./, ''));
    const result = [];
    const visit = element => {
      if (wanted.some(x => element.classes.has(x))) result.push(element);
      for (const child of element.children) visit(child);
    };
    for (const child of this.children) visit(child);
    return result;
  }
}

const elements = new Map();
const document = {
  getElementById(id) {
    if (!elements.has(id)) {
      const element = new Element(id);
      if (id === 'sectionFilter' || id === 'originFilter') element.value = 'all';
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
const initialNodeCount = nodes().length;
assert.ok(initialNodeCount <= fileCount);
const routeGroups = document.getElementById('routePanel').children.filter(x => x.tag === 'details');
assert.equal(routeGroups.length, 5, 'route list is grouped by destination');
const routeButtons = routeGroups.flatMap(x => x.children.filter(y => y.tag === 'button'));
assert.ok(routeButtons.length > 0, 'route list exposes selectable routes');
async function run() {
document.getElementById('reset').click();
assert.equal(nodes().length, fileCount, 'full graph button restores the complete graph');
document.getElementById('progressiveView').click();
assert.equal(nodes().length, initialNodeCount, 'progressive view button restores the clean initial graph');
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
  assert.ok(initialNodeCount < fileCount, 'small graphs also start in progressive mode');
  routeButtons[0].click();
  assert.match(document.getElementById('status').textContent, /Cadeia isolada/,
    'selecting a listed route isolates it in the graph');
  document.getElementById('reset').click();
  document.getElementById('allRoutes').click();
  assert.match(document.getElementById('status').textContent, /Rotas até o DPR/);
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

    document.getElementById('collapseBranch').click();
    assert.equal(nodes().length, 1, 'collapsing the target leaves only its box');
    document.getElementById('expandDpr').click();
    assert.ok(nodes().some(x => x.attrs.class.includes('dpr')),
      'expand to DPR reveals the project entry point');
    assert.ok(document.getElementById('trace').children.some(x =>
      x.textContent === 'Cadeia até o DPR'));
    document.getElementById('reset').click();
    document.getElementById('collapseBranch').click();
    document.getElementById('expandBranch').click();
    assert.ok(nodes().length > 1 && nodes().length < fileCount,
      'expanding one branch reveals only the next level');
    document.getElementById('expandEnd').click();
    assert.equal(nodes().length, fileCount, 'expand to end reveals the complete branch');
    document.getElementById('hideBranch').click();
    assert.equal(nodes().length, 1, 'hide branch removes its consumers');
    document.getElementById('reset').click();

    const hoverTarget = nodes().find(x => x.attrs.class.includes('target'));
    hoverTarget.dispatch('mouseenter');
    assert.ok(links().some(x => x.classes.has('hover')), 'hover highlights a related chain');
    assert.ok(links().some(x => x.classes.has('hover-muted')), 'hover fades unrelated links');
    hoverTarget.dispatch('mouseleave');
    assert.ok(links().every(x => !x.classes.has('hover') && !x.classes.has('hover-muted')));
    hoverTarget.dispatch('dblclick');
    assert.match(document.getElementById('status').textContent, /Cadeia isolada/,
      'double-click isolates the node route');
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
if (/1 biblioteca/.test(summary)) {
  document.getElementById('outsideRoutes').click();
  assert.match(document.getElementById('status').textContent, /Usos fora do DPR/);
  assert.equal(links().length, 3, 'all non-DPR dependency links are visible');
  assert.ok(links().every(x => x.attrs.class.includes('trace')),
    'non-DPR dependency links are highlighted');
  assert.ok(nodes().some(x => x.attrs.class.includes('origin-project-search-path')),
    'library nodes expose their project Search Path origin');
  const origin = document.getElementById('originFilter');
  origin.value = 'project-search-path'; origin.dispatch('change');
  assert.equal(links().length, 2, 'origin filter keeps the selected library branch');
  document.getElementById('reset').click();
  const terminalNames = ['Detached', 'ProjectOnly', 'LibraryRoot'];
  const terminalX = nodes().filter(node => node.children.some(child => child.tag === 'title' &&
    terminalNames.some(name => child.textContent?.startsWith(name + '\n'))))
    .map(node => node.children.find(child => child.tag === 'rect').attrs.x);
  assert.equal(new Set(terminalX).size, 1, 'all route destinations share the final column');
}

console.log('Visual render tests passed');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
