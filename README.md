# Delphi Unit Backtrace

[README em inglês](README.en.md)

Ferramenta console para responder **quem usa uma unit Delphi e por quais caminhos ela chega ao DPR**. A entrada obrigatória é o arquivo `.dproj` e o nome da unit; o caminho do `.pas` é descoberto pelo programa. O resultado contém os caminhos reversos em `result.txt`, todas as ligações alcançáveis em `graph.dot` e decisões de análise em `analysis.log`.

```powershell
UnitBacktrace.exe --project "D:\MeuERP\MeuERP.dproj" --unit uExtrator --output "D:\Analise"
```

O programa procura fontes recursivamente na pasta do projeto e avalia `DCC_UnitSearchPath` e `DCC_IncludePath` com o MSBuild do Delphi 13 para a configuração e plataforma selecionadas. Em uma máquina com Delphi 13, também lê o Search Path e o Browsing Path registrados na IDE para localizar fontes de bibliotecas. Os padrões vêm do `.dproj`; use `--platform Win32|Win64` e `--config Debug|Release` para selecioná-los. Se fontes de uma biblioteca estiverem fora desses caminhos, `--source-root DIR` acrescenta uma raiz recursiva; a opção pode ser repetida. Para analisar somente os caminhos do projeto, use `--no-global-path`.

Uma raiz adicional amplia o escopo da análise; avisos de outras units da biblioteca também podem aparecer no log.

