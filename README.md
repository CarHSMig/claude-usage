# Uso Claude

App de Mac (barra de menus + janela flutuante + ícone no Dock) que mostra, em tempo real, **quanto você já usou dos limites do Claude Code**: a janela de **sessão (5 h)** e a **semanal**, para cada conta que você usa. Mostra também quais contas têm **mais folga** e quantas **horas de IA** você gastou por projeto.

Feito para quem alterna entre uma ou mais contas do Claude Code (por exemplo, pessoal e trabalho) e quer saber de relance **qual conta usar agora**, sem abrir o terminal.

> Não é um produto da Anthropic nem usa uma API oficial documentada: o app lê o mesmo endpoint de uso que o Claude Code consulta. Veja [Privacidade e segurança](#privacidade-e-segurança).

## O que ele faz

- **Limites das contas, lado a lado.** Dois anéis por conta (sessão e semana), com o horário em que cada limite renova. A conta com mais folga ganha um contorno verde.
- **Ícone no Dock ao vivo.** O ícone do app mostra só a **conta indicada para uso**, com os anéis de sessão e de semana. Dá para deixá-lo fixo no Dock.
- **Avisos do macOS.** Notificação quando uma conta passa de 80% na sessão ou na semana, e quando o limite renova.
- **Janela flutuante.** Arraste por qualquer parte; 📌 fixa na frente de todos os apps e em todas as Mesas; arrastar as bordas ou cantos **redimensiona com zoom** (textos e anéis crescem juntos, de 0,8× a 2,5×).
- **Horas de IA** por conta, projeto e sessão, em gráficos por hora ou por dia.
- **Notas do dia**: um checklist contínuo, com histórico dos dias anteriores.
- **Atualização automática** a cada 2,5 minutos. Clique no quadro de uma conta para atualizar só ela; clique em outro ponto da janela para atualizar todas.
- **Menu na barra de menus:** Mostrar/Ocultar janela, Atualizar agora, Tamanho original, Editar contas, ativar/desativar o registro de horas, enviar aviso de teste e Sair.

## Requisitos

- macOS 14 (Sonoma) ou mais novo.
- Toolchain Swift 6.1 ou mais nova (vem com o **Xcode 16.3+**; ou só as Command Line Tools: `xcode-select --install`).
- O **Claude Code** instalado e logado em cada conta que você quer acompanhar.

## Baixar e instalar

Não há binário pronto para baixar: o app é compilado na sua máquina, o que leva menos de um minuto.

```bash
git clone https://github.com/CarHSMig/claude-usage.git
cd claude-usage
bash scripts/build-app.sh --install
open "/Applications/Uso Claude.app"
```

O script compila, monta o `Uso Claude.app`, assina localmente (assinatura *ad hoc*) e copia para `/Applications`. Sem `--install`, o app é gerado só em `build/Uso Claude.app`. Para atualizar depois, rode `git pull` e o mesmo comando de novo.

Como o app é compilado por você, o macOS não bloqueia a abertura (o aviso de "desenvolvedor não identificado" só aparece em apps baixados prontos). Se copiar o `.app` para outro Mac, abra pela primeira vez com botão direito › **Abrir**.

## Configurar as contas

As contas vêm do login que **já existe no Claude Code**: não é preciso cadastrar senha nem token. O que você informa ao app é só **em qual pasta** cada conta do Claude Code guarda a configuração.

Isso fica num arquivo seu, fora do projeto: `~/Library/Application Support/UsoClaude/accounts.json`. Na primeira abertura o app cria o arquivo com a pasta padrão do Claude Code:

```json
{
  "accounts": [
    { "label": "claude", "directory": "~/.claude" }
  ]
}
```

Para acompanhar mais contas, acrescente uma entrada por conta. Duas contas, por exemplo:

```json
{
  "accounts": [
    { "label": "pessoal", "directory": "~/.claude" },
    { "label": "trabalho", "directory": "~/.claude-trabalho" }
  ]
}
```

| Campo | O que é |
|---|---|
| `directory` | A pasta de configuração daquela conta do Claude Code: a padrão `~/.claude`, ou a que você aponta com a variável `CLAUDE_CONFIG_DIR` ao abrir o Claude Code. Aceita `~`. Obrigatório. |
| `label` | O nome que aparece na janela, no Dock e nos gráficos. Opcional: sem ele, vale o nome da pasta sem o ponto inicial (`~/.claude-trabalho` vira `claude-trabalho`). Use só letras, números, `.`, `-` e `_`. |

Para editar, use **Editar contas…** no ícone da barra de menus, ou abra o arquivo à mão. As contas são lidas **quando o app abre**: depois de salvar, feche e abra o Uso Claude de novo. Se o arquivo estiver com erro (JSON inválido, nome repetido, pasta sem caminho completo), o app avisa o motivo ao abrir e usa só `~/.claude` até você corrigir.

O nome da conta identifica as horas dela no histórico. Se você **renomear** uma conta, as horas antigas ficam com o nome antigo (em cinza nos gráficos). Prefira não mudar nomes depois de começar a usar.

Se aparecer **"abra o Claude Code nessa conta"**, o login daquela conta venceu. Abra o Claude Code com aquela pasta e mande qualquer mensagem: ele renova o login e a janela volta a mostrar os números. O app nunca renova login sozinho, para não deslogar o Claude Code.

## Como usar

1. Abra o **Uso Claude**. A janela aparece e o ícone entra no Dock e na barra de menus.
2. Leia os anéis: sessão (janela de 5 h) em cima, semana embaixo. Verde, amarelo e vermelho indicam a folga que resta. O contorno verde marca a conta mais livre.
3. Para deixar sempre à vista, clique em 📌, ou fixe o ícone no Dock (próxima seção).
4. Para ver horas e notas, clique em **▾ Horas · Notas**.

### Ícone no Dock

O ícone do app no Dock mostra os números ao vivo da **conta indicada para uso**: o nome dela em verde e os anéis de sessão e de semana. Para deixá-lo fixo, com o app aberto clique com o botão direito no ícone › Opções › **Manter no Dock**. Com o app fechado, o Dock mostra o ícone estático (`Resources/AppIcon.icns`, gerado por `swift scripts/make-icon.swift`). Clicar no ícone traz a janela completa para a frente.

### Abrir ao ligar o Mac

Ajustes do Sistema › Geral › Itens de Início › em "Abrir ao iniciar sessão", clique em **+** e escolha **Uso Claude** em Aplicativos. Para desligar, selecione o app na lista e clique em **−**.

## Horas de IA

O botão **▾ Horas · Notas** abre uma gaveta com as horas em que a **IA esteve executando**, por conta, projeto e sessão:

- **Dia:** das 00:00 às 23:59, com uma barra por hora.
- **Semana, Mês e Período…:** uma barra por dia. As setas ‹ › voltam para períodos anteriores.
- **Tooltip:** aparece ao passar o mouse sobre uma barra.
- **Sessões:** clique num projeto para ver as sessões dele.

O que conta como tempo:

- **Conta:** o trecho entre você enviar uma mensagem e a IA terminar a resposta.
- **Não conta:**
  - a espera por você aprovar uma permissão ou responder a uma pergunta da IA;
  - o tempo em que nada acontece.
- **Sessões em paralelo:** somam, porque cada projeto tem suas horas. Por isso o total do dia pode passar do tempo de relógio.
- **Worktrees:** as worktrees de um mesmo repositório contam como um projeto só.

### Ativar o registro

Na gaveta (ou no ícone da barra de menus), clique em **Ativar registro de horas**. O app mostra o que vai mudar e, se você confirmar, faz o seguinte:

1. Faz backup do `settings.json` da pasta de cada conta (`settings.json.bak-usoclaude-…`).
2. Acrescenta um hook do tipo `command` em cada evento, sem mexer nos hooks que já existem.

O hook não gasta tokens: ele não imprime nada e só grava o horário, o evento, a sessão e a pasta em `~/Library/Application Support/UsoClaude/events/`. O texto das suas mensagens não é guardado. Os dados ficam em `~/Library/Application Support/UsoClaude/usage.sqlite`, e o histórico se mantém mesmo depois que o Claude Code apaga as conversas antigas.

O histórico de antes da ativação vem dos transcripts do Claude Code. Dele, entra só o tempo exato de cada resposta (`turn_duration`), sem contar duas vezes os turnos copiados por sessões retomadas.

**Antes de apagar o app**, use **Desativar registro de horas** (no ícone da barra de menus). Senão, o Claude Code vai tentar rodar um hook que não existe mais.

Limitações conhecidas:

- Depois que você aprova uma permissão, o tempo até aquela ferramenta terminar pode ficar de fora, porque não há um evento que marque o momento da aprovação.
- Uma worktree antiga, apagada antes da importação e fora dos padrões `<repo>/.claude/worktrees/…` e `~/.herdr/worktrees/<repo>/…`, pode aparecer como um projeto separado.

## Notas

Aba **Notas** na gaveta (botão "▾ Horas · Notas"): uma nota contínua em forma de checklist.

- Cada linha é uma tarefa com checkbox; **Enter** cria a próxima, **Backspace** numa linha vazia apaga, ↑/↓ navegam.
- Linha terminada em `:` vira título de grupo; linha começando com `-` vira observação solta.
- Na virada do dia o app guarda um **snapshot** de como a nota estava (só em dias em que ela foi mexida) e tira as tarefas
  marcadas; as pendentes continuam. Use ‹ › para ver os dias anteriores (só leitura).
- Fica no mesmo banco local das horas (`usage.sqlite`), tabelas `notes_live` e `notes_snapshots`.

## Privacidade e segurança

- **Credenciais:** o app lê o login do Claude Code no **Keychain** do macOS (pelo comando `security find-generic-password`, o mesmo acesso que o Claude Code tem) e usa o token só para consultar o uso. Ele **não copia nem guarda** o token, e nunca renova login.
- **Rede:** a única chamada é `GET https://api.anthropic.com/api/oauth/usage`, com o token da conta. Nada é enviado a outros servidores.
- **Dados locais:** a lista de contas, as horas e as notas ficam em `~/Library/Application Support/UsoClaude/` (`accounts.json`, `usage.sqlite` e a pasta `events/`). O texto das suas mensagens não é gravado.
- **Settings do Claude Code:** só são alterados se você pedir (**Ativar registro de horas**), com backup e confirmação antes. Dá para desfazer em **Desativar registro de horas**.
- O endpoint de uso não é documentado oficialmente e pode mudar sem aviso; se parar de funcionar, a janela mostra "sem conexão".

## Desenvolvimento

```bash
swift test           # testes
swift run UsoClaude  # roda sem montar o .app
```

O projeto também abre no Xcode: basta abrir a pasta (ou o `Package.swift`).

Estrutura:

| Pasta | O que tem |
|---|---|
| `Sources/UsoClaude` | O app: janela, ícone do Dock, gaveta de horas, notas |
| `Sources/UsoClaudeCore` | Lógica sem interface: uso, contas e `accounts.json`, alertas, horas, notas (a parte testada) |
| `Sources/UsoClaudeHook` | O `uso-claude-hook`, executado pelo Claude Code para registrar as horas |
| `Tests` | Testes do `UsoClaudeCore` |
| `scripts` | `build-app.sh` (compila e instala) e `make-icon.swift` (gera o ícone) |
| `docs` | Specs e planos de implementação |

## Licença

Ainda não definida: sem um arquivo `LICENSE`, o código é de uso privado por padrão. Se for abrir o projeto, adicione uma licença.
