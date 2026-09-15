// SPDX-License-Identifier: Apache-2.0

unit Reverse.Visual;

interface

uses Reverse.Analysis;

type
  TVisualWriter = class
  public
    class procedure WriteHtml(const Analysis: TAnalysisResult;
      const FileName: string);
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections,
  Reverse.Domain;

function SafeJson(const Value: string): string;
var
  Json: TJSONString;
begin
  Json := TJSONString.Create(Value);
  try
    Result := Json.ToJSON.Replace('<', '\u003c')
      .Replace('>', '\u003e').Replace('&', '\u0026');
  finally
    Json.Free;
  end;
end;

class procedure TVisualWriter.WriteHtml(const Analysis: TAnalysisResult;
  const FileName: string);
var
  Html: TStringList;
  Edge: TDependency;
  First: Boolean;
  SeenEdges: TDictionary<string, Boolean>;
begin
  Html := TStringList.Create;
  SeenEdges := TDictionary<string, Boolean>.Create;
  try
    Html.Add('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">');
    Html.Add('<meta name="viewport" content="width=device-width,initial-scale=1">');
    Html.Add('<title>Delphi Unit Backtrace — grafo reverso</title>');
    Html.Add('<style>');
    Html.Add('body{margin:0;font:14px system-ui,sans-serif;color:#e6edf3;background:#0d1117}');
    Html.Add('header{padding:14px 20px;background:#161b22;border-bottom:1px solid #30363d}');
    Html.Add('h1{font-size:20px;margin:0 0 6px}p{margin:4px 0;color:#8b949e}');
    Html.Add('.layout{display:grid;grid-template-columns:280px 1fr;height:calc(100vh - 92px)}');
    Html.Add('aside{padding:16px;border-right:1px solid #30363d;overflow:auto;background:#161b22}');
    Html.Add('input,button{box-sizing:border-box;width:100%;padding:9px;margin:5px 0;background:#0d1117;color:#e6edf3;border:1px solid #30363d;border-radius:6px}');
    Html.Add('button{cursor:pointer}button:hover{border-color:#58a6ff}label{display:block;margin:12px 0}');
    Html.Add('#viewport{overflow:auto;position:relative}svg{display:block;min-width:100%;min-height:100%}');
    Html.Add('.edge{stroke:#59636e;stroke-width:1.4;fill:none}.edge.focus{stroke:#f2cc60;stroke-width:3}');
    Html.Add('.node rect{fill:#21262d;stroke:#59636e;stroke-width:1.5;rx:7}');
    Html.Add('.node text{fill:#e6edf3;font-size:12px;pointer-events:none}');
    Html.Add('.node{cursor:pointer}.node.target rect{fill:#173c2b;stroke:#3fb950}');
    Html.Add('.node.dpr rect{fill:#3b241e;stroke:#f0883e}.node.focus rect{stroke:#f2cc60;stroke-width:3}');
    Html.Add('.muted{opacity:.16}#detail{white-space:pre-wrap;word-break:break-word;line-height:1.5;margin-top:12px}');
    Html.Add('@media(max-width:750px){.layout{grid-template-columns:1fr;grid-template-rows:240px 1fr}aside{border-right:0;border-bottom:1px solid #30363d}}');
    Html.Add('</style></head><body>');
    Html.Add('<header><h1>Delphi Unit Backtrace</h1><p id="summary"></p></header>');
    Html.Add('<div class="layout"><aside>');
    Html.Add('<input id="search" type="search" placeholder="Buscar unit ou arquivo" aria-label="Buscar unit ou arquivo">');
    Html.Add('<label><input id="dprOnly" type="checkbox" style="width:auto"> Mostrar somente caminhos até o DPR</label>');
    Html.Add('<button id="reset">Mostrar grafo completo</button>');
    Html.Add('<p>Selecione uma unit ou ligação para ver detalhes. Use a rolagem para percorrer o grafo.</p>');
    Html.Add('<div id="detail"></div></aside><main id="viewport"><svg id="graph"></svg></main></div>');
    Html.Add('<script>');
    Html.Add('const target=' + SafeJson(Analysis.TargetFile) + ', program=' +
      SafeJson(Analysis.ProgramFile) + ';');
    Html.Add('const targetName=' + SafeJson(Analysis.TargetName) + ', programName=' +
      SafeJson(Analysis.ProgramName) + ';');
    Html.Add('const unresolved=' + Analysis.UnresolvedCount.ToString +
      ', ambiguous=' + Analysis.AmbiguousCount.ToString +
      ', failed=' + Analysis.FailedCount.ToString +
      ', fallback=' + Analysis.FallbackCount.ToString + ';');
    Html.Add('const edges=[');
    First := True;
    for Edge in Analysis.Reachable do
    begin
      if SeenEdges.ContainsKey(DependencyIdentity(Edge)) then Continue;
      SeenEdges.Add(DependencyIdentity(Edge), True);
      if not First then Html.Add(',');
      First := False;
      Html.Add('{from:' + SafeJson(Edge.UsedPath) + ',to:' +
        SafeJson(Edge.ConsumerPath) + ',used:' + SafeJson(Edge.UsedName) +
        ',consumer:' + SafeJson(Edge.Consumer) + ',section:' +
        SafeJson(Edge.Section) + ',line:' + Edge.Line.ToString +
        ',source:' + SafeJson(Edge.SourceFile) + '}');
    end;
    Html.Add('];');
    Html.Add('const svg=document.getElementById("graph"), detail=document.getElementById("detail");');
    Html.Add('const ns="http://www.w3.org/2000/svg";');
    Html.Add('function el(tag,attrs,parent){const x=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))x.setAttribute(k,v);parent.appendChild(x);return x}');
    Html.Add('const nodes=new Map([[target,{name:targetName}]]);');
    Html.Add('for(const e of edges){if(!nodes.has(e.from))nodes.set(e.from,{name:e.used});if(!nodes.has(e.to))nodes.set(e.to,{name:e.consumer})}');
    Html.Add('const out=new Map(),incoming=new Map();for(const e of edges){if(!out.has(e.from))out.set(e.from,[]);out.get(e.from).push(e);if(!incoming.has(e.to))incoming.set(e.to,[]);incoming.get(e.to).push(e)}');
    Html.Add('const toDpr=new Set([program]);const q=[program];for(let i=0;i<q.length;i++)for(const e of incoming.get(q[i])||[])if(!toDpr.has(e.from)){toDpr.add(e.from);q.push(e.from)}');
    Html.Add('document.getElementById("summary").textContent=`${targetName} → ${programName} | ${nodes.size} arquivos | ${edges.length} ligações | ${toDpr.has(target)?"Há caminho até o DPR":"Sem caminho até o DPR"} | ${unresolved+ambiguous+failed+fallback?`Resultado parcial: ${unresolved} não resolvidas, ${ambiguous} ambíguas, ${failed} falhas, ${fallback} fallbacks`:"Análise completa"}`;');
    Html.Add('let selected=null;function show(text){detail.textContent=text}');
    Html.Add('function render(){const filter=document.getElementById("dprOnly").checked;const term=document.getElementById("search").value.toLowerCase();');
    Html.Add('const visible=filter?new Set([...toDpr].filter(x=>nodes.has(x))):new Set(nodes.keys());');
    Html.Add('const levels=new Map([[target,0]]),queue=[target];for(let i=0;i<queue.length;i++)for(const e of out.get(queue[i])||[])if(visible.has(e.to)&&!levels.has(e.to)){levels.set(e.to,levels.get(queue[i])+1);queue.push(e.to)}');
    Html.Add('for(const x of visible)if(!levels.has(x))levels.set(x,0);');
    Html.Add('const groups=new Map();for(const x of visible){const level=levels.get(x);if(!groups.has(level))groups.set(level,[]);groups.get(level).push(x)}');
    Html.Add('for(const group of groups.values())group.sort((a,b)=>nodes.get(a).name.localeCompare(nodes.get(b).name));');
    Html.Add('const maxLevel=Math.max(0,...groups.keys()),maxRows=Math.max(1,...[...groups.values()].map(x=>x.length));');
    Html.Add('const width=(maxLevel+1)*240+80,height=maxRows*58+70;svg.setAttribute("viewBox",`0 0 ${width} ${height}`);svg.setAttribute("width",width);svg.setAttribute("height",height);svg.replaceChildren();');
    Html.Add('const pos=new Map();for(const [level,group] of groups)group.forEach((x,i)=>pos.set(x,{x:30+level*240,y:30+i*58}));');
    Html.Add('const defs=el("defs",{},svg),marker=el("marker",{id:"arrow",viewBox:"0 0 10 10",refX:9,refY:5,markerWidth:7,markerHeight:7,orient:"auto"},defs);el("path",{d:"M 0 0 L 10 5 L 0 10 z",fill:"#59636e"},marker);');
    Html.Add('for(const e of edges){if(!pos.has(e.from)||!pos.has(e.to))continue;const a=pos.get(e.from),b=pos.get(e.to);const line=el("path",{d:`M ${a.x+175} ${a.y+18} C ${a.x+195} ${a.y+18}, ${b.x-20} ${b.y+18}, ${b.x} ${b.y+18}`,class:`edge${selected===e?" focus":""}${term&&!(`${e.used} ${e.consumer} ${e.from} ${e.to}`.toLowerCase().includes(term))?" muted":""}`,"marker-end":"url(#arrow)"},svg);line.addEventListener("click",()=>{selected=e;show(`${e.used} → ${e.consumer}\n${e.section}:${e.line}\nDeclaração: ${e.source}:${e.line}\nArquivo usado: ${e.from}\nConsumidor: ${e.to}`);render()})}');
    Html.Add('for(const [path,p] of pos){const name=nodes.get(path).name,g=el("g",{class:`node${path===target?" target":""}${path===program?" dpr":""}${selected===path?" focus":""}${term&&!(`${name} ${path}`.toLowerCase().includes(term))?" muted":""}`},svg);el("rect",{x:p.x,y:p.y,width:175,height:36},g);const label=el("text",{x:p.x+9,y:p.y+23},g);label.textContent=name.length>23?name.slice(0,21)+"…":name;const title=el("title",{},g);title.textContent=`${name}\n${path}`;g.addEventListener("click",()=>{selected=path;show(`${name}\n${path}\nUsada por ${(out.get(path)||[]).length} arquivo(s)\nUsa ${[...new Set((incoming.get(path)||[]).map(e=>e.used))].length} unit(s)${toDpr.has(path)?"\nTem caminho até o DPR":""}`);render()})}');
    Html.Add('}');
    Html.Add('document.getElementById("search").addEventListener("input",render);document.getElementById("dprOnly").addEventListener("change",render);');
    Html.Add('document.getElementById("reset").addEventListener("click",()=>{selected=null;document.getElementById("search").value="";document.getElementById("dprOnly").checked=false;show("");render()});render();');
    Html.Add('</script></body></html>');
    TFile.WriteAllText(FileName, Html.Text, TEncoding.UTF8);
  finally
    SeenEdges.Free;
    Html.Free;
  end;
end;

end.
