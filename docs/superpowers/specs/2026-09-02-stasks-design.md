# Stasks: design spec

Data: 2026-09-02
Status: aprovado para plano de implementação

## 1. Objetivo

App de menu bar para macOS que mantém uma pilha visível das "abas mentais" abertas. Cada sessão do Claude Code e cada mensagem do Slack marcada com 👀 vira uma tarefa. Tarefas também podem ser criadas à mão. O app mostra título, origem e status (cor), e a janela pode ficar sempre visível.

Uso pessoal, um único usuário, um único Mac. Não há sync, nem multiusuário.

## 2. Decisões fechadas

| Tema | Decisão |
|---|---|
| Stack | Swift 6, SwiftUI + AppKit, projeto Xcode, target macOS 15+, sem dependências externas |
| "Sessão do Claude" | Claude Code (CLI) apenas, via hooks. Claude Desktop fora de escopo |
| Claude → app | Hooks escrevem em `inbox.jsonl`; app observa o arquivo |
| Slack → app | Polling `reactions.list` a cada 15s com user token. Socket Mode fora de escopo |
| Título Slack | Gerado por LLM (Anthropic API, Haiku 4.5), fallback texto truncado |
| Status | `Open` (azul), `In Progress` (âmbar), `Done` (verde) |
| Fechamento Claude | `SessionEnd` (`/exit`) ou prompt contendo "tarefa concluída", "task done" ou "task complete" |
| Fechamento Slack | Reação ✅ (`white_check_mark`) ou `:verify:` do próprio usuário. Remover 👀 não fecha |
| Fechamento manual | Qualquer tarefa pode ser marcada Done pelo menu de contexto |
| Concluídas | Somem da lista principal após 8h (configurável), ficam em seção recolhível, purge em 7 dias |
| Ordem | LIFO (padrão) ou FIFO, toggle no header; campo "Nova tarefa" acompanha a ponta de entrada |
| Tema | Segue o sistema. Escuro: "Dark Glass". Claro: "Light Frosted" |
| Terminal | iTerm2. Clique em tarefa Claude foca a aba da sessão via AppleScript |

## 3. Arquitetura

```
Stasks/
  Stasks.xcodeproj
  Stasks/
    App/         StasksApp.swift, AppDelegate.swift (status item, painel, hotkey)
    Models/      Task.swift, TaskSource.swift, TaskStatus.swift
    Store/       TaskStore.swift (estado observável + persistência JSON)
    Sources/     ClaudeInboxWatcher.swift, TranscriptWatcher.swift,
                 SlackPoller.swift, SlackAPI.swift, TitleGenerator.swift, AnthropicAPI.swift
    UI/          StackPanel.swift, TaskRow.swift, NewTaskField.swift, PanelHeader.swift,
                 SettingsView.swift, StatusItemView.swift
    Support/     Keychain.swift, FileWatcher.swift, Log.swift, HookInstaller.swift,
                 TerminalFocuser.swift
  hooks/         stasks-hook.sh
  StasksTests/
  docs/superpowers/specs/
```

Cada unidade em `Sources/` produz eventos para o `TaskStore` e não conhece a UI. A UI só lê o `TaskStore` e chama métodos de mutação.

### 3.1 Modelo

```swift
enum TaskSource: Codable, Equatable {
  case claude(sessionId: String, transcriptPath: String, cwd: String, itermSessionId: String?)
  case slack(teamId: String, channelId: String, channelName: String, ts: String, permalink: String)
  case manual
}

enum TaskStatus: String, Codable { case open, inProgress, done }

struct Task: Identifiable, Codable, Equatable {
  let id: UUID
  var title: String
  var subtitle: String?
  let source: TaskSource
  var status: TaskStatus
  let createdAt: Date
  var completedAt: Date?
  var isPinnedTitle: Bool      // /rename ou edição manual: LLM/prompt não sobrescreve
  var isProvisionalTitle: Bool // Slack: ainda esperando o LLM
}
```

### 3.2 Persistência

