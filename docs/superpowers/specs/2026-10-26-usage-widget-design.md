# Uso Claude: janela flutuante de limites — Design

Data: 2026-10-26

## Intenção e o porquê

O usuário usa duas contas do Claude no Claude Code e hoje precisa rodar `/usage` repetidamente. Às vezes estoura o limite de uma conta numa tarefa que caberia na outra, que tinha folga. O app resolve isso mostrando, sempre visível, os limites de sessão (5h) e semanais das duas contas, para que ele escolha a conta certa antes de começar uma tarefa.

Sucesso = olhar a janela por um segundo e saber qual conta usar, sem nunca mais digitar `/usage`.

## Objetivos

- Janela pequena, arrastável, que pode ser fixada sempre na frente dos outros apps.
- Mostrar as duas contas lado a lado (modelo B, ver mockup em `.superpowers/brainstorm/*/content/layout.html`), cada uma com:
  - anel de sessão (5h) com % e tempo até renovar;
  - anel semanal com % e dia/hora em que renova.
- Destacar a conta com mais folga.
- Zero cadastro manual: as contas vêm do login que já existe no Claude Code.

## Não objetivos

- Acompanhar uma terceira conta. Existe um item expirado `Claude Code-credentials-a4ed6c15` no Keychain que **deve ser ignorado**.
- Trocar de conta, abrir sessões ou executar o Claude Code.
- Histórico de uso, gráficos ou notificações (podem vir depois).
- Distribuição: notarização ou App Store.

## Anti-objetivos (falha mesmo que "funcione")

- **Deslogar o Claude Code.** O app nunca renova token (refresh) nem escreve no Keychain. Ele só lê.
- Expor tokens: nada de log, arquivo ou tela com token.
- Ficar no caminho: janela grande ou pedidos repetidos de senha do Keychain.

## Restrições e fatos verificados

- macOS 27, Apple Silicon. Só Command Line Tools estão instaladas (Swift 6.1, **sem Xcode**). O build precisa usar SwiftPM, com um script que monta o `.app`.
- Contas e Keychain (verificados em 2026-10-26):

  | Rótulo | Pasta | Item do Keychain (serviço) |
  |---|---|---|
  | claude | `~/.claude` | `Claude Code-credentials` |
  | proteo | `~/.claude-proteo` | `Claude Code-credentials-0f2fbab4` |

  Regra do sufixo: os 8 primeiros caracteres hex do SHA-256 do caminho absoluto da pasta. A pasta padrão `~/.claude` usa o item sem sufixo.
- O conteúdo do item é JSON. O app usa `claudeAiOauth.accessToken` e `claudeAiOauth.expiresAt` (ms epoch).
- Leitura pelo binário `/usr/bin/security find-generic-password -s <serviço> -w`, que já tem acesso sem prompt. Ler via `SecItemCopyMatching` dispararia um pedido de permissão, porque o item pertence a outro app.
- Endpoint (não oficial, pode mudar): `GET https://api.anthropic.com/api/oauth/usage` com os headers `Authorization: Bearer <token>` e `anthropic-beta: oauth-2025-04-20`. A resposta tem `five_hour` e `seven_day`, cada um com `utilization` (0–100, double) e `resets_at` (ISO-8601 com fração de segundos, ou `null`). Os demais campos são ignorados.
- Token expirado: resposta 401 com `authentication_error`.

## Decisões do usuário

- Formato da janela: modelo B (duas colunas, anéis).
- Contas: só as duas acima, detectadas automaticamente.
- App apenas lê. Com login vencido, mostra "abra o Claude Code nessa conta".

## Decisões minhas (o usuário aprovou o resumo)

- Swift + SwiftUI, app nativo. Aparece no Dock e no Command-Tab (decisão do usuário, 2026-10-26); ativar o app ou clicar no Dock traz a janela para a frente. Também tem um ícone na barra de menus com: Mostrar/Ocultar janela, Atualizar agora, Sair.
- Janela `NSPanel` sem borda e com cantos arredondados, que se arrasta pelo fundo (`isMovableByWindowBackground`). Tem um 📌 no canto que alterna o nível entre `.floating` (fixa) e `.normal`. Quando fixa, ganha também `collectionBehavior` `.canJoinAllSpaces` e `.fullScreenAuxiliary`.
- Posição e estado do pin persistem em `UserDefaults`.
- Cores dos anéis: verde < 50%, amarelo 50–80%, vermelho > 80%.
- "Conta recomendada": a de menor % semanal. Se a diferença for menor que 5 pontos, desempata pela menor % de sessão. Conta com semanal ou sessão em 100% nunca é recomendada se a outra tiver folga. A recomendada ganha um contorno verde.
- Atualização a cada 150 s (era 90 s; aumentado para consultar a API com menos frequência), ao clicar em "Atualizar agora" e ao clicar na janela (com debounce de 10 s). O token é relido do Keychain a cada ciclo, para pegar renovações feitas pelo Claude Code.
- Tempo até renovar: sessão como "em 2h40" (ou "—" se `resets_at` for null) e semana como "dom 22:00", no fuso local.
- Estados por conta: carregando, ok, login vencido (401 ou `expiresAt` passado) e erro de rede (mantém os últimos números esmaecidos, com "sem conexão").
- Contas definidas numa lista no código (rótulo + pasta). O serviço do Keychain é derivado pela regra do sufixo. Não há tela de cadastro.
- Projeto: `Package.swift` com o alvo executável `UsoClaude` e `scripts/build-app.sh`, que gera `build/Uso Claude.app` (Info.plist sem `LSUIElement`, assinatura ad-hoc `codesign -s -`).
- Testes unitários (Swift Testing via `swift test`, porque o XCTest não está disponível sem o Xcode) para: derivação do serviço do Keychain, parse da resposta, escolha da conta recomendada e formatação dos tempos. UI e rede são verificadas rodando o app.

## Abrir ao ligar o Mac (decisão do usuário)

- Isso é configurado pelo próprio macOS e não por uma opção dentro do app. O app **não** se registra sozinho para abrir no login.
- `scripts/build-app.sh` aceita `--install`, que copia o app para `/Applications/Uso Claude.app`. Com isso ele aparece normalmente em Ajustes do Sistema › Geral › Itens de Início (botão "+") e o usuário liga ou desliga ali.
- O README explica esse passo em português.

## Deixado para quem implementa

- Organização interna dos arquivos e tipos.
- Detalhes visuais finos (tamanhos, fontes), mantendo a janela em torno de 300×200 pt e o visual escuro do mockup.
