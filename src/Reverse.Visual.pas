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
  Warning: TUncertainReference;
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
    Html.Add('#matches button{text-align:left;margin:2px 0;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}');
    Html.Add('#matches{max-height:180px;overflow:auto;margin-bottom:8px}#status{color:#8b949e}');
    Html.Add('#viewport{overflow:auto;position:relative}svg{display:block;min-width:100%;min-height:100%}');
    Html.Add('.edge{stroke:#59636e;stroke-width:1.4;fill:none}.edge.trace{stroke:#f2cc60;stroke-width:3}.edge.focus{stroke:#ff7b72;stroke-width:4}');
    Html.Add('.node rect{fill:#21262d;stroke:#59636e;stroke-width:1.5;rx:7}');
    Html.Add('.node text{fill:#e6edf3;font-size:12px;pointer-events:none}');
    Html.Add('.node{cursor:pointer}.node.target rect{fill:#173c2b;stroke:#3fb950}');
    Html.Add('.node.dpr rect{fill:#3b241e;stroke:#f0883e}.node.trace rect{stroke:#f2cc60;stroke-width:2.5}.node.focus rect{stroke:#ff7b72;stroke-width:3}');
    Html.Add('.muted{opacity:.16}#detail{white-space:pre-wrap;word-break:break-word;line-height:1.5;margin-top:12px}');
    Html.Add('#trace{margin-top:14px;border-top:1px solid #30363d;padding-top:10px;line-height:1.5}#trace button{text-align:left;font-size:12px;white-space:normal;word-break:break-word}');
    Html.Add('#cuts,#uncertain{margin-top:14px;border-top:1px solid #30363d;padding-top:10px;line-height:1.5}#cuts button,#uncertain button{text-align:left;font-size:12px;white-space:normal;word-break:break-word}');
    Html.Add('@media(max-width:750px){.layout{grid-template-columns:1fr;grid-template-rows:240px 1fr}aside{border-right:0;border-bottom:1px solid #30363d}}');
    Html.Add('</style></head><body>');
    Html.Add('<header><h1>Delphi Unit Backtrace</h1><p id="summary"></p></header>');
    Html.Add('<div class="layout"><aside>');
    Html.Add('<input id="search" type="search" placeholder="Buscar unit ou arquivo" aria-label="Buscar unit ou arquivo">');
    Html.Add('<div id="matches"></div>');
    Html.Add('<label><input id="dprOnly" type="checkbox" style="width:auto"> Mostrar somente caminhos até o DPR</label>');
    Html.Add('<button id="neighbors">Ver ligações da unit selecionada</button>');
    Html.Add('<button id="route">Isolar cadeia destacada</button>');
    Html.Add('<button id="allRoutes">Mostrar todas as rotas até o DPR</button>');
    Html.Add('<button id="reset">Mostrar grafo completo</button>');
    Html.Add('<p id="status">Selecione uma unit ou ligação para ver detalhes. A busca centraliza a unit encontrada.</p>');
    Html.Add('<div id="detail"></div><div id="trace"></div><div id="cuts"></div><div id="uncertain"></div></aside><main id="viewport"><svg id="graph"></svg></main></div>');
    Html.Add('<script>');
    Html.Add('const target=' + SafeJson(Analysis.TargetFile) + ', program=' +
      SafeJson(Analysis.ProgramFile) + ', projectRoot=' +
      SafeJson(Analysis.ProjectRoot) + ';');
    Html.Add('const targetName=' + SafeJson(Analysis.TargetName) + ', programName=' +
      SafeJson(Analysis.ProgramName) + ';');
    Html.Add('const unresolved=' + Analysis.UnresolvedCount.ToString +
      ', ambiguous=' + Analysis.AmbiguousCount.ToString +
      ', failed=' + Analysis.FailedCount.ToString +
      ', fallback=' + Analysis.FallbackCount.ToString + ';');
    if Analysis.PathEvaluationWasFallback then
      Html.Add('const pathFallback=true;')
    else Html.Add('const pathFallback=false;');
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
    Html.Add('const uncertain=[');
    First := True;
    for Warning in Analysis.Uncertain do
    begin
      if not First then Html.Add(',');
      First := False;
      Html.Add('{used:' + SafeJson(Warning.Dependency.UsedName) +
        ',consumer:' + SafeJson(Warning.Dependency.Consumer) +
        ',to:' + SafeJson(Warning.Dependency.ConsumerPath) +
        ',source:' + SafeJson(Warning.Dependency.SourceFile) +
        ',line:' + Warning.Dependency.Line.ToString +
        ',reason:' + SafeJson(Warning.Reason) + '}');
    end;
    Html.Add('];');
    Html.Add('const svg=document.getElementById("graph"), detail=document.getElementById("detail");');
    Html.Add('const ns="http://www.w3.org/2000/svg";');
    Html.Add('function el(tag,attrs,parent){const x=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))x.setAttribute(k,v);parent.appendChild(x);return x}');
    Html.Add('const nodes=new Map([[target,{name:targetName}]]);');
    Html.Add('for(const e of edges){if(!nodes.has(e.from))nodes.set(e.from,{name:e.used});if(!nodes.has(e.to))nodes.set(e.to,{name:e.consumer})}');
    Html.Add('const reachableNames=new Set([...nodes.values()].map(x=>x.name.toLowerCase()));');
    Html.Add('const out=new Map(),incoming=new Map();for(const e of edges){if(!out.has(e.from))out.set(e.from,[]);out.get(e.from).push(e);if(!incoming.has(e.to))incoming.set(e.to,[]);incoming.get(e.to).push(e)}');
    Html.Add('const toDpr=new Set([program]);const q=[program];for(let i=0;i<q.length;i++)for(const e of incoming.get(q[i])||[])if(!toDpr.has(e.from)){toDpr.add(e.from);q.push(e.from)}');
    Html.Add('const dprEdges=new Set(edges.filter(e=>toDpr.has(e.from)&&toDpr.has(e.to)));');
    Html.Add('document.getElementById("summary").textContent=`${targetName} → ${programName} | ${nodes.size} arquivos | ${edges.length} ligações | ${toDpr.has(target)?"Há caminho até o DPR":"Sem caminho até o DPR"} | ${unresolved+ambiguous+failed+fallback+Number(pathFallback)?`Resultado parcial: ${unresolved} não resolvidas, ${ambiguous} ambíguas, ${failed} falhas, ${fallback} fallbacks${pathFallback?", caminhos MSBuild por fallback":""}`:"Análise completa"}`;');
    Html.Add('let selected=null,selectedPath=target,mode=nodes.size>250?"explore":"all",expanded=new Set([target]),currentPos=new Map(),traceResult=null;function show(text){detail.textContent=text}');
    Html.Add('function directCuts(path){return (out.get(path)||[]).filter(e=>toDpr.has(e.to))}');
    Html.Add('function showCuts(){const panel=document.getElementById("cuts");panel.replaceChildren();const heading=document.createElement("strong");heading.textContent="Declarações diretas a revisar para cortar todas as rotas até o DPR";panel.appendChild(heading);const cuts=directCuts(selectedPath);const note=document.createElement("p");note.textContent=cuts.length?`${cuts.length} declaração(ões) direta(s). Remover apenas uma pode deixar outras rotas. Confira se os símbolos usados permitem alterar cada uses.`:"Nenhuma declaração direta desta unit alcança o DPR no grafo resolvido.";panel.appendChild(note);for(const e of cuts){const b=document.createElement("button");b.textContent=`${e.consumer} usa ${e.used} | ${e.source}:${e.line} (${e.section})`;b.addEventListener("click",()=>{selected=e;show(`${e.used} → ${e.consumer}\nDeclaração: ${e.source}:${e.line}\nArquivo usado: ${e.from}\nConsumidor: ${e.to}`);render();center(e.to)});panel.appendChild(b)}}');
    Html.Add('function showUncertain(){const panel=document.getElementById("uncertain");panel.replaceChildren();if(!uncertain.length&&!failed&&!fallback&&!pathFallback)return;const heading=document.createElement("strong");heading.textContent="Ligações incertas e análise parcial";panel.appendChild(heading);const note=document.createElement("p");note.textContent="Referências incertas não foram acrescentadas ao grafo. Falhas, fallback do parser ou dos caminhos também podem omitir rotas. Confira analysis.log antes de alterar uses.";panel.appendChild(note);const relevant=uncertain.filter(x=>reachableNames.has(x.used.toLowerCase())||nodes.has(x.to));for(const x of relevant.slice(0,100)){const b=document.createElement("button");b.textContent=`${x.consumer} usa ${x.used} | ${x.reason} | ${x.source}:${x.line}`;b.addEventListener("click",()=>show(`${x.reason}\n${x.consumer} usa ${x.used}\n${x.source}:${x.line}`));panel.appendChild(b)}const rest=uncertain.length-relevant.length;if(rest||relevant.length>100){const p=document.createElement("p");p.textContent=`${relevant.length>100?`Mostrando 100 de ${relevant.length} referências potencialmente ligadas ao alvo. `:""}${rest?`${rest} outras referências incertas estão no log.`:""}`;panel.appendChild(p)}}');
    Html.Add('function inProject(path){if(!projectRoot)return false;const root=projectRoot.toLowerCase().replace(/[\\/]+$/,"");const file=path.toLowerCase();return file===root||file.startsWith(root+"/")||file.startsWith(root+"\\")}');
    Html.Add('function shortest(start,accept){const queue=[start],previous=new Map([[start,null]]),end=queue.find(accept);let found=end;for(let i=0;i<queue.length&&!found;i++){const x=queue[i];for(const e of out.get(x)||[])if(!previous.has(e.to)){previous.set(e.to,e);queue.push(e.to);if(accept(e.to)){found=e.to;break}}}if(!found)return null;const path=[];for(let x=found;x!==start;){const e=previous.get(x);path.unshift(e);x=e.from}return {edges:path,endpoint:found}}');
    Html.Add('function trace(start){const dpr=shortest(start,x=>x===program);if(dpr)return {...dpr,kind:"DPR"};const local=shortest(start,inProject);return local?{...local,kind:"PROJECT"}:null}');
    Html.Add('function traceNodes(){const result=new Set();if(traceResult){result.add(selectedPath);for(const e of traceResult.edges){result.add(e.from);result.add(e.to)}}return result}');
    Html.Add('function showTrace(){const panel=document.getElementById("trace");panel.replaceChildren();if(!traceResult){panel.textContent="Nenhuma cadeia até o DPR ou um arquivo do projeto foi encontrada.";return}');
    Html.Add('const heading=document.createElement("strong");heading.textContent=traceResult.kind==="DPR"?"Cadeia até o DPR":"Cadeia até um arquivo do projeto";panel.appendChild(heading);');
    Html.Add('const endpoint=document.createElement("p");endpoint.textContent=`Destino: ${nodes.get(traceResult.endpoint)?.name||traceResult.endpoint} (${traceResult.edges.length} ligação(ões))`;panel.appendChild(endpoint);');
    Html.Add('let step=0;for(const e of traceResult.edges.slice(0,50)){const b=document.createElement("button");b.textContent=`${++step}. ${e.used} → ${e.consumer} | ${e.section}:${e.line} | ${e.source}`;b.addEventListener("click",()=>{selected=e;show(`${e.used} → ${e.consumer}\nDeclaração: ${e.source}:${e.line}\nArquivo usado: ${e.from}\nConsumidor: ${e.to}`);render();center(e.to)});panel.appendChild(b)}if(traceResult.edges.length>50){const more=document.createElement("p");more.textContent=`Mais ${traceResult.edges.length-50} passos nesta cadeia. Use Isolar cadeia destacada para vê-la no grafo.`;panel.appendChild(more)}');
    Html.Add('const direct=new Set((out.get(selectedPath)||[]).map(e=>e.to)).size,note=document.createElement("p");note.textContent=direct?`A primeira ligação mostra um consumidor direto. Este arquivo tem ${direct} consumidor(es) direto(s); revise todos antes de remover a dependência.`:"Este arquivo já é o destino da cadeia.";panel.appendChild(note)}');
    Html.Add('function center(path){const p=currentPos.get(path),view=document.getElementById("viewport");if(p){view.scrollLeft=Math.max(0,p.x-view.clientWidth/2+90);view.scrollTop=Math.max(0,p.y-view.clientHeight/2+18)}}');
    Html.Add('function selectNode(path){selected=path;selectedPath=path;traceResult=trace(path);if(mode==="explore")expanded.add(path);if(!toDpr.has(path))document.getElementById("dprOnly").checked=false;const name=nodes.get(path).name;show(`${name}\n${path}\nUsada por ${(out.get(path)||[]).length} declaração(ões)\nUsa ${(incoming.get(path)||[]).length} declaração(ões)${toDpr.has(path)?"\nTem caminho até o DPR":""}`);showTrace();showCuts();render();center(path)}');
    Html.Add('function updateMatches(){const box=document.getElementById("matches"),term=document.getElementById("search").value.trim().toLowerCase();box.replaceChildren();if(!term)return;const found=[...nodes.keys()].filter(x=>`${nodes.get(x).name} ${x}`.toLowerCase().includes(term)).slice(0,30);for(const path of found){const b=document.createElement("button");b.textContent=nodes.get(path).name+" — "+path;b.title=path;b.addEventListener("click",()=>selectNode(path));box.appendChild(b)}if(!found.length)box.textContent="Nenhuma unit encontrada"}');
    Html.Add('function render(){const filter=document.getElementById("dprOnly").checked;const term=document.getElementById("search").value.toLowerCase();let visible,routeEdges=[];');
    Html.Add('if(mode==="neighbors"){visible=new Set([selectedPath]);for(const e of out.get(selectedPath)||[])visible.add(e.to);for(const e of incoming.get(selectedPath)||[])visible.add(e.from)}');
    Html.Add('else if(mode==="route"){routeEdges=traceResult?.edges||[];visible=new Set([selectedPath]);for(const e of routeEdges){visible.add(e.from);visible.add(e.to)}}');
    Html.Add('else if(mode==="dprRoutes"){visible=new Set([...toDpr].filter(x=>nodes.has(x)))}');
    Html.Add('else if(mode==="explore"){visible=new Set(expanded);for(const path of expanded)for(const e of out.get(path)||[])visible.add(e.to)}');
    Html.Add('else visible=filter?new Set([...toDpr].filter(x=>nodes.has(x))):new Set(nodes.keys());');
    Html.Add('const root=["all","explore","dprRoutes"].includes(mode)?target:selectedPath;const levels=new Map([[root,0]]),queue=[root];for(let i=0;i<queue.length;i++)for(const e of out.get(queue[i])||[])if(visible.has(e.to)&&!levels.has(e.to)){levels.set(e.to,levels.get(queue[i])+1);queue.push(e.to)}');
    Html.Add('for(const x of visible)if(!levels.has(x))levels.set(x,0);');
    Html.Add('const groups=new Map();for(const x of visible){const level=levels.get(x);if(!groups.has(level))groups.set(level,[]);groups.get(level).push(x)}');
    Html.Add('for(const group of groups.values())group.sort((a,b)=>nodes.get(a).name.localeCompare(nodes.get(b).name));');
    Html.Add('const maxLevel=Math.max(0,...groups.keys()),maxRows=Math.max(1,...[...groups.values()].map(x=>x.length));');
    Html.Add('const width=(maxLevel+1)*240+80,height=maxRows*58+70;svg.setAttribute("viewBox",`0 0 ${width} ${height}`);svg.setAttribute("width",width);svg.setAttribute("height",height);svg.replaceChildren();');
    Html.Add('const pos=new Map();for(const [level,group] of groups)group.forEach((x,i)=>pos.set(x,{x:30+level*240,y:30+i*58}));currentPos=pos;');
    Html.Add('const defs=el("defs",{},svg),marker=el("marker",{id:"arrow",viewBox:"0 0 10 10",refX:9,refY:5,markerWidth:7,markerHeight:7,orient:"auto"},defs);el("path",{d:"M 0 0 L 10 5 L 0 10 z",fill:"#59636e"},marker);');
    Html.Add('for(const e of edges){if(!pos.has(e.from)||!pos.has(e.to)||(mode==="route"&&!routeEdges.includes(e))||(mode==="dprRoutes"&&!dprEdges.has(e))||(mode==="explore"&&!expanded.has(e.from))||(mode==="neighbors"&&e.from!==selectedPath&&e.to!==selectedPath))continue;const a=pos.get(e.from),b=pos.get(e.to),onTrace=traceResult?.edges.includes(e);const line=el("path",{d:`M ${a.x+175} ${a.y+18} C ${a.x+195} ${a.y+18}, ${b.x-20} ${b.y+18}, ${b.x} ${b.y+18}`,class:`edge${onTrace?" trace":""}${selected===e?" focus":""}${selected!==e&&((traceResult&&!onTrace)||(term&&!traceResult&&!(`${e.used} ${e.consumer} ${e.from} ${e.to}`.toLowerCase().includes(term))))?" muted":""}`,"marker-end":"url(#arrow)"},svg);line.addEventListener("click",()=>{selected=e;selectedPath=e.from;traceResult=trace(e.from);showTrace();showCuts();show(`${e.used} → ${e.consumer}\n${e.section}:${e.line}\nDeclaração: ${e.source}:${e.line}\nArquivo usado: ${e.from}\nConsumidor: ${e.to}`);render();center(e.from)})}');
    Html.Add('const highlighted=traceNodes();for(const [path,p] of pos){const name=nodes.get(path).name,g=el("g",{class:`node${path===target?" target":""}${path===program?" dpr":""}${highlighted.has(path)?" trace":""}${selected===path?" focus":""}${selected!==path&&((traceResult&&!highlighted.has(path))||(term&&!traceResult&&!(`${name} ${path}`.toLowerCase().includes(term))))?" muted":""}`},svg);el("rect",{x:p.x,y:p.y,width:175,height:36},g);const label=el("text",{x:p.x+9,y:p.y+23},g);label.textContent=name.length>23?name.slice(0,21)+"…":name;const title=el("title",{},g);title.textContent=`${name}\n${path}`;g.addEventListener("click",()=>selectNode(path))}');
    Html.Add('document.getElementById("status").textContent=mode==="route"?traceResult?`Cadeia isolada até ${traceResult.kind==="DPR"?"o DPR":"um arquivo do projeto"}: ${routeEdges.length} ligação(ões).`:`Sem cadeia até o projeto ou DPR.`:mode==="dprRoutes"?`Todas as rotas resolvidas até o DPR: ${visible.size} arquivo(s) e ${dprEdges.size} ligação(ões).`:mode==="explore"?`Explorando ${visible.size} arquivo(s). Clique em uma unit para expandir seus consumidores.`:mode==="neighbors"?`Ligações diretas da unit selecionada: ${Math.max(0,visible.size-1)} vizinho(s).`:`Grafo completo: ${visible.size} arquivo(s). ${traceResult?"A cadeia selecionada está em amarelo.":""}`;');
    Html.Add('}');
    Html.Add('document.getElementById("search").addEventListener("input",()=>{updateMatches();render()});document.getElementById("dprOnly").addEventListener("change",()=>{mode="all";render()});');
    Html.Add('document.getElementById("neighbors").addEventListener("click",()=>{mode="neighbors";render();center(selectedPath)});document.getElementById("route").addEventListener("click",()=>{traceResult=trace(selectedPath);showTrace();mode="route";render();center(selectedPath)});');
    Html.Add('document.getElementById("allRoutes").addEventListener("click",()=>{mode="dprRoutes";render();center(target)});');
    Html.Add('document.getElementById("reset").addEventListener("click",()=>{selected=null;selectedPath=target;traceResult=null;mode="all";document.getElementById("search").value="";document.getElementById("dprOnly").checked=false;updateMatches();show("");document.getElementById("trace").replaceChildren();showCuts();render();center(target)});showCuts();showUncertain();render();');
    Html.Add('</script></body></html>');
    TFile.WriteAllText(FileName, Html.Text, TEncoding.UTF8);
  finally
    SeenEdges.Free;
    Html.Free;
  end;
end;

end.