- `~/Library/Application Support/Stasks/tasks.json`: array de `Task`. Gravação atômica (write temp + rename), debounce 200ms após mutação.
- `~/Library/Application Support/Stasks/inbox.jsonl`: fila de eventos dos hooks do Claude.
- `~/Library/Application Support/Stasks/state.json`: cursores do Slack (`lastSeenTs` por canal, `installedAt`), posição do painel, preferências não sensíveis.
- Keychain (service `com.lucianostegun.stasks`): Slack user token, Anthropic API key.
- Preferências simples (LIFO/FIFO, horas de expiração, hotkey, toggle LLM) em `UserDefaults`.

## 4. Integração Claude Code

### 4.1 Hook script (`hooks/stasks-hook.sh`)

Instalado em `~/.claude/settings.json` nos eventos `SessionStart`, `UserPromptSubmit`, `SessionEnd`, `Stop` e `Notification`. Lê o JSON do hook no stdin e faz append de uma linha em `inbox.jsonl`:

```json
{"event":"SessionStart","session_id":"...","cwd":"...","transcript_path":"...","source":"startup|resume|clear|compact","iterm_session_id":"$ITERM_SESSION_ID","term_program":"$TERM_PROGRAM","ts":1788377555}
{"event":"UserPromptSubmit","session_id":"...","prompt":"...","ts":...}
{"event":"SessionEnd","session_id":"...","reason":"...","ts":...}
```

Restrições: usa só `jq` e bash, termina em <50ms, sai com 0 sempre (nunca bloqueia o Claude), cria o diretório se não existir. Não depende do app estar rodando.

### 4.2 `ClaudeInboxWatcher`

- `DispatchSource.makeFileSystemObjectSource` no `inbox.jsonl` (eventos `.write`, `.extend`). Também processa o arquivo inteiro no boot (fila acumulada com o app fechado).
- Lê linhas novas a partir de um offset; ao terminar, trunca o arquivo com lock (`flock` no script, `O_EXLOCK` no app) para evitar corrida com um hook escrevendo.
- Linhas malformadas são ignoradas e logadas.

Regras por evento:

| Evento | Ação |
|---|---|
| `SessionStart` (qualquer origem) | Nunca cria task. Com `resume` e task existente `Done`: reabre como `Open` |
| `UserPromptSubmit` sem task | Prompt vazio, comando (`/...`) ou frase de conclusão: nada. Caso contrário cria task `Open` com título = prompt (primeira linha, 80 chars), subtítulo = nome da pasta, `activity = working` |
| `UserPromptSubmit` com task | Frase de conclusão `(?i)\b(tarefa concluída|task done|task complete)\b` → `Done`. Prompt real → `activity = working`. Título nunca muda por prompt |
| `Stop` | Task ativa → `activity = finished` (Claude terminou a resposta) |
| `Notification` | Task ativa → `activity = waitingInput` (Claude pede permissão ou input) |
| `SessionEnd` | `Done`, `activity = nil` |

Uma sessão com N prompts é uma única task. Chave de deduplicação: `sessionId`.

### 4.3 `TranscriptWatcher`

Para cada task Claude não `Done`, observa `transcriptPath`. Ao ler linha `{"type":"custom-title","customTitle":"...","sessionId":"..."}`, aplica o título e marca `isPinnedTitle = true`. Ao ler uma linha `assistant` da thread principal com blocos de texto, o subtítulo passa a ser o começo dessa resposta (80 chars, primeira linha); blocos `thinking`, `tool_use`, `tool_result` e sidechains são ignorados. Para de observar quando a task vira `Done` ou o arquivo deixa de existir.

### 4.4 `HookInstaller`

Botão em Settings. Lê `~/.claude/settings.json`, faz backup em `settings.json.stasks-backup-<ts>`, adiciona os três hooks apontando para o script dentro do bundle (`Stasks.app/Contents/Resources/stasks-hook.sh`), preserva hooks existentes, grava. Detecta "instalado", "desatualizado" (caminho diferente) ou "ausente".

## 5. Integração Slack

### 5.1 Pré-requisitos no Slack App

User token (`xoxp-`) com scopes: `reactions:read`, `channels:history`, `groups:history`, `im:history`, `mpim:history`, `channels:read`, `groups:read`, `users:read`. Token informado em Settings, validado com `auth.test`, guardado no Keychain.

### 5.2 `SlackPoller`

Intervalo padrão 15s (Tier 2 permite ~20 req/min). Pausa em `NSWorkspace.willSleepNotification`, retoma em `didWakeNotification`.

Ciclo:

