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
const summary = document.getElementById('summary').textContent;
const counts = summary.match(/(\d+) arquivos alcançáveis \| (\d+) pastas \| (\d+) relações/);
assert.ok(counts, 'summary exposes file, folder, and relationship counts');
const [, fileCount, folderCount, relationCount] = counts.map(Number);
assert.equal(graphNodes().length, folderCount,
  'folder mode starts with every reachable folder');
const folderTree = document.getElementById('folders');
const folderEntries = folderTree.children.filter(x => x.tag === 'details');
assert.equal(folderEntries.length, folderCount,
  'sidebar lists every reachable folder');
assert.equal(folderEntries.reduce((total, entry) => total +
  entry.children.filter(x => x.tag === 'button').length, 0), fileCount,
  'folder tree lists every reachable file');
assert.match(document.getElementById('folderSummary').children[0].textContent,
  new RegExp(`Resumo: ${folderCount} pastas únicas, ${fileCount} arquivos`));
assert.equal(document.getElementById('folderSummary').children[1].children.length,
  folderCount, 'folder summary lists each folder exactly once');
graphNodes()[0].click();
assert.ok(document.getElementById('unitMode').classes.has('active'),
  'clicking a folder in the graph opens its units');
document.getElementById('folderMode').click();
folderEntries[0].children.find(x => x.tag === 'button').click();
assert.ok(document.getElementById('unitMode').classes.has('active'),
  'selecting a file switches to unit mode');
assert.ok(document.getElementById('detail').textContent.includes('Pasta:'),
  'selecting a file exposes its path and folder');
document.getElementById('search').value = '';
document.getElementById('search').oninput();
document.getElementById('unitMode').click();
assert.equal(graphNodes().length, fileCount,
  'unit mode shows every reachable file');
assert.equal(document.getElementById('status').textContent,
  `${fileCount} arquivo(s) | ${relationCount} relação(ões)`);
document.getElementById('folderMode').click();
assert.equal(graphNodes().length, folderCount, 'folder mode can be restored');
console.log('Project map render tests passed');