Também encontra arquivos referenciados diretamente pelo DPR, usa `MainSource` quando o DPR tem outro nome e procura includes relativos e em `DCC_IncludePath`. Lê `uses` em `interface` e `implementation` com [DelphiAST](https://github.com/RomanYankovsky/DelphiAST), identifica cada arquivo pelo caminho resolvido e preserva os ramos do grafo. Quando o DelphiAST rejeita uma sintaxe, a ferramenta tenta extrair os `uses` por tokens, registra o fallback e marca o resultado como parcial. Nomes curtos como `Classes` são resolvidos usando a ordem de namespaces do projeto. A enumeração textual é limitada a 10.000 caminhos para evitar explosão combinatória; o DOT conserva todas as ligações alcançáveis. Ciclos e ramos sem consumidores são identificados.

O código separa modelos e interfaces (`Reverse.Domain`), leitura de fontes (`Reverse.AST`), caminhos do projeto e da IDE (`Reverse.MSBuild` e `Reverse.DelphiPaths`), descoberta de fontes (`Reverse.Scope`), resolução de referências (`Reverse.Analysis`), travessia do grafo (`Reverse.Graph`) e saída/log (`Reverse.Output` e `Reverse.Log`). Parser, avaliação MSBuild, provedor de caminhos globais e log usam interfaces para permitir substituição em testes e outras implementações.

## Compilar e testar no Delphi 13

```powershell
git clone --recurse-submodules https://github.com/regyssilveira/delphi-unit-backtrace.git
cd delphi-unit-backtrace
.\tools\Build.ps1 -Platform Win64
.\tools\Build.ps1 -Tests -Platform Win64
.\bin\Win64\UnitBacktraceTests.exe
```

O script usa a instalação local `C:\Program Files (x86)\Embarcadero\Studio\37.0`. Para outro local, ajuste `$bdsRoot` em `tools/Build.ps1`. Os projetos `.dproj` também estão na raiz. DUnitX acompanha o RAD Studio 13; o DelphiAST é um submódulo Git.

O executável para testes locais fica em `bin\Win64\UnitBacktrace.exe`. A análise gera `result.txt`, `graph.dot`, `graph.html` e `analysis.log` na pasta indicada por `--output`. Abra `graph.html` no navegador para explorar o grafo sem instalar dependências. O painel permite buscar uma unit ou arquivo, destacar caminhos que chegam ao DPR e selecionar uma ligação para ver o arquivo e a linha do `uses`. O cabeçalho indica quando a análise é parcial.

A saída elimina linhas exatamente iguais de caminhos e evidências, além de declarações de nós e ligações repetidas no DOT. Relações com arquivo, seção ou linha diferentes continuam separadas. Projetos com muitos ramos podem produzir milhares de caminhos distintos mesmo após essa limpeza; a lista textual mantém o limite de 10.000 caminhos, enquanto o grafo conserva as ligações alcançáveis.

Durante a execução, o console informa a descoberta de arquivos, a análise dos fontes e a resolução das dependências. As contagens e porcentagens usam o total conhecido de cada etapa; a montagem do grafo aparece como etapa em andamento até terminar. As mensagens são limitadas a uma atualização a cada 500 ms por etapa, além do início e do fim. Exemplo:

```text
Preparando projeto e descobrindo arquivos...
Arquivos descobertos: 4 | Win32 | Debug
Analisando arquivos: 0/4 (0%)
Analisando arquivos: 4/4 (100%)
Resolvendo dependencias: 0/5 (0%)
Resolvendo dependencias: 5/5 (100%)
Montando grafo reverso...
Gravando resultado e log...
Concluido: D:\Analise
Abra no navegador: D:\Analise\graph.html
```

## Log e códigos de saída

O log UTF-8 registra `INFO`, `WARN`, `ERROR` e `DEBUG`, incluindo candidatos para a unit alvo, cada relação encontrada, o arquivo escolhido para cada referência, fallback do parser ou MSBuild, falhas e caminhos de busca sem resolução. Código `0`: análise concluída sem fallback, falhas, referências não resolvidas ou ambíguas; `1`: erro fatal; `2`: argumentos ausentes; `3`: resultado gerado com fallback, fontes ou referências sem resolução ou ambíguas. Relações não resolvidas ficam no log e não entram no grafo.

## Alcance atual

Esta versão analisa dependências declaradas em `uses`. Ela não verifica se um símbolo da unit é realmente chamado. Se a avaliação MSBuild falhar, o log registra `msbuild-fallback` e a leitura textual dos caminhos pode incluir configurações não selecionadas; variáveis `$(...)` sem valor conhecido são sinalizadas. O teste sintético reproduzível possui 2.202 fontes distribuídos entre o projeto e três bibliotecas externas. Os testes DUnitX cobrem parser, fallback, includes, caminhos condicionais MSBuild, resolução de arquivos e namespaces, grafo e saída console.

## Exemplo de saída

O projeto pequeno em `tests/fixtures/Small` reproduz a saída sem bibliotecas externas. Execute a partir da raiz do repositório.

```powershell
.\bin\Win64\UnitBacktrace.exe --project .\tests\fixtures\Small\Small.dproj --unit Target --no-global-path --output .\bin\readme-example-output
```

Os trechos abaixo mostram as linhas principais. Os prefixos dos caminhos absolutos foram encurtados e os horários do log foram omitidos.

`result.txt` mostra os caminhos reversos até o DPR e a linha que declarou cada `uses`.

```text
Target: Target | ...\Small\Target.pas
Project entry: Small
Parsed: 4 | AST fallback: 0 | Failed: 0 | Unresolved: 0 | Ambiguous: 0 | Reachable edges: 5

Reverse paths:
Target -> A -> B -> Small [DPR]
Target -> A -> Small [DPR]
Target -> B -> Small [DPR]

Evidence:
Target -> A | interface | ...\Small\A.pas:3 | used file: ...\Small\Target.pas
```

`graph.dot` preserva todas as ligações alcançáveis; cada nó usa o caminho físico do arquivo.

```dot
digraph UnitBacktrace {
  rankdir=LR;
  "...\\Target.pas" -> "...\\A.pas" [label="interface:3"];
  "...\\Target.pas" -> "...\\B.pas" [label="interface:3"];
  "...\\A.pas" -> "...\\B.pas" [label="interface:3"];
  "...\\A.pas" -> "...\\Small.dpr" [label="program:4"];
  "...\\B.pas" -> "...\\Small.dpr" [label="program:5"];
}
```

`analysis.log` registra plataforma, avaliação de caminhos, dependências e resumo.

```text
[INFO] platform | Win32
[INFO] config | Debug
[INFO] msbuild-evaluated | DCC_UnitSearchPath | 1 entries
[DEBUG] dependency | ...\Small\A.pas:3 | A uses Target
[INFO] complete | 4 parsed; 0 fallback; 0 failed; 0 unresolved; 0 ambiguous; 5 reachable edges; 0 ms
```

`[DPR]` indica que o caminho alcançou a entrada do projeto; `interface:3` indica a seção e a linha da declaração.

## Licença

O código desta ferramenta está sob [Apache-2.0](LICENSE). O submódulo DelphiAST mantém suas licenças originais: MPL-2.0 para DelphiAST e avisos MPL-1.1 em quatro arquivos do SimpleParser usados no executável. Consulte [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) e [NOTICE](NOTICE) para atribuições e acesso às fontes. O histórico Git preserva os commits anteriores sob MIT.
