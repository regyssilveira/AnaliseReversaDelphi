# Analise Reversa Delphi / Delphi Reverse Dependencies

## Português

Ferramenta console para responder **quem usa uma unit Delphi e por quais caminhos ela chega ao DPR**. A entrada obrigatória é o arquivo `.dproj` e o nome da unit; o caminho do `.pas` é descoberto pelo programa. O resultado contém os caminhos reversos em `result.txt`, todas as ligações alcançáveis em `graph.dot` e decisões de análise em `analysis.log`.

```powershell
ReverseDependencies.exe --project "D:\MeuERP\MeuERP.dproj" --unit uExtrator --output "D:\Analise"
```

O programa procura fontes recursivamente na pasta do projeto e nas pastas explícitas de `DCC_UnitSearchPath`. Inclui o DPR, lê `uses` em `interface` e `implementation` com [DelphiAST](https://github.com/RomanYankovsky/DelphiAST), e preserva todos os ramos do grafo. A enumeração textual é limitada a 10.000 caminhos para evitar explosão combinatória; o DOT conserva todas as ligações alcançáveis. Ciclos e ramos sem consumidores são identificados.

### Compilar e testar no Delphi 13

```powershell
git clone --recurse-submodules https://github.com/regyssilveira/AnaliseReversaDelphi.git
cd AnaliseReversaDelphi
.\tools\Build.ps1 -Platform Win64
.\tools\Build.ps1 -Tests -Platform Win64
.\bin\Win64\ReverseTests.exe
```

O script usa a instalação local `C:\Program Files (x86)\Embarcadero\Studio\37.0`. Para outro local, ajuste `$bdsRoot` em `tools/Build.ps1`. Os projetos `.dproj` também estão na raiz. DUnitX acompanha o RAD Studio 13; o DelphiAST é um submódulo Git.

### Log e códigos de saída

O log UTF-8 registra `INFO`, `WARN`, `ERROR` e `DEBUG`, incluindo candidatos para a unit alvo, cada relação encontrada, falhas de parsing e caminhos de busca sem resolução. Código `0`: análise concluída sem falhas de parsing; `1`: erro fatal; `2`: argumentos ausentes; `3`: resultado gerado com algum arquivo que falhou no parsing.

### Alcance atual

Esta versão analisa dependências declaradas em `uses`. Ela não verifica se um símbolo da unit é realmente chamado. A leitura de `DCC_UnitSearchPath` ainda não avalia todas as condições do MSBuild nem resolve macros `$(...)`; elas são sinalizadas no log. Um projeto grande com caminhos condicionais deve ser conferido antes de tratar o resultado como completo. Também faltam testes com um projeto Delphi real de terceiros; o teste de escala sintético possui 2.202 fontes, inclui três bibliotecas externas à pasta do DPR e completou sem falhas de parsing em cerca de 0,47 s no ambiente de desenvolvimento (Win64).

## English

Console tool answering **which Delphi units use a selected unit, and through which paths it reaches the DPR**. Only a `.dproj` file and the unit name are required; the program finds the `.pas` file. Outputs are reverse paths in `result.txt`, all reachable links in `graph.dot`, and analysis decisions in `analysis.log`.

```powershell
ReverseDependencies.exe --project "D:\MyApp\MyApp.dproj" --unit uExtractor --output "D:\Analysis"
```

It recursively scans the project directory and explicit `DCC_UnitSearchPath` directories, parses interface and implementation `uses` clauses with [DelphiAST](https://github.com/RomanYankovsky/DelphiAST), and preserves converging branches and cycles. Textual path enumeration stops at 10,000 paths to avoid combinatorial explosion; DOT retains every reachable edge. Build and test with the Delphi 13 commands above.

The current scope is declared `uses` dependencies. MSBuild conditions and `$(...)` path macros are not fully evaluated yet and are logged for review. A synthetic 2,202-source project with three external libraries completed without parser errors in about 0.47 s on the development machine (Win64); validation against a large real project is still required.

## License

This project's code is MIT-licensed. DelphiAST is included as a Git submodule under its own MPL-2.0 license.