1. `reactions.list?limit=50&full=true` (itens do usuário autenticado, mais recentes primeiro; `full=true` traz todos os usuários de cada reação e o `permalink`).
2. Para cada item do tipo `message`, considerando apenas reações onde `users` inclui o próprio `user_id`:
   - contém `eyes` e não existe task com `(channelId, ts)` e `ts >= installedAt - 24h` → cria task.
   - contém `white_check_mark` ou `verify` e existe task não `Done` → `Done`.
3. Ao criar task:
   - título provisório = texto da mensagem, primeira linha, 80 chars; `isProvisionalTitle = true`
   - subtítulo = `#<canal> · <autor>` (`conversations.info`, `users.info`, com cache em memória por 1h). DMs: `DM · <autor>`
   - `permalink` vem no próprio item de `reactions.list` (`full=true`)
   - se `thread_ts` presente: `conversations.replies?limit=15` para contexto
   - dispara `TitleGenerator` em background
4. Atualiza `lastSeenTs` por canal.

Primeiro boot: `installedAt = now`; só mensagens das últimas 24h entram.

### 5.3 Erros

- `invalid_auth`, `token_revoked`, `missing_scope`: para o polling, marca estado "Slack desconectado". Ícone da menu bar ganha ponto vermelho; header do painel mostra a mensagem com link para Settings.
- `ratelimited` ou erro de rede: backoff exponencial 15s → 30s → 60s → ... → 5min, volta a 15s no primeiro sucesso.

## 6. `TitleGenerator`

- Endpoint Anthropic Messages, modelo `claude-haiku-4-5`, `max_tokens: 60`, `temperature: 0.2`.
- System prompt: "Você recebe uma mensagem do Slack e o contexto da thread. Gere um título de tarefa acionável para quem vai responder ou agir sobre a mensagem. Responda só com o título, no idioma da mensagem, máximo 60 caracteres, sem aspas, sem ponto final."
- User content: canal, autor, mensagem, até 15 mensagens da thread (autor + texto).
- Sucesso: se `!isPinnedTitle`, aplica título, `isProvisionalTitle = false`.
- Falha (rede, 4xx, key ausente, toggle desligado): mantém provisório, loga. Retry único na próxima abertura do painel se ainda `isProvisionalTitle`.
- Toggle "gerar títulos com LLM" em Settings desliga tudo isso.

## 7. UI

### 7.1 Menu bar

- `NSStatusItem` com ícone template (pilha de 3 barras) e contador de tarefas `Open + In Progress` ao lado. Contador some em zero.
- Ponto vermelho no ícone quando Slack ou Anthropic estão em erro.
- Clique esquerdo alterna o painel. Clique direito: menu com "Settings…", "Instalar hooks do Claude", "Sair".

### 7.2 Painel

- `NSPanel` (`.nonactivatingPanel`, `.borderless`, `.resizable`), cantos 16pt via `maskImage` no `NSVisualEffectView`, hospedando SwiftUI. Largura fixa 340pt. Altura automática (segue o conteúdo até 70% da tela, depois rola) até o usuário arrastar a borda inferior; a partir daí a altura é manual, persistida em `UserDefaults`, e a lista preenche a janela. Duplo clique no título "Stasks" volta ao automático.
- Abre ancorado abaixo do ícone da menu bar.
- Modo normal: fecha ao clicar fora ou `Esc`.
- Modo "sempre visível" (📌): `level = .floating`, `hidesOnDeactivate = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. Arrastável pelo header, posição persistida. Estado do pin persistido.
- Tema segue o sistema. Escuro: fundo `rgba(24,27,44,.74)` sobre blur, borda `white 10%`. Claro: `rgba(255,255,255,.66)`, borda branca.

### 7.3 Header

`Stasks` · chip com contagem · espaço · toggle `LIFO`/`FIFO` · botão 📌 · botão ＋. Quando há erro de integração, uma linha fina abaixo do header com o aviso e link para Settings.

### 7.4 Linha de tarefa (2 linhas, 340pt)

```
| barra de status | Título (ellipsis) .............. [ícone origem 14pt] |
|                 | Subtítulo (ellipsis) ................... tempo (2h) |
```

- Barra de status: filete 3pt na borda esquerda, com glow. Azul `#5aa9ff` Open, âmbar `#ffb84d` In Progress, verde `#43d17c` Done.
- Atividade do Claude (`activity`): `waitingInput` → linha inteira pulsando em âmbar (fundo, contorno e glow, ciclo de 0.9s); `finished` → glow verde fixo e suave no contorno; `working` → sem efeito. Efeitos só em tasks ativas.
- Ícone de origem: quadrado 14pt arredondado. Claude `#d97757`, Slack `#e01e5a`, Manual `#8a90b8`.
- Tempo relativo: `agora`, `12m`, `2h`, `1d`. Done: riscado, opacidade 50%.
- Hover: fundo `white 6%` (escuro) ou `white 70%` (claro).

