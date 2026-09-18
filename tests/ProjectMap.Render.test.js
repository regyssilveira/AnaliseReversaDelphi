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
assert.match(document.getElementById('summary').textContent,
  /4 arquivos alcançáveis \| 1 pastas \| 5 relações/);
assert.equal(graphNodes().length, 1, 'folder mode starts with one grouped folder');
assert.equal(document.getElementById('folders').children.length, 1,
  'sidebar lists every reachable folder');
document.getElementById('unitMode').click();
assert.equal(graphNodes().length, 4, 'unit mode shows every reachable file');
assert.match(document.getElementById('status').textContent,
  /4 arquivo\(s\) \| 5 relação\(ões\)/);
document.getElementById('folderMode').click();
assert.equal(graphNodes().length, 1, 'folder mode can be restored');
console.log('Project map render tests passed');
