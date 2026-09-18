// SPDX-License-Identifier: Apache-2.0

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync(process.argv[2] ||
  'bin/project-map-output/graph.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert.ok(script, 'project map HTML must contain a script');

class Element {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.handlers = new Map();
    this.attrs = {};
    this.value = '';
    this.style = {};
    this.scrollLeft = 0;
    this.scrollTop = 0;
    this.classes = new Set();
    this.classList = {
      add: value => this.classes.add(value),
      remove: value => this.classes.delete(value),
      toggle: (value, enabled) => enabled ? this.classes.add(value) :
        this.classes.delete(value),
    };
  }
  setAttribute(key, value) {
    this.attrs[key] = String(value);
    if (key === 'class')
      this.classes = new Set(String(value).split(/\s+/).filter(Boolean));
  }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  addEventListener(name, handler) { this.handlers.set(name, handler); }
  click() { return this.onclick?.() ?? this.handlers.get('click')?.(); }
}

const elements = new Map();
const document = {
  getElementById(id) {
    if (!elements.has(id)) {
      const element = new Element(id);
      if (id === 'section') element.value = 'all';
      if (id === 'folderDepth') {
        element.value = '1';
        const option = new Element('option');
        option.value = '1';
        element.appendChild(option);
      }
      if (id === 'folderSummary') {
        element.appendChild(new Element('summary'));
        element.appendChild(new Element('ul'));
      }
      elements.set(id, element);
    }
    return elements.get(id);
  },
  createElementNS(_namespace, tag) { return new Element(tag); },
  createElement(tag) { return new Element(tag); },
};

vm.runInContext(script, vm.createContext({ document }));
const graph = document.getElementById('graph');
const graphNodes = () => graph.children.filter(x => x.tag === 'g');
const depthOptions = document.getElementById('folderDepth').children;
assert.ok(depthOptions.length >= 2,
  'folder grouping offers every discovered level and the full path');
for (let index = 0; index < depthOptions.length - 1; index++)
  assert.equal(depthOptions[index].value, String(index + 1),
    'folder levels are consecutive and adapt to the project depth');
assert.equal(depthOptions.at(-1).value, 'all');
const summary = document.getElementById('summary').textContent;
const counts = summary.match(/(\d+) arquivos alcançáveis \| (\d+) pastas \| (\d+) relações/);
assert.ok(counts, 'summary exposes file, folder, and relationship counts');
const [, fileCount, folderCount, relationCount] = counts.map(Number);
const initialGroupCount = Number(document.getElementById('status').textContent
  .match(/(\d+) pasta\(s\)/)?.[1] || 0);
assert.ok(initialGroupCount > 0 && initialGroupCount <= folderCount,
  'folder mode groups physical directories at the selected depth');
assert.equal(graphNodes().length, initialGroupCount);
const folderTree = document.getElementById('folders');
const folderEntries = folderTree.children.filter(x => x.tag === 'details');
assert.equal(folderEntries.length, folderCount,
  'sidebar lists every reachable folder');
assert.equal(folderEntries.reduce((total, entry) => total +
  entry.children.filter(x => x.tag === 'button').length, 0), 0,
  'folder tree defers file elements until a folder is expanded');
assert.match(document.getElementById('folderSummary').children[0].textContent,
  new RegExp(`Resumo: ${folderCount} pastas únicas, ${fileCount} arquivos`));
assert.equal(document.getElementById('folderSummary').children[1].children.length,
  folderCount, 'folder summary lists each folder exactly once');
graphNodes()[0].click();
const openedUnits = document.getElementById('unitMode').classes.has('active');
assert.ok(openedUnits || document.getElementById('folderMode').classes.has('active'),
  'clicking a folder opens its units or drills into the next folder level');
if (!openedUnits) {
  assert.equal(document.getElementById('folderBack').disabled, false,
    'drill-down enables navigation to the previous level');
  document.getElementById('folderBack').click();
  assert.ok(graphNodes().length > 0, 'returning from a folder keeps the graph navigable');
}
document.getElementById('folderMode').click();
folderEntries[0].open = true;
folderEntries[0].ontoggle();
const loadedButtons = folderEntries[0].children.filter(x => x.tag === 'button');
assert.ok(loadedButtons.length > 1,
  'expanding a folder loads its navigation button and files on demand');
loadedButtons[0].click();
assert.ok(document.getElementById('unitMode').classes.has('active'),
  'opening a physical folder switches to unit mode');
assert.equal(document.getElementById('folderBack').disabled, false,
  'opening a physical folder keeps a return path');
document.getElementById('folderBack').click();
loadedButtons[1].click();
assert.ok(document.getElementById('unitMode').classes.has('active'),
  'selecting a file switches to unit mode');
assert.ok(document.getElementById('detail').textContent.includes('Pasta:'),
  'selecting a file exposes its path and folder');
document.getElementById('folderBack').click();
document.getElementById('folderMode').click();
document.getElementById('search').value = '';
document.getElementById('search').oninput();
document.getElementById('unitMode').click();
if (fileCount <= 1000) {
  assert.equal(graphNodes().length, fileCount,
    'unit mode shows every reachable file in a manageable map');
  assert.equal(document.getElementById('status').textContent,
    `${fileCount} arquivo(s) | ${relationCount} relação(ões)`);
} else {
  assert.ok(document.getElementById('folderMode').classes.has('active'),
    'large maps stay grouped until a folder is selected');
  assert.match(document.getElementById('detail').textContent,
    /Selecione primeiro uma pasta/);
}
document.getElementById('folderMode').click();
assert.equal(graphNodes().length, initialGroupCount, 'grouped folder mode can be restored');
const multiFolderGroup = graphNodes().find(node => node.children.some(child =>
  child.tag === 'text' && /• ([2-9]|\d{2,}) pasta\(s\)/.test(child.textContent || '')));
if (multiFolderGroup) {
  multiFolderGroup.click();
  assert.ok(document.getElementById('folderMode').classes.has('active'),
    'a group with subfolders drills down without rendering all units');
  assert.equal(document.getElementById('folderBack').disabled, false);
  assert.ok(graphNodes().length > 0, 'the next directory level is visible');
  document.getElementById('folderBack').click();
}
document.getElementById('folderDepth').value = 'all';
document.getElementById('folderDepth').onchange();
assert.equal(graphNodes().length, folderCount,
  'complete path mode restores every physical folder');
document.getElementById('folderMode').click();
assert.equal(document.getElementById('folderDepth').value, '1',
  'folder overview returns to the first hierarchy level');
assert.equal(graphNodes().length, initialGroupCount,
  'folder overview regroups src and other parent directories');
console.log('Project map render tests passed');
