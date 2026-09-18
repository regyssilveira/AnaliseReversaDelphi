# Extensão para Delphi 13

A extensão usa o mesmo núcleo do `UnitBacktrace.exe`, compilado dentro de um package design-time. Ela não procura, inicia nem distribui o executável de linha de comando.

## Compilar

Feche o Delphi antes de substituir um BPL já instalado e execute na raiz do repositório:

```powershell
.\tools\Build-IDE.ps1 -Config Release
```

O package será criado em `bin\IDE\UnitBacktraceIDE.bpl`. O Delphi 13 usado neste projeto possui IDE Win32; por isso o package design-time é compilado com `dcc32`, independentemente das plataformas analisadas.

## Instalar

1. Abra **Component > Install Packages** no Delphi 13.
2. Clique em **Add**.
3. Selecione `bin\IDE\UnitBacktraceIDE.bpl`.
4. Confirme e reinicie a IDE se o menu não aparecer imediatamente.

O package adiciona duas ações:

- **Delphi Unit Backtrace - Mapear projeto atual**;
- **Delphi Unit Backtrace - Analisar unit atual**.

A primeira usa o `.dproj` ativo. A segunda usa o projeto ativo e o arquivo `.pas` selecionado no editor. A análise roda em uma thread, mostra progresso, pode ser cancelada e bloqueia uma segunda execução simultânea. Ao terminar, o gráfico é aberto no navegador padrão.

Os arquivos são gravados ao lado do projeto:

```text
analysis-output\<projeto>-<identificador>\project-map
analysis-output\<projeto>-<identificador>\<unit>
```

Cada pasta contém `result.txt`, `graph.dot`, `graph.html` e `analysis.log`, como na linha de comando.

## Desinstalar

Abra **Component > Install Packages**, selecione **UnitBacktraceIDE** e remova o package. Feche o Delphi antes de apagar ou substituir o BPL.

## Limitações desta primeira integração

- o gráfico abre no navegador padrão; o painel acoplável ficará para a próxima etapa;
- configuração, plataforma e Search Paths seguem os padrões do `.dproj` e da instalação ativa do Delphi;
- a unit atual é identificada inicialmente pelo nome do arquivo `.pas`.
