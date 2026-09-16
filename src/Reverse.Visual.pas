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
  Origin: TPair<string, TSourceOrigin>;
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
    Html.Add('input,button,select{box-sizing:border-box;width:100%;padding:9px;margin:5px 0;background:#0d1117;color:#e6edf3;border:1px solid #30363d;border-radius:6px}');
    Html.Add('button{cursor:pointer}button:hover{border-color:#58a6ff}button:disabled{opacity:.45;cursor:default}label{display:block;margin:12px 0}');
    Html.Add('#matches button{text-align:left;margin:2px 0;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}');
    Html.Add('#matches{max-height:180px;overflow:auto;margin-bottom:8px}#status{color:#8b949e}');
    Html.Add('#viewport{overflow:auto;position:relative;cursor:grab}#viewport.dragging{cursor:grabbing}svg{display:block}');
    Html.Add('.edge{stroke:#59636e;stroke-width:1.4;fill:none}.edge.section-interface{stroke:#79c0ff}.edge.section-implementation{stroke:#bc8cff}.edge.section-program{stroke:#f0883e}.edge.trace{stroke:#f2cc60;stroke-width:3}.edge.remaining{stroke:#3fb950;stroke-width:3}.edge.cut{stroke:#ff7b72;stroke-width:3;stroke-dasharray:7 5}.edge.focus{stroke:#ff7b72;stroke-width:4}');
    Html.Add('.node rect{fill:#21262d;stroke:#59636e;stroke-width:1.5;rx:7}');
    Html.Add('.node text{fill:#e6edf3;font-size:12px;pointer-events:none}');
    Html.Add('.node{cursor:pointer}.node.target rect{fill:#173c2b;stroke:#3fb950}');
    Html.Add('.node.dpr rect{fill:#3b241e;stroke:#f0883e}.node.trace rect{stroke:#f2cc60;stroke-width:2.5}.node.focus rect{stroke:#ff7b72;stroke-width:3}');
    Html.Add('.node.origin-project-search-path rect{fill:#152f4a}.node.origin-global-search-path rect{fill:#30234a}.node.origin-additional-root rect{fill:#173b3b}');
    Html.Add('.muted{opacity:.16}#detail{white-space:pre-wrap;word-break:break-word;line-height:1.5;margin-top:12px}');
    Html.Add('#trace{margin-top:14px;border-top:1px solid #30363d;padding-top:10px;line-height:1.5}#trace button{text-align:left;font-size:12px;white-space:normal;word-break:break-word}');
    Html.Add('#cuts,#uncertain{margin-top:14px;border-top:1px solid #30363d;padding-top:10px;line-height:1.5}#cuts button,#uncertain button{text-align:left;font-size:12px;white-space:normal;word-break:break-word}');
    Html.Add('#simulation{margin-top:10px;line-height:1.5}#zoomControls{display:flex;gap:4px}#zoomControls button{flex:1}#copyStatus{min-height:18px}');
    Html.Add('#routePanel{margin:8px 0 14px;border-bottom:1px solid #30363d;padding-bottom:10px}#routePanel details{margin:6px 0}#routePanel summary{cursor:pointer;font-weight:600}#routePanel button{text-align:left;font-size:11px;white-space:normal;word-break:break-word}');
    Html.Add('#branchControls{display:grid;grid-template-columns:1fr 1fr;gap:4px}#branchControls button{margin:0}.edge.hover{stroke:#fff176;stroke-width:4;opacity:1}.node.hover rect{stroke:#fff176;stroke-width:3}.hover-muted{opacity:.1}');
    Html.Add('#viewControls{display:grid;grid-template-columns:1fr 1fr;gap:4px;margin-bottom:10px}#viewControls button{margin:0}');
    Html.Add('@media(max-width:750px){.layout{grid-template-columns:1fr;grid-template-rows:240px 1fr}aside{border-right:0;border-bottom:1px solid #30363d}}');
    Html.Add('</style></head><body>');
    Html.Add('<header><h1>Delphi Unit Backtrace</h1><p id="summary"></p></header>');
    Html.Add('<div class="layout"><aside>');
    Html.Add('<input id="search" type="search" placeholder="Buscar unit ou arquivo" aria-label="Buscar unit ou arquivo">');
    Html.Add('<div id="matches"></div>');
    Html.Add('<div id="viewControls"><button id="progressiveView">Visão progressiva</button><button id="reset">Grafo completo</button></div>');
    Html.Add('<div id="routePanel"></div>');
    Html.Add('<label for="sectionFilter">Seção mostrada no grafo</label><select id="sectionFilter"><option value="all">Todas</option><option value="interface">Interface</option><option value="implementation">Implementação</option><option value="program">DPR</option></select>');
    Html.Add('<label for="originFilter">Origem dos arquivos</label><select id="originFilter"><option value="all">Todas</option><option value="project">Projeto</option><option value="project-reference">Referência do projeto</option><option value="project-search-path">Search Path do projeto</option><option value="global-search-path">Search Path global</option><option value="additional-root">Raiz adicional</option></select>');
    Html.Add('<p>O filtro altera apenas a visualização; a simulação considera todas as ligações resolvidas.</p>');
    Html.Add('<label><input id="dprOnly" type="checkbox" style="width:auto"> Mostrar somente caminhos até o DPR</label>');
    Html.Add('<button id="neighbors">Ver ligações da unit selecionada</button>');
    Html.Add('<button id="route">Isolar cadeia destacada</button>');
    Html.Add('<button id="allRoutes">Mostrar todas as rotas até o DPR</button>');
    Html.Add('<button id="outsideRoutes">Mostrar usos fora do DPR</button>');
    Html.Add('<div id="branchControls"><button id="expandBranch">Expandir ramo</button><button id="collapseBranch">Recolher ramo</button><button id="expandDpr">Expandir até DPR</button><button id="expandEnd">Expandir até o final</button></div><button id="hideBranch">Ocultar ramo selecionado</button>');
    Html.Add('<div id="zoomControls"><button id="zoomOut" aria-label="Diminuir zoom">−</button><button id="zoomIn" aria-label="Aumentar zoom">+</button></div>');
    Html.Add('<button id="fitTrace">Ajustar cadeia selecionada</button><button id="fitAll">Ajustar grafo visível</button>');
    Html.Add('<p>Arraste o grafo para mover a visão.</p>');
    Html.Add('<p id="status">Selecione uma unit ou ligação para ver detalhes. A busca centraliza a unit encontrada.</p>');
    Html.Add('<div id="detail"></div><button id="copySource" disabled>Copiar arquivo:linha</button><p id="copyStatus"></p><div id="trace"></div><div id="cuts"></div><button id="cutToggle" disabled>Marcar declaração na simulação</button><button id="cutReset">Limpar simulação</button><div id="simulation"></div><div id="uncertain"></div></aside><main id="viewport"><svg id="graph"></svg></main></div>');
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
    Html.Add('const origins=new Map([');
    First := True;
    for Origin in Analysis.SourceOrigins do
    begin
      if not First then Html.Add(',');
      First := False;
      Html.Add('[' + SafeJson(Origin.Key) + ',' +
        SafeJson(SourceOriginName(Origin.Value)) + ']');
    end;
    Html.Add(']);');
    Html.Add('const routeCounts={dpr:' + Analysis.RouteCount(rdDpr).ToString +
      ',project:' + Analysis.RouteCount(rdProjectFile).ToString +
      ',library:' + Analysis.RouteCount(rdLibraryRoot).ToString +
      ',none:' + Analysis.RouteCount(rdNoConsumer).ToString +
      ',cycle:' + Analysis.RouteCount(rdCycle).ToString + '};');
    Html.Add('const svg=document.getElementById("graph"), detail=document.getElementById("detail");');
    Html.Add('const ns="http://www.w3.org/2000/svg";');
    Html.Add('function el(tag,attrs,parent){const x=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))x.setAttribute(k,v);parent.appendChild(x);return x}');
    Html.Add('const nodes=new Map([[target,{name:targetName}]]);');
    Html.Add('for(const e of edges){if(!nodes.has(e.from))nodes.set(e.from,{name:e.used});if(!nodes.has(e.to))nodes.set(e.to,{name:e.consumer})}');
    Html.Add('const reachableNames=new Set([...nodes.values()].map(x=>x.name.toLowerCase()));');
    Html.Add('const out=new Map(),incoming=new Map();for(const e of edges){if(!out.has(e.from))out.set(e.from,[]);out.get(e.from).push(e);if(!incoming.has(e.to))incoming.set(e.to,[]);incoming.get(e.to).push(e)}');
    Html.Add('function originOf(path){return origins.get(path.toLowerCase())||"unknown"}function isProjectOrigin(path){return ["project","project-reference"].includes(originOf(path))}');
    Html.Add('const toDpr=new Set([program]);const q=[program];for(let i=0;i<q.length;i++)for(const e of incoming.get(q[i])||[])if(!toDpr.has(e.from)){toDpr.add(e.from);q.push(e.from)}');
    Html.Add('const dprEdges=new Set(edges.filter(e=>toDpr.has(e.from)&&toDpr.has(e.to)));');
    Html.Add('const nonDprEdges=new Set(edges.filter(e=>!toDpr.has(e.to))),outsideNodes=new Set([target]);for(const e of nonDprEdges){outsideNodes.add(e.from);outsideNodes.add(e.to)}');
    Html.Add('function endpointKind(path){if(path===program)return "DPR";if((out.get(path)||[]).length)return "CYCLE";if(path===target||originOf(path)==="unknown")return "NO_CONSUMER";return isProjectOrigin(path)?"PROJECT":"LIBRARY"}');
    Html.Add('function enumerateRoutes(limit=10000){const result=[],frames=[{node:target,index:0}],pathNodes=[target],pathEdges=[];let limited=false;const finish=(kind,endpoint,extra=null)=>{const routeEdges=extra?[...pathEdges,extra]:pathEdges.slice();result.push({kind,endpoint,edges:routeEdges});if(result.length>=limit)limited=true};');
    Html.Add('while(frames.length&&!limited){const frame=frames[frames.length-1],nextEdges=out.get(frame.node)||[];if(frame.node===program||!nextEdges.length){finish(endpointKind(frame.node),frame.node);frames.pop();pathNodes.pop();if(pathEdges.length>=frames.length)pathEdges.pop();continue}if(frame.index>=nextEdges.length){frames.pop();pathNodes.pop();if(pathEdges.length>=frames.length)pathEdges.pop();continue}const edge=nextEdges[frame.index++];if(pathNodes.includes(edge.to)){finish("CYCLE",edge.to,edge);continue}frames.push({node:edge.to,index:0});pathNodes.push(edge.to);pathEdges.push(edge)}return {routes:result,limited}}');
    Html.Add('const routeIndex=enumerateRoutes();function routeLabel(route){const names=[targetName,...route.edges.map(e=>e.consumer)];return `${names.join(" → ")} [${route.kind}]`}');
    Html.Add('document.getElementById("summary").textContent=`${targetName} → ${programName} | ${nodes.size} arquivos | ${edges.length} ligações | Rotas: ${routeCounts.dpr} DPR, ${routeCounts.project} projeto, ${routeCounts.library} biblioteca, ${routeCounts.none} sem consumidor, ${routeCounts.cycle} ciclos | ${unresolved+ambiguous+failed+fallback+Number(pathFallback)?`Resultado parcial: ${unresolved} não resolvidas, ${ambiguous} ambíguas, ${failed} falhas, ${fallback} fallbacks${pathFallback?", caminhos MSBuild por fallback":""}`:"Análise completa"}`;');
    Html.Add('let selected=null,selectedPath=target,mode="explore",expanded=new Set([target]),hidden=new Set(),currentPos=new Map(),traceResult=null,traceStep=0,cutEdges=new Set(),remainingRoute=null,zoom=1,baseWidth=0,baseHeight=0,dragState=null;function show(text){detail.textContent=text}');
    Html.Add('function directCuts(path){return (out.get(path)||[]).filter(e=>toDpr.has(e.to))}');
    Html.Add('function showCuts(){const panel=document.getElementById("cuts");panel.replaceChildren();const heading=document.createElement("strong");heading.textContent="Declarações diretas a revisar para cortar todas as rotas até o DPR";panel.appendChild(heading);const cuts=directCuts(selectedPath);const note=document.createElement("p");note.textContent=cuts.length?`${cuts.length} declaração(ões) direta(s). Remover apenas uma pode deixar outras rotas. Confira se os símbolos usados permitem alterar cada uses.`:"Nenhuma declaração direta desta unit alcança o DPR no grafo resolvido.";panel.appendChild(note);for(const e of cuts){const b=document.createElement("button");b.textContent=`${e.consumer} usa ${e.used} | ${e.source}:${e.line} (${e.section})`;b.addEventListener("click",()=>{selected=e;show(`${e.used} → ${e.consumer}\nDeclaração: ${e.source}:${e.line}\nArquivo usado: ${e.from}\nConsumidor: ${e.to}`);render();center(e.to)});panel.appendChild(b)}}');
    Html.Add('function showUncertain(){const panel=document.getElementById("uncertain");panel.replaceChildren();if(!uncertain.length&&!failed&&!fallback&&!pathFallback)return;const heading=document.createElement("strong");heading.textContent="Ligações incertas e análise parcial";panel.appendChild(heading);const note=document.createElement("p");note.textContent="Referências incertas não foram acrescentadas ao grafo. Falhas, fallback do parser ou dos caminhos também podem omitir rotas. Confira analysis.log antes de alterar uses.";panel.appendChild(note);');
    Html.Add('const relevant=uncertain.filter(x=>reachableNames.has(x.used.toLowerCase())||nodes.has(x.to));for(const x of relevant.slice(0,100)){const b=document.createElement("button");b.textContent=`${x.consumer} usa ${x.used} | ${x.reason} | ${x.source}:${x.line}`;b.addEventListener("click",()=>show(`${x.reason}\n${x.consumer} usa ${x.used}\n${x.source}:${x.line}`));panel.appendChild(b)}const rest=uncertain.length-relevant.length;if(rest||relevant.length>100){const p=document.createElement("p");p.textContent=`${relevant.length>100?`Mostrando 100 de ${relevant.length} referências potencialmente ligadas ao alvo. `:""}${rest?`${rest} outras referências incertas estão no log.`:""}`;panel.appendChild(p)}}');
    Html.Add('function inProject(path){if(!projectRoot)return false;const root=projectRoot.toLowerCase().replace(/[\\/]+$/,"");const file=path.toLowerCase();return file===root||file.startsWith(root+"/")||file.startsWith(root+"\\")}');
    Html.Add('function shortest(start,accept,excluded=null){const queue=[start],previous=new Map([[start,null]]),end=queue.find(accept);let found=end;for(let i=0;i<queue.length&&!found;i++){const x=queue[i];for(const e of out.get(x)||[]){if(excluded?.has(e))continue;if(!previous.has(e.to)){previous.set(e.to,e);queue.push(e.to);if(accept(e.to)){found=e.to;break}}}}if(!found)return null;const path=[];for(let x=found;x!==start;){const e=previous.get(x);path.unshift(e);x=e.from}return {edges:path,endpoint:found}}');
    Html.Add('function trace(start){const dpr=shortest(start,x=>x===program);if(dpr)return {...dpr,kind:"DPR"};const local=shortest(start,x=>x!==start&&isProjectOrigin(x));if(local)return {...local,kind:"PROJECT"};const terminal=shortest(start,x=>!(out.get(x)||[]).length);if(!terminal)return null;return {...terminal,kind:isProjectOrigin(terminal.endpoint)?"PROJECT":originOf(terminal.endpoint)==="unknown"?"NO_CONSUMER":"LIBRARY"}}');
    Html.Add('function traceNodes(){const result=new Set();if(traceResult){result.add(selectedPath);for(const e of traceResult.edges){result.add(e.from);result.add(e.to)}}return result}');
    Html.Add('function showTrace(){const panel=document.getElementById("trace");panel.replaceChildren();if(!traceResult){panel.textContent="Nenhuma cadeia até o DPR ou um arquivo do projeto foi encontrada.";return}');
    Html.Add('const heading=document.createElement("strong"),labels={DPR:"Cadeia até o DPR",PROJECT:"Cadeia até um arquivo do projeto",LIBRARY:"Cadeia exclusiva de biblioteca",NO_CONSUMER:"Cadeia sem consumidor conhecido"};heading.textContent=labels[traceResult.kind]||"Cadeia de dependência";panel.appendChild(heading);');
    Html.Add('const endpoint=document.createElement("p");endpoint.textContent=`Destino: ${nodes.get(traceResult.endpoint)?.name||traceResult.endpoint} (${traceResult.edges.length} ligação(ões))`;panel.appendChild(endpoint);');
    Html.Add('if(traceResult.edges.length){traceStep=Math.min(traceStep,traceResult.edges.length-1);const count=document.createElement("p");count.textContent=`Passo ${traceStep+1} de ${traceResult.edges.length}`;panel.appendChild(count);const controls=document.createElement("div");controls.id="traceControls";controls.style.display="flex";controls.style.gap="4px";const prev=document.createElement("button");prev.textContent="← Anterior";prev.disabled=traceStep===0;prev.addEventListener("click",()=>gotoTraceStep(traceStep-1));controls.appendChild(prev);');
    Html.Add('const next=document.createElement("button");next.textContent="Próximo →";next.disabled=traceStep===traceResult.edges.length-1;next.addEventListener("click",()=>gotoTraceStep(traceStep+1));controls.appendChild(next);panel.appendChild(controls);const e=traceResult.edges[traceStep],step=document.createElement("button");step.textContent=`${e.used} → ${e.consumer} | ${e.section}:${e.line} | ${e.source}`;step.addEventListener("click",()=>gotoTraceStep(traceStep));panel.appendChild(step)}');
    Html.Add('const direct=new Set((out.get(selectedPath)||[]).map(e=>e.to)).size,note=document.createElement("p");note.textContent=direct?`A primeira ligação mostra um consumidor direto. Este arquivo tem ${direct} consumidor(es) direto(s); revise todos antes de remover a dependência.`:"Este arquivo já é o destino da cadeia.";panel.appendChild(note)}');
    Html.Add('function selectRoute(route){selected=target;selectedPath=target;traceStep=0;traceResult={edges:route.edges,endpoint:route.endpoint,kind:route.kind};mode="route";showTrace();showCuts();render();center(target)}');
    Html.Add('function showRouteList(){const panel=document.getElementById("routePanel");panel.replaceChildren();const title=document.createElement("strong");title.textContent="Rotas encontradas";panel.appendChild(title);const labels={DPR:"Até o DPR",PROJECT:"Até arquivo do projeto",LIBRARY:"Somente bibliotecas",NO_CONSUMER:"Sem consumidor",CYCLE:"Ciclos"};');
    Html.Add('for(const kind of ["DPR","PROJECT","LIBRARY","NO_CONSUMER","CYCLE"]){const list=routeIndex.routes.filter(x=>x.kind===kind),details=document.createElement("details"),summary=document.createElement("summary");summary.textContent=`${labels[kind]} (${list.length})`;details.open=kind==="DPR"&&list.length<=20;details.appendChild(summary);for(const route of list.slice(0,100)){const b=document.createElement("button");b.textContent=routeLabel(route);b.addEventListener("click",()=>selectRoute(route));details.appendChild(b)}if(list.length>100){const note=document.createElement("p");note.textContent=`Mostrando 100 de ${list.length} rotas.`;details.appendChild(note)}panel.appendChild(details)}if(routeIndex.limited){const note=document.createElement("p");note.textContent="Lista limitada a 10.000 rotas; o grafo preserva todas as ligações.";panel.appendChild(note)}}');
    Html.Add('function gotoTraceStep(index){if(!traceResult?.edges.length)return;traceStep=Math.max(0,Math.min(index,traceResult.edges.length-1));const e=traceResult.edges[traceStep];selected=e;if(mode==="explore")for(let i=0;i<=traceStep;i++)expanded.add(traceResult.edges[i].from);show(`${e.used} → ${e.consumer}\nDeclaração: ${e.source}:${e.line}\nArquivo usado: ${e.from}\nConsumidor: ${e.to}`);showTrace();render();center(e.to)}');
    Html.Add('function selectedEdge(){return selected&&typeof selected==="object"?selected:null}function updateEdgeActions(){const e=selectedEdge(),copy=document.getElementById("copySource"),toggle=document.getElementById("cutToggle");copy.disabled=!e;toggle.disabled=!e;toggle.textContent=e&&cutEdges.has(e)?"Desmarcar declaração simulada":"Marcar declaração na simulação"}');
    Html.Add('function showSimulation(){remainingRoute=shortest(target,x=>x===program,cutEdges);const panel=document.getElementById("simulation");panel.replaceChildren();const heading=document.createElement("strong");heading.textContent="Simulação de corte (sem alterar arquivos)";panel.appendChild(heading);const result=document.createElement("p");result.textContent=remainingRoute?`Ainda há caminho até o DPR: ${remainingRoute.edges.length} ligação(ões) na cadeia mais curta.`:"Sem caminho até o DPR no grafo resolvido após os cortes marcados.";panel.appendChild(result);');
    Html.Add('if(unresolved+ambiguous+failed+fallback+Number(pathFallback)){const caution=document.createElement("p");caution.textContent="Resultado parcial: rotas ausentes podem existir. Confira analysis.log.";panel.appendChild(caution)}const count=document.createElement("p");count.textContent=`${cutEdges.size} declaração(ões) marcada(s).`;panel.appendChild(count);for(const e of cutEdges){const b=document.createElement("button");b.textContent=`Desmarcar: ${e.consumer} usa ${e.used} | ${e.source}:${e.line}`;b.addEventListener("click",()=>{cutEdges.delete(e);showSimulation();render()});panel.appendChild(b)}updateEdgeActions()}');
    Html.Add('function toggleCut(){const e=selectedEdge();if(!e)return;if(cutEdges.has(e))cutEdges.delete(e);else cutEdges.add(e);showSimulation();render()}');
    Html.Add('async function copySelectedSource(){const e=selectedEdge();if(!e)return;const value=`${e.source}:${e.line}`;let copied=false;try{if(typeof navigator!=="undefined"&&navigator.clipboard?.writeText){await navigator.clipboard.writeText(value);copied=true}else{const input=document.createElement("textarea");input.value=value;document.body.appendChild(input);input.select();copied=!!document.execCommand("copy");input.remove()}}catch(_error){}document.getElementById("copyStatus").textContent=copied?`Copiado: ${value}`:`Não foi possível copiar. Use: ${value}`}');
    Html.Add('function center(path){const p=currentPos.get(path),view=document.getElementById("viewport");if(p){view.scrollLeft=Math.max(0,(p.x+90)*zoom-view.clientWidth/2);view.scrollTop=Math.max(0,(p.y+18)*zoom-view.clientHeight/2)}}');
    Html.Add('function branchNodes(start){const found=new Set([start]),queue=[start];for(let i=0;i<queue.length;i++)for(const e of out.get(queue[i])||[])if(!found.has(e.to)){found.add(e.to);queue.push(e.to)}return found}');
    Html.Add('function expandBranch(){mode="explore";hidden.delete(selectedPath);expanded.add(selectedPath);render();center(selectedPath)}function collapseBranch(){mode="explore";expanded.delete(selectedPath);traceResult=null;render();center(selectedPath)}');
    Html.Add('function expandToDpr(){const route=shortest(selectedPath,x=>x===program);if(!route)return;mode="explore";for(const e of route.edges){expanded.add(e.from);hidden.delete(e.from);hidden.delete(e.to)}traceResult={...route,kind:"DPR"};showTrace();render();center(selectedPath)}');
    Html.Add('function expandToEnd(){mode="explore";for(const path of branchNodes(selectedPath)){expanded.add(path);hidden.delete(path)}render();center(selectedPath)}function hideSelectedBranch(){mode="explore";for(const path of branchNodes(selectedPath))if(path!==target)hidden.add(path);traceResult=null;render();center(target)}');
    Html.Add('function applyZoom(){if(!baseWidth||!baseHeight)return;svg.setAttribute("width",Math.max(1,Math.round(baseWidth*zoom)));svg.setAttribute("height",Math.max(1,Math.round(baseHeight*zoom)))}function setZoom(value){zoom=Math.max(.001,Math.min(4,value));applyZoom();center(selectedPath)}');
    Html.Add('function fitAll(){if(!baseWidth||!baseHeight)return;const view=document.getElementById("viewport");zoom=Math.max(.001,Math.min(4,.95*Math.min(view.clientWidth/baseWidth,view.clientHeight/baseHeight)));applyZoom();view.scrollLeft=0;view.scrollTop=0}function fitTrace(){if(!traceResult?.edges.length){setZoom(1);return}mode="route";render();fitAll()}');
    Html.Add('const view=document.getElementById("viewport");view.addEventListener("pointerdown",ev=>{if(ev.target?.closest?.(".node,.edge"))return;dragState={x:ev.clientX,y:ev.clientY,left:view.scrollLeft,top:view.scrollTop,id:ev.pointerId};view.setPointerCapture?.(ev.pointerId)});view.addEventListener("pointermove",ev=>{if(!dragState)return;const dx=ev.clientX-dragState.x,dy=ev.clientY-dragState.y;if(Math.abs(dx)+Math.abs(dy)>4)view.classList.add("dragging");view.scrollLeft=dragState.left-dx;view.scrollTop=dragState.top-dy});function endDrag(){if(dragState){view.releasePointerCapture?.(dragState.id);dragState=null}view.classList.remove("dragging")}view.addEventListener("pointerup",endDrag);view.addEventListener("pointercancel",endDrag)');
    Html.Add('function selectNode(path){selected=path;selectedPath=path;traceStep=0;traceResult=trace(path);if(mode==="explore")expanded.add(path);if(!toDpr.has(path))document.getElementById("dprOnly").checked=false;const name=nodes.get(path).name;show(`${name}\n${path}\nUsada por ${(out.get(path)||[]).length} declaração(ões)\nUsa ${(incoming.get(path)||[]).length} declaração(ões)${toDpr.has(path)?"\nTem caminho até o DPR":""}`);showTrace();showCuts();render();center(path)}');
    Html.Add('function updateMatches(){const box=document.getElementById("matches"),term=document.getElementById("search").value.trim().toLowerCase();box.replaceChildren();if(!term)return;const found=[...nodes.keys()].filter(x=>`${nodes.get(x).name} ${x}`.toLowerCase().includes(term)).slice(0,30);for(const path of found){const b=document.createElement("button");b.textContent=nodes.get(path).name+" — "+path;b.title=path;b.addEventListener("click",()=>selectNode(path));box.appendChild(b)}if(!found.length)box.textContent="Nenhuma unit encontrada"}');
    Html.Add('function destinationRank(path){if(path===program)return 0;if(isProjectOrigin(path))return 1;if(originOf(path)!=="unknown")return 2;return 3}function average(values,fallback){return values.length?values.reduce((a,b)=>a+b,0)/values.length:fallback}');
    Html.Add('function reduceCrossings(groups,levels,visible){const ordered=[...groups.keys()].sort((a,b)=>a-b);for(let pass=0;pass<4;pass++){let positions=new Map();for(const group of groups.values())group.forEach((x,i)=>positions.set(x,i));for(const level of ordered.slice(1)){const group=groups.get(level);group.sort((a,b)=>average((incoming.get(a)||[]).filter(e=>visible.has(e.from)).map(e=>positions.get(e.from)??0),positions.get(a))-average((incoming.get(b)||[]).filter(e=>visible.has(e.from)).map(e=>positions.get(e.from)??0),positions.get(b)));group.forEach((x,i)=>positions.set(x,i))}');
    Html.Add('positions=new Map();for(const group of groups.values())group.forEach((x,i)=>positions.set(x,i));for(const level of ordered.slice(0,-1).reverse()){const group=groups.get(level);group.sort((a,b)=>average((out.get(a)||[]).filter(e=>visible.has(e.to)).map(e=>positions.get(e.to)??0),positions.get(a))-average((out.get(b)||[]).filter(e=>visible.has(e.to)).map(e=>positions.get(e.to)??0),positions.get(b)));group.forEach((x,i)=>positions.set(x,i))}}}');
    Html.Add('function clearHover(){for(const x of svg.querySelectorAll(".edge,.node")){x.classList.remove("hover");x.classList.remove("hover-muted")}}function hoverRoute(path){clearHover();const route=trace(path);if(!route)return;const routeEdges=new Set(route.edges),routeNodes=new Set([path]);for(const e of route.edges){routeNodes.add(e.from);routeNodes.add(e.to)}for(const x of svg.querySelectorAll(".edge")){if(routeEdges.has(x._edge))x.classList.add("hover");else x.classList.add("hover-muted")}for(const x of svg.querySelectorAll(".node")){if(routeNodes.has(x._path))x.classList.add("hover");else x.classList.add("hover-muted")}}');
    Html.Add('function render(){const filter=document.getElementById("dprOnly").checked,section=document.getElementById("sectionFilter").value,originFilter=document.getElementById("originFilter").value;const term=document.getElementById("search").value.toLowerCase(),highlighted=traceNodes(),traceEdges=new Set(traceResult?.edges||[]);');
    Html.Add('if(mode==="dprRoutes")for(const e of dprEdges){highlighted.add(e.from);highlighted.add(e.to)}else if(mode==="outsideRoutes")for(const e of nonDprEdges){highlighted.add(e.from);highlighted.add(e.to)}let visible,routeEdges=[];');
    Html.Add('if(mode==="neighbors"){visible=new Set([selectedPath]);for(const e of out.get(selectedPath)||[])visible.add(e.to);for(const e of incoming.get(selectedPath)||[])visible.add(e.from)}');
    Html.Add('else if(mode==="route"){routeEdges=traceResult?.edges||[];visible=new Set([selectedPath]);for(const e of routeEdges){visible.add(e.from);visible.add(e.to)}}');
    Html.Add('else if(mode==="dprRoutes"){visible=new Set([...toDpr].filter(x=>nodes.has(x)))}');
    Html.Add('else if(mode==="outsideRoutes"){visible=new Set([...outsideNodes].filter(x=>nodes.has(x)))}');
    Html.Add('else if(mode==="explore"){visible=new Set(expanded);for(const path of expanded)for(const e of out.get(path)||[])visible.add(e.to);for(const path of highlighted)visible.add(path)}');
    Html.Add('else visible=filter?new Set([...toDpr].filter(x=>nodes.has(x))):new Set(nodes.keys());');
    Html.Add('if(originFilter!=="all")visible=new Set([...visible].filter(x=>x===target||originOf(x)===originFilter));visible=new Set([...visible].filter(x=>x===target||!hidden.has(x)));visible.add(target);');
    Html.Add('const root=["all","explore","dprRoutes","outsideRoutes"].includes(mode)?target:selectedPath;const levels=new Map([[root,0]]),queue=[root];for(let i=0;i<queue.length;i++)for(const e of out.get(queue[i])||[])if(visible.has(e.to)&&!levels.has(e.to)){levels.set(e.to,levels.get(queue[i])+1);queue.push(e.to)}');
    Html.Add('for(const x of visible)if(!levels.has(x))levels.set(x,0);');
    Html.Add('const nonTerminal=[...visible].filter(x=>x!==program&&(out.get(x)||[]).some(e=>visible.has(e.to))),destinationLevel=Math.max(0,...nonTerminal.map(x=>levels.get(x)))+1;for(const x of visible)if(x!==target&&(x===program||!(out.get(x)||[]).some(e=>visible.has(e.to))))levels.set(x,destinationLevel);');
    Html.Add('const groups=new Map();for(const x of visible){const level=levels.get(x);if(!groups.has(level))groups.set(level,[]);groups.get(level).push(x)}');
    Html.Add('for(const [level,group] of groups){group.sort((a,b)=>level===destinationLevel?destinationRank(a)-destinationRank(b)||nodes.get(a).name.localeCompare(nodes.get(b).name):nodes.get(a).name.localeCompare(nodes.get(b).name))}reduceCrossings(groups,levels,visible);');
    Html.Add('const maxLevel=Math.max(0,...groups.keys()),maxRows=Math.max(1,...[...groups.values()].map(x=>x.length));');
    Html.Add('baseWidth=(maxLevel+1)*240+80;baseHeight=maxRows*58+70;svg.setAttribute("viewBox",`0 0 ${baseWidth} ${baseHeight}`);applyZoom();svg.replaceChildren();');
    Html.Add('const pos=new Map();for(const [level,group] of groups)group.forEach((x,i)=>pos.set(x,{x:30+level*240,y:30+i*58}));currentPos=pos;');
    Html.Add('const defs=el("defs",{},svg),marker=el("marker",{id:"arrow",viewBox:"0 0 10 10",refX:9,refY:5,markerWidth:7,markerHeight:7,orient:"auto"},defs);el("path",{d:"M 0 0 L 10 5 L 0 10 z",fill:"#59636e"},marker);');
    Html.Add('for(const e of edges){if(!pos.has(e.from)||!pos.has(e.to)||(section!=="all"&&e.section!==section)||(mode==="route"&&!routeEdges.includes(e))||(mode==="dprRoutes"&&!dprEdges.has(e))||(mode==="outsideRoutes"&&!nonDprEdges.has(e))||(mode==="explore"&&!expanded.has(e.from)&&!traceEdges.has(e))||(mode==="neighbors"&&e.from!==selectedPath&&e.to!==selectedPath))continue;');
    Html.Add('const a=pos.get(e.from),b=pos.get(e.to),onTrace=traceEdges.has(e)||(mode==="dprRoutes"&&dprEdges.has(e))||(mode==="outsideRoutes"&&nonDprEdges.has(e)),isCut=cutEdges.has(e),onRemaining=cutEdges.size&&remainingRoute?.edges.includes(e),classes=["edge",`section-${e.section}`];if(isCut)classes.push("cut");else if(onRemaining)classes.push("remaining");else if(onTrace)classes.push("trace");if(selected===e)classes.push("focus");if(!isCut&&selected!==e&&((traceResult&&!onTrace&&!onRemaining)||(term&&!traceResult&&!(`${e.used} ${e.consumer} ${e.from} ${e.to}`.toLowerCase().includes(term)))))classes.push("muted");');
    Html.Add('const line=el("path",{d:`M ${a.x+175} ${a.y+18} C ${a.x+195} ${a.y+18}, ${b.x-20} ${b.y+18}, ${b.x} ${b.y+18}`,class:classes.join(" "),"marker-end":"url(#arrow)"},svg);line._edge=e;const title=el("title",{},line);title.textContent=`${e.used} → ${e.consumer} | ${e.section} | ${e.source}:${e.line}`;line.addEventListener("mouseenter",()=>hoverRoute(e.from));line.addEventListener("mouseleave",clearHover);line.addEventListener("click",()=>{selected=e;selectedPath=e.from;traceStep=0;traceResult=trace(e.from);showTrace();showCuts();show(`${e.used} → ${e.consumer}\n${e.section}:${e.line}\nDeclaração: ${e.source}:${e.line}\nArquivo usado: ${e.from}\nConsumidor: ${e.to}`);render();center(e.from)})}');
    Html.Add('for(const [path,p] of pos){const name=nodes.get(path).name,g=el("g",{class:`node origin-${originOf(path)}${path===target?" target":""}${path===program?" dpr":""}${highlighted.has(path)?" trace":""}${selected===path?" focus":""}${selected!==path&&((traceResult&&!highlighted.has(path))||(term&&!traceResult&&!(`${name} ${path}`.toLowerCase().includes(term))))?" muted":""}`},svg);g._path=path;el("rect",{x:p.x,y:p.y,width:175,height:36},g);const label=el("text",{x:p.x+9,y:p.y+23},g);label.textContent=name.length>23?name.slice(0,21)+"…":name;const title=el("title",{},g);title.textContent=`${name}\n${path}\nOrigem: ${originOf(path)}`;g.addEventListener("mouseenter",()=>hoverRoute(path));g.addEventListener("mouseleave",clearHover);g.addEventListener("click",()=>selectNode(path));g.addEventListener("dblclick",()=>{selectNode(path);mode="route";render();center(path)})}');
    Html.Add('let status=mode==="route"?(traceResult?`Cadeia isolada (${traceResult.kind}): ${routeEdges.length} ligação(ões).`:`Sem cadeia conhecida.`):mode==="dprRoutes"?`Rotas até o DPR: ${visible.size} arquivo(s), ${dprEdges.size} ligação(ões).`:mode==="outsideRoutes"?`Usos fora do DPR: ${visible.size} arquivo(s), ${nonDprEdges.size} ligação(ões).`:mode==="explore"?`Explorando ${visible.size} arquivo(s). Clique em uma unit para expandir seus consumidores.`:mode==="neighbors"?`Ligações diretas: ${Math.max(0,visible.size-1)} vizinho(s).`:`Todas as rotas: ${visible.size} arquivo(s).`;');
    Html.Add('if(section!=="all")status+=` Seção: ${section}.`;if(originFilter!=="all")status+=` Origem: ${originFilter}.`;document.getElementById("status").textContent=status;updateEdgeActions();');
    Html.Add('}');
    Html.Add('document.getElementById("search").addEventListener("input",()=>{updateMatches();render()});document.getElementById("dprOnly").addEventListener("change",()=>{mode="all";render()});document.getElementById("sectionFilter").addEventListener("change",render);document.getElementById("originFilter").addEventListener("change",render);');
    Html.Add('document.getElementById("neighbors").addEventListener("click",()=>{mode="neighbors";render();center(selectedPath)});document.getElementById("route").addEventListener("click",()=>{traceStep=0;traceResult=trace(selectedPath);showTrace();mode="route";render();center(selectedPath)});');
    Html.Add('document.getElementById("allRoutes").addEventListener("click",()=>{selected=null;selectedPath=target;traceResult=null;traceStep=0;mode="dprRoutes";document.getElementById("trace").replaceChildren();show("");showCuts();render();center(target)});');
    Html.Add('document.getElementById("outsideRoutes").addEventListener("click",()=>{selected=null;selectedPath=target;traceResult=null;traceStep=0;mode="outsideRoutes";document.getElementById("trace").replaceChildren();show("");showCuts();render();center(target)});');
    Html.Add('document.getElementById("expandBranch").addEventListener("click",expandBranch);document.getElementById("collapseBranch").addEventListener("click",collapseBranch);document.getElementById("expandDpr").addEventListener("click",expandToDpr);document.getElementById("expandEnd").addEventListener("click",expandToEnd);document.getElementById("hideBranch").addEventListener("click",hideSelectedBranch);');
    Html.Add('document.getElementById("zoomIn").addEventListener("click",()=>setZoom(zoom*1.25));document.getElementById("zoomOut").addEventListener("click",()=>setZoom(zoom/1.25));document.getElementById("fitTrace").addEventListener("click",fitTrace);document.getElementById("fitAll").addEventListener("click",fitAll);');
    Html.Add('document.getElementById("cutToggle").addEventListener("click",toggleCut);document.getElementById("cutReset").addEventListener("click",()=>{cutEdges.clear();showSimulation();render()});document.getElementById("copySource").addEventListener("click",copySelectedSource);');
    Html.Add('document.getElementById("progressiveView").addEventListener("click",()=>{selected=null;selectedPath=target;traceResult=null;traceStep=0;mode="explore";expanded=new Set([target]);hidden.clear();show("");document.getElementById("trace").replaceChildren();showCuts();render();center(target)});');
    Html.Add('document.getElementById("reset").addEventListener("click",()=>{selected=null;selectedPath=target;traceResult=null;traceStep=0;mode="all";expanded=new Set([target]);hidden.clear();document.getElementById("search").value="";document.getElementById("dprOnly").checked=false;document.getElementById("sectionFilter").value="all";document.getElementById("originFilter").value="all";updateMatches();show("");document.getElementById("trace").replaceChildren();showCuts();render();center(target)});showRouteList();showCuts();showUncertain();showSimulation();render();');
    Html.Add('</script></body></html>');
    TFile.WriteAllText(FileName, Html.Text, TEncoding.UTF8);
  finally
    SeenEdges.Free;
    Html.Free;
  end;
end;

end.
