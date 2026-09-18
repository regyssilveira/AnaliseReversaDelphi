# Roadmap do Delphi Unit Backtrace

Este documento organiza o caminho da versão `0.6.0` até a `1.0.0`. As versões não têm data fixa: cada marco será publicado quando seus critérios de conclusão forem atendidos.

## Situação atual — 0.6.0

A ferramenta já oferece dois fluxos:

- mapa direto de tudo que é alcançável a partir do DPR;
- backtrace reverso de uma unit até o DPR, um arquivo do projeto ou uma raiz de biblioteca.

Ela avalia configurações do `.dproj` com o MSBuild do Delphi 13, considera Search Paths do projeto e da IDE, aceita raízes adicionais, gera relatório, log, DOT e HTML independente, e possui executáveis Win32 e Win64. A suíte atual tem 40 testes DUnitX, além de testes do JavaScript gerado. O mapa foi validado em um projeto real com 8.034 fontes descobertas e 53.003 relações alcançáveis.

## Definição de pronto para 1.0.0

A versão `1.0.0` estará pronta quando os itens abaixo estiverem concluídos:

- interface de linha de comando e códigos de saída documentados e cobertos por testes de contrato;
- formatos `result.txt`, `analysis.log`, `graph.dot` e `graph.html` considerados estáveis dentro da série 1.x;
- navegação dos dois gráficos validada em Chrome, Edge e Firefox atuais;
- tempo e consumo de memória medidos em projetos pequeno, sintético e grande, com limites de regressão registrados;
- resolução determinística de units duplicadas, namespaces, aliases, Search Paths e includes;
- mensagens acionáveis para referências ambíguas, não resolvidas e arquivos que falharam no parser;
- pacotes Win32 e Win64 reproduzíveis, com licenças, hashes e checklist de publicação;
- nenhuma regressão conhecida de severidade alta e documentação correspondente ao executável publicado.

## 0.7.0 — Estabilidade e desempenho

Prioridade: necessária para a `1.0.0`.

- [ ] Criar benchmarks reproduzíveis para descoberta, parsing, resolução e geração do HTML.
- [ ] Registrar tempo, pico aproximado de memória, quantidade de arquivos e relações no resumo da análise.
- [ ] Reduzir o custo de renderização de pastas com muitas units e relações.
- [ ] Impedir qualquer caminho da interface de abrir acidentalmente um grafo acima do limite seguro.
- [ ] Preservar zoom, posição, filtros e histórico ao alternar entre pastas e units.
- [ ] Testar navegação profunda, ciclos, pastas vazias e caminhos de rede.
- [ ] Adicionar uma fixture hierárquica com `src`, `infrastructure` e vários níveis para evitar regressões de agrupamento.

Critério de conclusão: os benchmarks e testes de navegação passam em Win32 e Win64, e o mapa grande permanece utilizável sem travamentos durante o fluxo normal.

## 0.8.0 — Qualidade da análise

Prioridade: necessária para a `1.0.0`.

- [ ] Explicar no HTML por que cada referência ficou ambígua ou não resolvida e mostrar os candidatos relevantes.
- [ ] Tornar explícita a ordem usada para resolver arquivos de mesmo nome.
- [ ] Ampliar testes de namespaces, aliases, units com escopo, includes condicionais e macros do MSBuild.
- [ ] Revisar a classificação entre arquivo do projeto, referência explícita e biblioteca.
- [ ] Identificar arquivos declarados no projeto que não são alcançáveis pelo DPR, sem confundi-los com bibliotecas disponíveis apenas no Search Path.
- [ ] Produzir um resumo de qualidade com percentuais resolvidos, ambíguos, não resolvidos e processados por fallback.

Critério de conclusão: uma decisão de resolução pode ser auditada pelo log ou HTML, e os casos conhecidos de ambiguidade possuem testes determinísticos.

## 0.9.0 — Candidato à versão 1.0

Prioridade: necessária para a `1.0.0`.

- [ ] Congelar nomes de opções, valores padrão, códigos de saída e estrutura básica dos artefatos.
- [ ] Adicionar `--version` e manter a versão nos relatórios e logs.
- [ ] Criar testes ponta a ponta da CLI para sucesso, resultado parcial, argumentos inválidos e falha fatal.
- [ ] Validar HTML em Chrome, Edge e Firefox.
- [ ] Revisar textos, acessibilidade por teclado, contraste e comportamento em telas menores.
- [ ] Automatizar a montagem dos ZIPs e a geração dos hashes em um único comando de release.
- [ ] Criar `CHANGELOG.md` e um checklist de publicação e rollback.
- [ ] Executar uma rodada de testes em pelo menos três projetos reais com estruturas diferentes.

Critério de conclusão: a `0.9.0` permanece sem regressões de severidade alta durante o período de validação e não exige mudanças incompatíveis para se tornar `1.0.0`.

## 1.0.0 — Contrato estável

- [ ] Corrigir regressões encontradas na `0.9.0`.
- [ ] Publicar a matriz de compatibilidade com Delphi, Windows e navegadores.
- [ ] Documentar as garantias e limitações da série 1.x.
- [ ] Publicar exemplos atualizados dos dois modos usando os binários finais.
- [ ] Assinar a tag e conferir hashes e conteúdo dos pacotes publicados.

## Depois da 1.0

Estes itens agregam valor, mas não bloqueiam a primeira versão estável:

- cache incremental de arquivos sem alteração;
- exportação JSON para integração com outras ferramentas;
- comparação entre duas análises para mostrar dependências adicionadas e removidas;
- análise de vários projetos de um grupo e relações entre executáveis e packages;
- regras configuráveis para limites de arquitetura entre pastas ou camadas;
- relatório adequado para integração contínua, incluindo SARIF se houver um caso de uso comprovado;
- abertura opcional do arquivo e da linha diretamente no editor configurado pelo usuário.

## Fora do escopo atual

- provar uso de símbolos, métodos ou classes dentro de uma unit;
- alterar ou remover automaticamente declarações `uses`;
- compilar o projeto analisado para decidir se uma remoção é segura;
- substituir ferramentas completas de análise semântica do compilador Delphi.

A ferramenta continuará tratando uma declaração `uses` como dependência. As sugestões ajudam a investigar; a remoção deve ser confirmada pela compilação e pelos testes do projeto analisado.

## Como priorizar uma nova tarefa

Uma tarefa entra antes da `1.0.0` quando corrige resultado incorreto, travamento, perda de navegação, comportamento não determinístico ou ausência de informação necessária para auditar a análise. Melhorias de conveniência e novas integrações ficam para depois da estabilidade, salvo quando forem necessárias para validar um projeto real.
