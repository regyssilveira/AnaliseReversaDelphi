# Third-party components

The application's own code is licensed under Apache-2.0. The DelphiAST Git
submodule retains its upstream licenses; it is not relicensed by this project.

## DelphiAST

The [DelphiAST project](https://github.com/RomanYankovsky/DelphiAST/tree/38402535ad6018b981f08920836aac99b554cb86)
states that it is licensed under MPL-2.0. Its license text is preserved at
[vendor/DelphiAST/LICENSE](vendor/DelphiAST/LICENSE). The submodule is pinned
to commit `38402535ad6018b981f08920836aac99b554cb86`.

Four parser files compiled into the application carry separate MPL-1.1
notices in their source headers:

- `Source/SimpleParser/SimpleParser.pas`
- `Source/SimpleParser/SimpleParser.Types.pas`
- `Source/SimpleParser/SimpleParser.Lexer.pas`
- `Source/SimpleParser/SimpleParser.Lexer.Types.pas`

Their license text is included in [licenses/MPL-1.1.txt](licenses/MPL-1.1.txt).
The original source and its notices are available in the pinned DelphiAST
submodule above. Recipients of the executable can obtain the exact source by
cloning this project with `--recurse-submodules` at the corresponding release
tag, or by opening the pinned upstream commit.
