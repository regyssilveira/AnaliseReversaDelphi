// SPDX-License-Identifier: Apache-2.0

unit Reverse.ProjectMapVisual;


interface

uses Reverse.Analysis;

type
  TProjectMapVisualWriter = class
  public
    class procedure WriteHtml(const Analysis: TAnalysisResult;
      const FileName: string);
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections, Reverse.Domain;

function SafeJson(const Value: string): string;
var
  Json: TJSONString;
begin
  Json := TJSONString.Create(Value);
  try
    Result := Json.ToJSON.Replace('<', '\u003c').Replace('>', '\u003e')
      .Replace('&', '\u0026');
  finally
    Json.Free;
  end;
end;

function FolderOf(const FileName, ProjectRoot: string): string;
var
  Directory, Root: string;
begin
  Directory := ExcludeTrailingPathDelimiter(ExtractFilePath(FileName));
  Root := ExcludeTrailingPathDelimiter(ProjectRoot);
  if SameText(Directory, Root) then Exit('(raiz do projeto)');
  if Directory.StartsWith(IncludeTrailingPathDelimiter(Root), True) then
    Exit(ExtractRelativePath(IncludeTrailingPathDelimiter(Root),
      IncludeTrailingPathDelimiter(Directory)).TrimRight(['\', '/']));
  Result := Directory;
end;

class procedure TProjectMapVisualWriter.WriteHtml(
  const Analysis: TAnalysisResult; const FileName: string);
var
  Html: TStringList;
  Files: TDictionary<string, string>;
  Edge: TDependency;
  Pair: TPair<string, string>;
  Origin: TSourceOrigin;
  First: Boolean;
  procedure AddFile(const Path, Name: string);
  begin
    if Path <> '' then Files.AddOrSetValue(Key(Path), Name);
  end;
begin
  Html := TStringList.Create;
  Files := TDictionary<string, string>.Create;
  try
    AddFile(Analysis.ProgramFile, Analysis.ProgramName);
    for Edge in Analysis.Reachable do
    begin
      AddFile(Edge.ConsumerPath, Edge.Consumer);
      AddFile(Edge.UsedPath, Edge.UsedName);
    end;
    Html.Add('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">');
    Html.Add('<meta name="viewport" content="width=device-width,initial-scale=1">');
    Html.Add('<title>Delphi Unit Backtrace — mapa do projeto</title><style>');
    Html.Add('body{margin:0;font:14px system-ui,sans-serif;color:#e6edf3;background:#0d1117}header{padding:14px 20px;background:#161b22;border-bottom:1px solid #30363d}h1{font-size:20px;margin:0 0 6px}p{margin:4px 0;color:#8b949e}.layout{display:grid;grid-template-columns:300px 1fr;height:calc(100vh - 92px)}aside{padding:16px;border-right:1px solid #30363d;overflow:auto;background:#161b22}');
    Html.Add('input,button,select{box-sizing:border-box;width:100%;padding:9px;margin:5px 0;background:#0d1117;color:#e6edf3;border:1px solid #30363d;border-radius:6px}button{cursor:pointer}button:hover{border-color:#58a6ff}button:disabled{opacity:.45;cursor:default}.switch{display:grid;grid-template-columns:1fr 1fr;gap:5px}.switch button.active{border-color:#58a6ff;background:#152f4a}#navigation{position:sticky;top:-16px;z-index:2;padding:10px 0;background:#161b22;border-bottom:1px solid #30363d}#folderBack:not(:disabled){border-color:#f2cc60;color:#f2cc60;font-weight:700}#folderSummary{margin:12px 0;padding:9px;background:#0d1117;border:1px solid #30363d;border-radius:6px;line-height:1.5}#folderSummary summary{cursor:pointer;font-weight:600}#folderSummary ul{padding-left:18px;margin:8px 0}#folderSummary li{margin:5px 0;word-break:break-word}#folders{margin-top:12px}#folders>strong{display:block;margin-bottom:8px}#folders details{border-bottom:1px solid #30363d;padding:6px 0}#folders summary{cursor:pointer;font-weight:600;word-break:break-word}#folders button{text-align:left;font-size:12px;white-space:normal;margin:3px 0;padding:7px 9px}#detail{white-space:pre-wrap;word-break:break-word;line-height:1.5;border-top:1px solid #30363d;margin-top:12px;padding-top:12px}');
    Html.Add('#viewport{overflow:auto;position:relative;cursor:grab}#viewport.dragging{cursor:grabbing}svg{display:block}.edge{stroke:#59636e;stroke-width:1.5;fill:none}.edge.interface{stroke:#79c0ff}.edge.implementation{stroke:#bc8cff}.edge.program{stroke:#f0883e}.edge.selected{stroke:#f2cc60;stroke-width:3}.edge-label{fill:#8b949e;font-size:11px}.node rect{fill:#21262d;stroke:#59636e;stroke-width:1.5;rx:8}.node text{fill:#e6edf3;font-size:12px;pointer-events:none}.node{cursor:pointer}.node.entry rect{fill:#3b241e;stroke:#f0883e}.node.selected rect{stroke:#f2cc60;stroke-width:3}.node.external rect{fill:#30234a}');
    Html.Add('@media(max-width:750px){.layout{grid-template-columns:1fr;grid-template-rows:260px 1fr}aside{border-right:0;border-bottom:1px solid #30363d}}</style></head><body>');
    Html.Add('<header><h1>Mapa de dependências do projeto</h1><p id="summary"></p></header><div class="layout"><aside>');
    Html.Add('<div id="navigation"><button id="folderBack" disabled>← Voltar para o nível anterior</button><div class="switch"><button id="folderMode" class="active">Pastas (visão geral)</button><button id="unitMode">Units</button></div></div>');
    Html.Add('<input id="search" type="search" placeholder="Buscar pasta, unit ou arquivo">');
    Html.Add('<label>Agrupar diretórios</label><select id="folderDepth"><option value="1">1 nível — pasta principal</option></select>');
    Html.Add('<label>Seção</label><select id="section"><option value="all">Todas</option><option value="program">DPR</option><option value="interface">Interface</option><option value="implementation">Implementação</option></select>');
    Html.Add('<button id="fit">Ajustar grafo</button><p id="status"></p><details id="folderSummary"><summary></summary><ul></ul></details><div id="folders"><strong>Pastas e arquivos</strong></div><div id="detail">Clique numa pasta do gráfico ou abra uma pasta na lista.</div>');
    Html.Add('</aside><main id="viewport"><svg id="graph"></svg></main></div><script>');
    Html.Add('const entry=' + SafeJson(Analysis.ProgramFile) + ',entryName=' +
      SafeJson(Analysis.ProgramName) + ',projectRoot=' + SafeJson(Analysis.ProjectRoot) + ';');
    Html.Add('const files=[');
    First := True;
    for Pair in Files do
    begin
      if not First then Html.Add(',');
      First := False;
      if not Analysis.SourceOrigins.TryGetValue(Pair.Key, Origin) then
        Origin := soUnknown;
      Html.Add('{path:' + SafeJson(Pair.Key) + ',name:' + SafeJson(Pair.Value) +
        ',folder:' + SafeJson(FolderOf(Pair.Key, Analysis.ProjectRoot)) +
        ',origin:' + SafeJson(SourceOriginName(Origin)) + '}');
    end;
    Html.Add('];const edges=[');
    First := True;
    for Edge in Analysis.Reachable do
    begin
      if not First then Html.Add(',');
      First := False;
      Html.Add('{from:' + SafeJson(Key(Edge.ConsumerPath)) + ',to:' +
        SafeJson(Key(Edge.UsedPath)) + ',consumer:' + SafeJson(Edge.Consumer) +
        ',used:' + SafeJson(Edge.UsedName) + ',section:' + SafeJson(Edge.Section) +
        ',source:' + SafeJson(Edge.SourceFile) + ',line:' + Edge.Line.ToString + '}');
    end;
    Html.Add('];const fileByPath=new Map(files.map(x=>[x.path,x])),entryKey=entry.toLowerCase();');
    Html.Add('const folders=new Map();for(const f of files){if(!folders.has(f.folder))folders.set(f.folder,[]);folders.get(f.folder).push(f)}const folderOf=p=>fileByPath.get(p)?.folder||"(desconhecido)";');
    Html.Add('function folderParts(folder){if(folder.startsWith("\\\\"))return ["rede",...folder.slice(2).split(/[\\/]+/).filter(Boolean)];return folder.split(/[\\/]+/).filter(Boolean)}const folderDepthSelect=document.getElementById("folderDepth"),allFolders=[...folders.keys()].filter(x=>!["(raiz do projeto)","(desconhecido)"].includes(x)),maxFolderDepth=Math.max(1,...allFolders.map(x=>folderParts(x).length));for(let depth=2;depth<=maxFolderDepth;depth++){const option=document.createElement("option");option.value=String(depth);option.textContent=`${depth} níveis`;folderDepthSelect.appendChild(option)}const fullDepth=document.createElement("option");fullDepth.value="all";fullDepth.textContent="Caminho completo";folderDepthSelect.appendChild(fullDepth);');
    Html.Add('const folderEdges=new Map();for(const e of edges){const from=folderOf(e.from),to=folderOf(e.to);if(from===to)continue;const key=from+"\u0000"+to;if(!folderEdges.has(key))folderEdges.set(key,{from,to,count:0,edges:[]});const x=folderEdges.get(key);x.count++;x.edges.push(e)}');
    Html.Add('const svg=document.getElementById("graph"),viewport=document.getElementById("viewport"),ns="http://www.w3.org/2000/svg";let mode="folders",selected=null,activeFolders=null,folderHistory=[],positions=new Map(),width=800,height=600;');
    Html.Add('function el(tag,attrs,parent=svg){const x=document.createElementNS(ns,tag);for(const [k,v]of Object.entries(attrs))x.setAttribute(k,v);parent.appendChild(x);return x}function text(x,y,value,parent,cls=""){const t=el("text",{x,y,class:cls},parent);t.textContent=value;return t}');
    Html.Add('function folderGroup(folder){if(folder==="(raiz do projeto)"||folder==="(desconhecido)")return folder;const depth=document.getElementById("folderDepth").value;if(depth==="all")return folder;const parts=folderParts(folder),count=Number(depth),joined=parts.slice(0,count).join("\\");return /^[a-z]:$/i.test(joined)?joined+"\\":joined}function filesInGroup(group){return files.filter(x=>(!activeFolders||activeFolders.has(x.folder))&&folderGroup(x.folder)===group)}');
    Html.Add('function filteredEdges(){const section=document.getElementById("section").value,term=document.getElementById("search").value.toLowerCase();return edges.filter(e=>(section==="all"||e.section===section)&&(!activeFolders||activeFolders.has(folderOf(e.from))||activeFolders.has(folderOf(e.to)))&&(!term||`${e.consumer} ${e.used} ${e.from} ${e.to} ${folderOf(e.from)} ${folderOf(e.to)}`.toLowerCase().includes(term)))}');
    Html.Add('function levels(root,nodes,links){const outgoing=new Map();for(const e of links){if(!outgoing.has(e.from))outgoing.set(e.from,[]);outgoing.get(e.from).push(e.to)}const result=new Map([[root,0]]),q=[root];for(let i=0;i<q.length;i++)for(const target of outgoing.get(q[i])||[])if(nodes.has(target)&&!result.has(target)){result.set(target,result.get(q[i])+1);q.push(target)}for(const n of nodes)if(!result.has(n))result.set(n,0);return result}');
    Html.Add('function draw(items,links,root,isFolder){svg.replaceChildren();const nodeWidth=isFolder?320:220,columnWidth=nodeWidth+60;const marker=el("marker",{id:"arrow",viewBox:"0 0 10 10",refX:9,refY:5,markerWidth:7,markerHeight:7,orient:"auto"},el("defs",{}));el("path",{d:"M 0 0 L 10 5 L 0 10 z",fill:"#59636e"},marker);const keys=new Set(items.map(x=>x.key)),lv=levels(root,keys,links),groups=new Map();for(const item of items){const level=lv.get(item.key);if(!groups.has(level))groups.set(level,[]);groups.get(level).push(item)}for(const group of groups.values())group.sort((a,b)=>a.label.localeCompare(b.label));const maxRows=Math.max(1,...[...groups.values()].map(x=>x.length)),maxLevel=Math.max(0,...groups.keys());width=(maxLevel+1)*columnWidth+80;height=maxRows*72+70;svg.setAttribute("viewBox",`0 0 ${width} ${height}`);svg.style.width=width+"px";svg.style.height=height+"px";positions=new Map();for(const[level,group]of groups)group.forEach((x,i)=>positions.set(x.key,{x:30+level*columnWidth,y:30+i*72}));');
    Html.Add('for(const e of links){const a=positions.get(e.from),b=positions.get(e.to);if(!a||!b)continue;const path=el("path",{d:`M ${a.x+nodeWidth} ${a.y+22} C ${a.x+nodeWidth+25} ${a.y+22},${b.x-25} ${b.y+22},${b.x} ${b.y+22}`,class:`edge ${e.section||""}${selected===e?" selected":""}`,"marker-end":"url(#arrow)"});path.addEventListener("click",()=>{selected=e;document.getElementById("detail").textContent=isFolder?`${e.from} → ${e.to}\n${e.count} relação(ões) entre as pastas`:`${e.consumer} usa ${e.used}\n${e.section}:${e.line}\n${e.source}`;render()});if(isFolder&&e.count>1)text((a.x+b.x+nodeWidth)/2,(a.y+b.y+44)/2,String(e.count),svg,"edge-label")}');
    Html.Add('for(const item of items){const p=positions.get(item.key),classes=["node"];if(item.key===root)classes.push("entry");if(selected===item)classes.push("selected");if(item.external)classes.push("external");const g=el("g",{class:classes.join(" ")});el("rect",{x:p.x,y:p.y,width:nodeWidth,height:44},g);const limit=isFolder?45:31;text(p.x+10,p.y+19,item.label.length>limit?item.label.slice(0,limit-2)+"…":item.label,g);text(p.x+10,p.y+35,item.caption,g,"edge-label");const title=el("title",{},g);title.textContent=item.label;g.addEventListener("click",()=>{if(isFolder)openFolder(item.key);else{selected=item;document.getElementById("detail").textContent=item.detail;render()}})}document.getElementById("status").textContent=`${items.length} ${isFolder?"pasta(s)":"arquivo(s)"} | ${links.length} relação(ões)`}');
    Html.Add('function renderFolders(){const active=filteredEdges(),map=new Map();for(const e of active){const from=folderGroup(folderOf(e.from)),to=folderGroup(folderOf(e.to));if(from===to)continue;const key=from+"\u0000"+to;if(!map.has(key))map.set(key,{from,to,count:0,edges:[]});const x=map.get(key);x.count++;x.edges.push(e)}');
    Html.Add('const names=new Set();for(const e of active){const fromFolder=folderOf(e.from),toFolder=folderOf(e.to);if(!activeFolders||activeFolders.has(fromFolder))names.add(folderGroup(fromFolder));if(!activeFolders||activeFolders.has(toFolder))names.add(folderGroup(toFolder))}if(!names.size)for(const f of activeFolders||[folderOf(entryKey)])names.add(folderGroup(f));const items=[...names].map(folder=>{const group=filesInGroup(folder),physical=new Set(group.map(x=>x.folder));');
    Html.Add('return{key:folder,label:folder,caption:`${group.length} arquivo(s) • ${physical.size} pasta(s)`,external:group.some(x=>!["project","project-reference"].includes(x.origin)),detail:`${folder}\n${physical.size} pasta(s)\n${group.length} arquivo(s)\n\n${group.map(x=>x.name+"\n"+x.path).join("\n\n")}`}});const root=items[0]?.key||folderGroup(folderOf(entryKey));draw(items,[...map.values()].filter(x=>names.has(x.from)&&names.has(x.to)),root,true);updateBackButton()}');
    Html.Add('function renderUnits(){const active=filteredEdges(),names=new Set([entryKey]);for(const e of active){names.add(e.from);names.add(e.to)}const items=[...names].map(path=>{const f=fileByPath.get(path)||{name:path,path,folder:"(desconhecido)",origin:"unknown"};return{key:path,label:f.name,caption:f.folder,external:!["project","project-reference"].includes(f.origin),detail:`${f.name}\n${f.path}\n\nPasta: ${f.folder}\nOrigem: ${f.origin}`}});draw(items,active,entryKey,false)}function render(){if(mode==="folders")renderFolders();else renderUnits()}');
    Html.Add('function updateBackButton(){const back=document.getElementById("folderBack");back.disabled=!folderHistory.length;back.textContent=folderHistory.length?`← Voltar para o nível anterior (${folderHistory.length})`:"← Voltar para o nível anterior"}function saveNavigation(){folderHistory.push({folders:activeFolders?[...activeFolders]:null,depth:document.getElementById("folderDepth").value,mode,search:document.getElementById("search").value});updateBackButton()}');
    Html.Add('function setMode(value){mode=value;document.getElementById("folderMode").classList.toggle("active",mode==="folders");document.getElementById("unitMode").classList.toggle("active",mode==="units");selected=null;render();updateBackButton()}function groupDetail(name,group){document.getElementById("detail").textContent=`${name}\n${new Set(group.map(x=>x.folder)).size} pasta(s)\n${group.length} arquivo(s)\n\n${group.map(x=>x.name+"\n"+x.path).join("\n\n")}`}');
    Html.Add('function openFolder(groupName){const group=filesInGroup(groupName),physical=new Set(group.map(x=>x.folder)),depth=document.getElementById("folderDepth").value;saveNavigation();groupDetail(groupName,group);document.getElementById("search").value="";if(physical.size>1&&depth!=="all"&&Number(depth)<maxFolderDepth){activeFolders=physical;document.getElementById("folderDepth").value=String(Number(depth)+1);setMode("folders")}else{activeFolders=physical;setMode("units")}}');
    Html.Add('function openPhysicalFolder(folder){saveNavigation();activeFolders=new Set([folder]);const group=folders.get(folder)||[];document.getElementById("search").value="";groupDetail(folder,group);setMode("units")}function resetFolders(){activeFolders=null;folderHistory=[];document.getElementById("folderDepth").value="1";document.getElementById("search").value="";setMode("folders")}');
    Html.Add('document.getElementById("folderBack").onclick=()=>{const previous=folderHistory.pop();if(!previous)return;activeFolders=previous.folders?new Set(previous.folders):null;document.getElementById("folderDepth").value=previous.depth;document.getElementById("search").value=previous.search||"";setMode(previous.mode||"folders")};document.getElementById("folderMode").onclick=resetFolders;document.getElementById("unitMode").onclick=()=>{if(files.length>1000&&!activeFolders){document.getElementById("detail").textContent="Selecione primeiro uma pasta para evitar renderizar milhares de arquivos de uma vez.";return}if(mode!=="units")saveNavigation();setMode("units")};');
    Html.Add('document.getElementById("search").oninput=render;document.getElementById("section").onchange=render;document.getElementById("folderDepth").onchange=()=>{activeFolders=null;folderHistory=[];document.getElementById("search").value="";setMode("folders")};document.getElementById("fit").onclick=()=>{viewport.scrollLeft=0;viewport.scrollTop=0;svg.style.width="100%";svg.style.height="100%"};');
    Html.Add('const folderCounts=new Map();for(const edge of folderEdges.values()){const out=folderCounts.get(edge.from)||{incoming:0,outgoing:0},inc=folderCounts.get(edge.to)||{incoming:0,outgoing:0};out.outgoing+=edge.count;inc.incoming+=edge.count;folderCounts.set(edge.from,out);folderCounts.set(edge.to,inc)}const summaryBox=document.getElementById("folderSummary"),summaryList=summaryBox.children[1];summaryBox.children[0].textContent=`Resumo: ${folders.size} pastas únicas, ${files.length} arquivos`;for(const [folder,group]of [...folders].sort((a,b)=>a[0].localeCompare(b[0]))){const item=document.createElement("li"),counts=folderCounts.get(folder)||{incoming:0,outgoing:0};item.textContent=`${folder} — ${group.length} arquivo(s), ${counts.incoming} entrada(s), ${counts.outgoing} saída(s)`;summaryList.appendChild(item)}');
    Html.Add('function fillFolder(details,folder,group){if(details.datasetLoaded)return;details.datasetLoaded="1";const open=document.createElement("button");open.textContent="Abrir pasta no gráfico";open.onclick=()=>openPhysicalFolder(folder);details.appendChild(open);for(const f of group.sort((a,b)=>a.name.localeCompare(b.name))){const b=document.createElement("button");b.textContent=f.name;b.title=f.path;b.onclick=()=>{saveNavigation();activeFolders=new Set([f.folder]);document.getElementById("search").value=f.path;setMode("units");document.getElementById("detail").textContent=`${f.name}\n${f.path}\n\nPasta: ${f.folder}\nOrigem: ${f.origin}`};details.appendChild(b)}}const panel=document.getElementById("folders");for(const [folder,group]of [...folders].sort((a,b)=>a[0].localeCompare(b[0]))){const details=document.createElement("details"),summary=document.createElement("summary");summary.textContent=`${folder} (${group.length})`;details.ontoggle=()=>{if(details.open)fillFolder(details,folder,group)};details.appendChild(summary);panel.appendChild(details)}');
    Html.Add('document.getElementById("summary").textContent=`${entryName} | ${files.length} arquivos alcançáveis | ${folders.size} pastas | ${edges.length} relações`;render();');
    Html.Add('</script></body></html>');
    TFile.WriteAllText(FileName, Html.Text, TEncoding.UTF8);
  finally
    Files.Free;
    Html.Free;
  end;
end;

end.