### 7.5 Interações

| Gesto | Efeito |
|---|---|
| Clique esquerdo em tarefa Claude | `TerminalFocuser`: AppleScript no iTerm2 seleciona a sessão com `unique id == itermSessionId`, seleciona a aba, ativa o app. Se não achar: `open <cwd>` no Finder |
| Clique esquerdo em tarefa Slack | Abre `slack://channel?team=<teamId>&id=<channelId>&message=<ts>`. Fallback: `permalink` no browser |
| Clique esquerdo em tarefa Manual | Nada |
| Clique direito | Menu: Open / In progress / Done · separador · Abrir origem · Editar título · Remover |
| Duplo clique no título | Edição inline. Enter salva e marca `isPinnedTitle`. Esc cancela |
| `⌘N` (painel aberto) | Foca "Nova tarefa". Enter cria `Open` manual. Esc cancela |
| Hotkey global (padrão `⌥⌘S`) | Alterna o painel |
| Clique em "Concluídas hoje" | Recolhe/expande a seção |

Animações: inserção/remoção com spring, mudança de status com fade na barra lateral. Nada acima de 250ms.

### 7.6 Ordem

- LIFO: mais recente no topo; campo "Nova tarefa" acima da lista.
- FIFO: mais antiga no topo; campo "Nova tarefa" abaixo da lista.
- Seção "Concluídas" sempre no rodapé, ordenada por `completedAt` desc.

## 8. Settings

Janela normal (`⌘,` com painel aberto, ou pelo menu do ícone). Abas:

- **Geral**: LIFO/FIFO, horas até esconder concluídas (padrão 8), hotkey, abrir no login (`SMAppService`).
- **Claude**: status dos hooks (instalado / desatualizado / ausente), botão "Instalar hooks", caminho do inbox, botão "Abrir logs".
- **Slack**: user token (SecureField), botão "Testar" (`auth.test`, mostra workspace e usuário), intervalo de polling (10 a 60s).
- **Anthropic**: API key (SecureField), botão "Testar", toggle "Gerar títulos com LLM".

## 9. Logging

`os.Logger` com subsystem `com.lucianostegun.stasks`, categorias `inbox`, `transcript`, `slack`, `llm`, `ui`. Sem tokens nos logs.

## 10. Testes

**Unit (XCTest)**:
- `TaskStore`: criar, mudar status, ordenar LIFO/FIFO, expiração de Done após N horas, purge em 7 dias, persistência round-trip.
- `InboxParser`: cada evento, linhas malformadas ignoradas, regex de conclusão (positivos e negativos, case-insensitive, acentos).
- `TranscriptParser`: extrai `custom-title`, ignora outros tipos.
- `SlackReactionMapper`: fixtures JSON de `reactions.list` → eventos criar/fechar; ignora reações de outros usuários; respeita janela de 24h; `verify` e `white_check_mark`.
- `TitlePromptBuilder`: monta o prompt com e sem thread; corta em 15 mensagens.
- `HookInstaller`: preserva hooks existentes, detecta desatualizado, cria backup.

**Integração**: `URLProtocol` mock para Slack e Anthropic. Sem rede nos testes.

**Manual (checklist no README)**: hooks disparando em sessão real, `/rename` refletindo, `/exit` fechando, "task done" fechando, clique focando a aba certa do iTerm2, pin sobrevivendo a troca de Space e a fullscreen de outro app, 👀 criando e ✅ fechando.

## 11. Fora de escopo (futuro)

Socket Mode, múltiplos workspaces Slack, Claude Desktop, sync entre Macs, notificações, widgets, assinatura/notarização para distribuição, terminais além do iTerm2.
