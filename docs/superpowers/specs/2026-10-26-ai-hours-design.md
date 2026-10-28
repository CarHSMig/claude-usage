# Uso Claude: horas de IA por conta e projeto — Design

Data: 2026-10-26 · Estende `2026-10-26-usage-widget-design.md` (o app já existe e funciona).

## Intenção e o porquê

O usuário quer saber quanto tempo a IA trabalhou de fato, para **cobrar horas de clientes** e **acompanhar o próprio trabalho**. O relatório mostra horas de **IA em execução** (não tempo com a janela aberta nem tempo do usuário lendo ou digitando) por conta, projeto, sessão, hora, dia, semana, mês e período livre. Ele fica dentro da janelinha existente.

Sucesso = abrir a gaveta, escolher "outubro" ou "01/09–15/10" e ter um número de horas por projeto em que dá para confiar na hora de cobrar.

## Objetivos

- Registrar com precisão, daqui para a frente, os intervalos em que a IA está executando, via **hooks do Claude Code** nas duas contas.
- Importar o histórico que ainda existe nos transcripts (desde 09/09/2026 em `~/.claude`, 26/09/2026 em `~/.claude-proteo`) usando só o tempo exato (`turn_duration`).
- Guardar tudo num banco local que sobrevive à limpeza de 30 dias do Claude Code.
- Mostrar o relatório numa gaveta abaixo dos anéis (modelo B aprovado, ver `.superpowers/brainstorm/*/content/report-layout-v2.html`).

## Não objetivos

- Exportar PDF, CSV ou Excel (por enquanto é só na tela).
- Agrupar por cliente acima de projeto.
- Renomear projetos pela interface (só se o usuário sentir falta depois).
- Estimar o tempo de respostas antigas sem `turn_duration`.
- Gastar tokens: nada de hooks do tipo `prompt` ou `agent`.

## Anti-objetivos (falha mesmo que "funcione")

- **Hook que imprime algo.** A saída de `UserPromptSubmit` e `SessionStart` entra no contexto da IA, gasta tokens e polui as conversas. O hook nunca escreve em stdout ou stderr e sempre sai com 0.
- **Hook lento ou que trava o Claude Code.** O hook não faz rede, não abre o SQLite e não chama git: só faz append num arquivo.
- **Guardar conteúdo das conversas.** O texto do prompt (que chega no stdin do `UserPromptSubmit`) é descartado. Nenhum conteúdo de mensagem vai para disco.
- **Estragar o `settings.json`.** Os hooks existentes (ai-memory, rtk) precisam continuar intactos.
- **Contar tempo de espera pelo usuário como hora de IA** (diálogo de permissão, pergunta da IA, resposta interrompida e abandonada).
- **Travar a janela** durante a importação inicial (~1,6 GB de transcripts).

## Fatos verificados (2026-10-26)

- Claude Code 2.1.311. Os transcripts ficam em `<pasta>/projects/<cwd-codificado>/<sessionId>.jsonl`.
- As entradas `type: "system", subtype: "turn_duration"` têm `durationMs`, `timestamp` (fim do turno), `cwd`, `sessionId` e `isSidechain`. Total exato: 152,6 h em `~/.claude` e 71,9 h em `~/.claude-proteo`.
- As entradas `type: "ai-title"` têm `aiTitle` e `sessionId` (título da sessão).
- Turnos sem `turn_duration`: a grande maioria são comandos sem resposta da IA (slash e locais), com ~0 h. Os demais têm duração incerta e **ficam fora** (decisão do usuário).
- Os dois `settings.json` já têm `hooks` com `PreToolUse` (rtk, ai-memory), `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `PreCompact`, `Stop`, `SessionEnd`, `SubagentStart` e `SubagentStop`. O formato é `{"matcher": "", "hooks": [{"type": "command", "command": "..."}]}`.
- O app atual: SwiftPM, Swift 6.1, `UsoClaudeCore` (testável) + `UsoClaude` (UI), Swift Testing, `scripts/build-app.sh --install` para `/Applications/Uso Claude.app`. O Xcode está instalado.

## Decisões do usuário

- Tempo contado = **só a IA executando**.
- Projeto = pasta. **Worktrees do mesmo repositório git contam como um projeto só.** Não há nível de cliente.
- **Hooks daqui para a frente. No histórico importado, só o tempo exato.**
- Hooks do tipo `command`, **zero tokens**.
- Banco: **SQLite** (em vez de YAML ou Postgres).
- UI: **gaveta abaixo dos anéis** (opção B), com:
  - filtros **Dia / Semana / Mês / Período…**;
  - setas ‹ › para voltar a períodos anteriores;
  - "Período…" com datas de/até;
  - no **Dia**, de 00:00 a 23:59 com **uma barra por hora**; nos demais, uma barra por dia;
  - **tooltip** ao passar o mouse na barra (total, por conta e por projeto);
  - lista por projeto com barra empilhada por conta.
- Só na tela, sem exportar.

## Decisões minhas (o usuário aprovou o resumo)

- **Por sessão:** clicar num projeto da lista expande as sessões do período (título `aiTitle` ou "sem título", conta, início, horas).
- **Semana:** segunda a domingo, fuso do Mac.
- **Intervalos que cruzam a meia-noite ou uma hora cheia** são fatiados entre os baldes.
- **Agentes em paralelo dentro de uma sessão contam uma vez:** dentro de uma mesma `session_id`, os intervalos são unidos (união de intervalos, sem soma). **Sessões diferentes em paralelo somam**, porque cada projeto tem suas horas (confirmado pelo usuário). Por isso o total do dia pode passar do tempo de relógio, quando duas sessões rodam juntas.
- **Gaveta:** o app lembra se estava aberta e o último filtro (`UserDefaults`).
- **Importação inicial** em segundo plano, com indicador discreto na gaveta ("importando histórico…").
- **Instalação dos hooks** só com a aprovação do usuário, por um botão "Ativar registro de horas" na gaveta. Mostra antes o que vai mudar, faz backup de cada `settings.json` (`settings.json.bak-usoclaude-<timestamp>`) e acrescenta as entradas sem alterar as existentes. A operação é idempotente: não duplica se já estiver instalada.
- **Nome do projeto** = nome da pasta raiz do repositório principal.

## Como funciona

### 1. Hook (`uso-claude-hook`)

- Novo executável no pacote, copiado para `Uso Claude.app/Contents/MacOS/uso-claude-hook`.
- O comando registrado em cada `settings.json` é `'/Applications/Uso Claude.app/Contents/MacOS/uso-claude-hook' --account <label>`. A conta vem do flag, porque cada `settings.json` pertence a uma pasta.
- Lê o JSON do stdin e extrai **apenas** `hook_event_name`, `session_id`, `cwd`, `transcript_path` e, quando existirem, `tool_name` e `notification_type`.
- Acrescenta uma linha JSON com `ts` (agora, ISO-8601 com ms) em `~/Library/Application Support/UsoClaude/events/<label>.jsonl`, abrindo com `O_APPEND` e escrevendo de uma vez só (linha pequena, append atômico).
- Nunca imprime nada e sempre sai com 0, inclusive em caso de erro.
- **Eventos registrados:** `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure` (se existir), `Notification`, `PermissionRequest` (se existir), `Stop`, `SubagentStart`, `SubagentStop`, `SessionStart` e `SessionEnd`.

### 2. Regras de contagem (máquina de estados por `session_id`)

| Evento | Efeito |
|---|---|
| `UserPromptSubmit` | se ocioso → **inicia** intervalo; se havia intervalo aberto sem `Stop` (interrupção), fecha-o no **último evento** daquele turno e inicia um novo |
| espera pelo usuário (diálogo de permissão; `PreToolUse` de `AskUserQuestion` ou `ExitPlanMode`) | **pausa**: fecha o intervalo no instante do evento |
| primeiro evento de atividade após a pausa (`PostToolUse`, `PreToolUse` de outra ferramenta, `SubagentStart/Stop`) | **retoma**: abre novo intervalo |
| `Stop` | **fecha** o intervalo |
| `SessionEnd` | fecha o intervalo aberto no último evento de atividade |
| intervalo aberto sem nenhum evento há mais de 30 min | fechado no último evento de atividade (proteção contra Esc + abandono) |

Pontos a verificar no início da implementação:
- O builder deve confirmar, no Claude Code 2.1.311, qual evento sinaliza o diálogo de permissão: `PermissionRequest` e/ou `Notification` com `notification_type: "permission_prompt"`.
- Se o retorno de uma permissão aprovada só puder ser detectado por `PostToolUse`, o tempo de execução daquela ferramenta específica fica fora. Essa perda é aceitável e deve ser documentada no README.

### 3. Importação do histórico

- Varre `<pasta>/projects/*/*.jsonl` das duas contas em segundo plano.
- Cada `turn_duration` com `isSidechain != true` vira o intervalo `[timestamp − durationMs, timestamp]`, com `source = import`.
- Lê o `ai-title` para o título da sessão.
- Só importa turnos **anteriores ao momento em que os hooks daquela conta foram ativados**, o que evita contar o mesmo turno duas vezes.
- É executada uma vez por conta. Um registro no banco marca a importação como concluída e guarda o corte.

### 4. Projeto de uma pasta

- `git -C <cwd> rev-parse --path-format=absolute --git-common-dir` devolve a raiz do repositório principal (o pai do `.git`), e o nome dessa pasta é o projeto.
- Sem git, ou com a pasta já apagada, o projeto é o nome da própria pasta.
- O resultado vai para cache na tabela `projects(cwd → project)` na primeira vez que a pasta aparece.
- Limitação conhecida: uma worktree antiga já apagada antes da importação pode aparecer como projeto separado. O builder deve tentar inferir pelo prefixo comum com projetos conhecidos. Se não der, aceita-se a limitação, registrada no README.

### 5. Armazenamento

- `~/Library/Application Support/UsoClaude/usage.sqlite`, via `SQLite3` do sistema, sem dependências externas.
- Tabelas (mínimo):
  - `intervals(account, session_id, cwd, start, end, source)`
  - `sessions(session_id, account, title, transcript_path)`
  - `projects(cwd, project)`
  - `ingest(account, events_offset, history_imported_at, hooks_installed_at)`
- O app consome `events/<label>.jsonl` de forma incremental pelo offset e aplica a máquina de estados. Os eventos que chegam com o app fechado entram quando ele abrir.
- Consumo a cada ~10 s com o app aberto (ou observando o arquivo).
- O relatório consulta os intervalos, une por sessão e fatia por hora ou dia no fuso local.

### 6. UI (gaveta)

- O botão "▾ Horas / ▴ Horas" no cabeçalho estica ou recolhe a janela para baixo, mantendo a borda de cima fixa.
- Conteúdo segue o mockup v2:
  - segmentos Dia, Semana, Mês e Período…;
  - navegação ‹ › com o rótulo do período (ex.: "seg, 26 out 2026", "out 2026");
  - total em destaque, "de IA executando";
  - gráfico de barras empilhadas por conta (azul `claude`, roxo `proteo`);
  - tooltip no hover;
  - lista de projetos ordenada por horas, com expansão de sessões.
- No Período…, mostra também a média por dia.
- Se os hooks não estiverem ativos, aparece um aviso e o botão "Ativar registro de horas".

## Decisões tomadas na revisão do documento (minhas)

- **Desativar:** a gaveta também tem "Desativar registro de horas", que remove só as entradas `uso-claude-hook` dos dois `settings.json` (com backup). O README orienta usar isso antes de apagar o app, porque senão o Claude Code tentaria rodar um hook inexistente.
- **Resposta em andamento:** um intervalo ainda aberto conta até "agora" no relatório, para as horas de hoje subirem em tempo real.

## Deixado para quem implementa

- O formato exato das horas ("5h 47min" / "3h50") e o layout fino, mantendo o visual escuro atual.
- A estrutura interna dos módulos.
- O teste da máquina de estados com sequências de eventos sintéticas, que é obrigatório e é onde mora a precisão para cobrança.
