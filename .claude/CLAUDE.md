# ranking-beach-tennis-app — Instruções para Claude

App Flutter (Android, iOS e web/PWA) do ranking individual de beach tennis, organizado em **ligas**
(backend 1.1.0, D-017 a D-023): cada liga tem membros, temporadas, partidas e ranking próprios, e o
app mostra a liga selecionada.
O backend vive em repositório separado (`C:\Users\luche\IdeaProjects\ranking-beach-tennis`),
mantido por outra sessão: **não altere o repositório do backend** (somente leitura). Se o app
precisar de mudança na API, descreva a necessidade para o usuário levar à sessão do backend.

## Regras de trabalho

- **Leia `docs/decisions.md` do backend** (D-001 em diante) antes de mexer em regra de negócio.
  Só implemente o que estiver aprovado ali ou combinado com o usuário nesta conversa; o resto
  deve ser discutido antes. Não invente regras de negócio.
- Trabalho incremental: ao fim de cada etapa, explique o que foi feito, liste os arquivos
  principais, rode `flutter analyze` e `flutter test` e mostre o resultado real, liste
  limitações e pendências e **aguarde aprovação** antes de mudanças grandes.
- Nunca afirme que testes passaram sem executá-los.
- **Commits e pushes somente quando o usuário pedir.** Aprovar uma etapa não é pedir commit.
- **Fluxo de branches (obrigatório, detalhes em `CONTRIBUTING.md`):** nunca commite direto em `dev` ou
  `main`. Para cada mudança: atualize `dev`, crie `feat/`, `fix/`, `refactor/` ou `chore/<nome-em-kebab-case>`
  a partir dela, commite, faça push e abra um pull request para `dev` (`gh pr create --base dev`; a
  descrição termina com a linha de atribuição indicada pelo sistema). Depois de aprovado e mergeado,
  apague a branch (no GitHub e local). `main` é produção e **só recebe pull request da `dev`** (verificação
  `source-branch-is-dev`), quando o usuário pedir; cada release ganha a tag `vX.Y.Z`.
- Depois de todo merge na `main`, a `dev` é sincronizada automaticamente pelo workflow
  `sync-dev-with-main` (PR `main` → `dev` com merge commit). Confira que
  `git log origin/dev..origin/main` ficou vazio; se o workflow falhar, faça o PR à mão.
- Não criar recursos na nuvem (Firebase, Google Cloud, lojas, hospedagem), publicar nada ou
  gerar custos sem aprovação explícita.
- Idiomas:
  - Conversa com o usuário: **pt-BR**.
  - Código, nomes, comentários, documentação técnica e **mensagens de commit: inglês**.
  - Textos da interface: **pt-BR**.
- Mensagens de commit terminam com a linha de coautoria indicada pelo sistema.

## Arquitetura

Organizada por funcionalidade (sem geração de código):

| Pasta | Conteúdo |
|---|---|
| `lib/core/config` | `AppConfig` (`--dart-define`: `API_BASE_URL`, `GOOGLE_SERVER_CLIENT_ID`) |
| `lib/core/network` | Dio com o ID token do Firebase; erros viram `ApiException` |
| `lib/core/routing` | go_router 17 com `StatefulShellRoute` (Ranking, Partidas, Jogadores, Notificações, Perfil; as mesmas abas para todos); `routerRestartProvider` recria o router ao trocar de liga |
| `lib/core/storage` | `LocalStore` (arquivo JSON atômico no celular; SharedPreferences/localStorage na web, via `openLocalStore`), `Cached<T>` (cópia offline), SharedPreferences |
| `lib/features/auth` | `AuthRepository` (Firebase + google_sign_in 7), login, `signOutProvider` |
| `lib/features/me` | `/api/me` (perfil, flag de administrador geral, nome de exibição) e estatísticas globais (`/api/me/statistics`) |
| `lib/features/leagues` | Liga selecionada (`currentLeagueProvider`, `switchLeague`, `enterLeague`), seletor no título, tela Ligas (minhas, convites, explorar), criar/entrar/sair, página da liga e sua administração |
| `lib/features/ranking` | Ranking atual, temporadas passadas |
| `lib/features/matches` | Registro (e correção pelo admin), histórico com filtros, detalhe e auditoria |
| `lib/features/players` | Lista e perfis de jogadores |
| `lib/features/sync` | Fila offline de partidas (`SyncController`) e gatilhos de sincronização |
| `lib/features/notifications` | Caixa de notificações, contador, token FCM (`PushMessaging`), gatilhos |
| `lib/features/admin` | Temporadas da liga atual (em `/leagues/{id}/seasons`) e ações de admin na partida |
| `lib/features/profile` | Aba Perfil: nome de exibição, "Minhas estatísticas" (todas as ligas, sem pontos), "Minhas ligas", tema e sair |

Regras:
- Riverpod 3 sem codegen (`Provider`, `FutureProvider`, `AsyncNotifier`, `Notifier`). O
  `ProviderScope` desliga novas tentativas automáticas: `retry: (_, _) => null`.
- Firebase fica atrás de portas (`AuthRepository`, `PushMessaging`): telas e testes não
  dependem do SDK.
- **Pontos são sempre calculados pelo backend.** O app não replica a fórmula; só valida o
  placar (D-002) para feedback rápido e mostra qual dupla venceu.
- Erros do backend chegam como problem details com `detail` em pt-BR e `code` estável; mostre
  `ApiException.message` ao usuário e use `code` para fluxos específicos
  (`POSSIBLE_DUPLICATE_MATCH`, `MATCH_MODIFIED`).
- Offline: partidas são salvas no celular e enviadas com id gerado no cliente (idempotente).
  Só o autor edita ou descarta a pendência (D-016). Ranking e jogadores têm cópia offline;
  notificações **não** (decisão aprovada).
- Depois de ações que mudam dados, invalide os providers afetados
  (ex.: `refreshAfterMatchChange` em `admin/match_admin_actions.dart`, `refreshLeague` em
  `leagues/league_admin.dart`).
- Ligas: dados da liga só pelas rotas `/api/leagues/{leagueId}/...` (helper `leaguePath`); os
  repositórios recebem o id de `currentLeagueIdProvider` e se refazem ao trocar de liga. Permissão
  de administração **só** pelo `canAdminister` da liga (`canAdministerLeagueProvider`, falso se
  arquivada); `Me.admin` é o administrador geral (desarquivar e buscar arquivadas). Partidas
  pendentes guardam a liga em que foram registradas; cópias offline são por liga.

## Decisões de UX aprovadas pelo usuário (além do decisions.md)

- Permissão de notificações (Android 13+): pedida uma única vez por aparelho, após o login;
  o token FCM é registrado mesmo se o usuário recusar.
- Contador de não lidas: atualiza ao abrir o app, ao voltar para a frente, ao entrar na aba e
  quando chega um push. Sem consulta periódica.
- "Hoje" para limites de temporada usa a data do celular (o backend confere no fuso de
  São Paulo). Atalho "Encerrar hoje" com confirmação.
- Não há aba Admin: todos têm as mesmas 5 abas. Ranking, Partidas e Jogadores são da liga
  selecionada, cujo nome é o título (toque para trocar); Notificações e Perfil valem para todas.
  Trocar de liga volta todas as abas ao início. Sem nenhuma liga, a tela Ligas ocupa o app inteiro
  (sem abas). A administração da liga fica na página da liga (Convidar, Pedidos, Temporadas,
  Editar, Arquivar; menu em cada membro). Corrigir, anular e reverter ficam no menu do detalhe da
  partida. O redirect bloqueia `/admin*` e `/leagues/{id}/seasons*` para quem não administra a liga atual.
- Explorar mostra também as ligas em que o usuário está (etiqueta "Membro"). Link de convite
  `https://ranking-beach-tennis.web.app/convite/{código}` (web com URLs sem `#`); no Android o link
  abre o navegador por enquanto (App Links fica para depois da 1.1.0).
- Notificações de partida sem `leagueId` (anteriores às ligas) são da Arena.
- Ícone do app: raquete em contorno laranja (vazada, espessura levemente variável) com arcos de movimento laranja sobre fundo escuro; fontes SVG em `assets/branding`.

## Ambiente (Windows 11)

- Flutter 3.41.9 / Dart 3.11. Android SDK instalado. Não há Mac (build iOS fica para depois).
- O usuário **não usa emulador**: o app roda no celular dele por USB. O backend local é
  alcançado pelo cabo:

```bash
adb devices
adb reverse tcp:8080 tcp:8080
flutter run -d <id do aparelho> --dart-define=API_BASE_URL=http://localhost:8080 --dart-define=GOOGLE_SERVER_CLIENT_ID=780647009353-jkckmv4ct9lu93o7utqbalafcanqeboi.apps.googleusercontent.com
```

  O `adb reverse` se perde ao desconectar o cabo. Plugin nativo novo ou recurso Android
  (ícones, manifest) exige rebuild completo; mudanças só em Dart aceitam hot restart (`R`).
- Backend local (Docker Desktop aberto): na pasta do backend, `docker compose up -d` e
  `.\mvnw.cmd spring-boot:run` com `JAVA_HOME=C:\Users\luche\.jdks\corretto-25.0.4.1`.
  Para ter admin localmente, defina `ADMIN_AUTH_SUBJECT` com o UID Firebase do usuário
  (consulte `select auth_subject, email from app_user` no Postgres local).
- Firebase: projeto `ranking-beach-tennis`, app Android `com.lucchetta.rankingBeachTennis`
  e iOS configurados (`lib/firebase_options.dart`, `android/app/google-services.json`, `firebase.json`,
  `ios/Runner/Info.plist` com `GIDClientID` e URL scheme; alvo iOS 15.0). O FlutterFire CLI não está no PATH: use
  `dart pub global run flutterfire_cli:flutterfire configure ...` (comando completo no README).
- iPhone sem Mac: workflow manual `.github/workflows/ios-unsigned.yml` gera um `.ipa` sem assinatura,
  instalado pelo usuário com Sideloadly e Apple ID gratuito (expira em 7 dias, sem push).
- Web: `flutter run -d chrome --web-port 5000`; login com Google por popup do Firebase Auth; sem push na
  web (`NoPushMessaging`). Exige CORS no backend e HTTPS em produção (Firebase Hosting planejado:
  `ranking-beach-tennis.web.app`, publicar só com aprovação).
- Push está desligado no backend até o usuário configurar a chave do Firebase; as
  notificações dentro do app funcionam.

## Testes

- Helpers em `test/helpers.dart`: `pumpScreen(..., leagues:)`,
  `deviceOverrides(auth, store, notifications:, push:, leagues:, leagueRepository:, statistics:)`,
  `FakeAuthRepository`, `FakeMatchRepository` (`offline = true` simula falta de conexão),
  `FakeNotificationRepository`, `FakePushMessaging`, `FakeAdminRepository`, `FakeLeagueRepository`,
  `MemoryLocalStore` e dados de exemplo (`sampleMatch`, `sampleNotification`, `primavera`,
  `anaMe`, `adminMe`, `sampleLeague` (membro), `adminLeague` (admin da liga), `noStatistics`).
- Com `leagues:` as ligas vêm prontas; com `leagueRepository:` "Minhas ligas" vem do fake (use para
  entrar/sair/criar). Em `pumpScreen` com `deviceOverrides`, passe `leagues: null`.
- **Nunca deixe os testes chegarem ao Firebase nem à rede real**: use sempre `deviceOverrides`.
- Telas que navegam com go_router precisam de um `GoRouter` no teste (`MaterialApp.router`).
- Armadilhas já encontradas:
  - Em `testWidgets`, não faça I/O real de arquivo (use `MemoryLocalStore`).
  - O timer periódico do `SyncController` precisa ser encerrado dentro do teste.
  - Snackbar exige um `Scaffold` na rota.
  - Itens fora da tela: `scrollUntilVisible`; com mais de uma área rolável (ex.: campo de
    texto com várias linhas), passe `scrollable: find.byType(Scrollable).first`.
  - Uma falha offline simulada é seguida de uma sincronização automática bem-sucedida.
  - Botões Filled/Outlined ocupam a largura toda pelo tema: em linha, use `AppTheme.inlineButton`.
  - `context.push` não muda `currentConfiguration.uri`: confira a tela, não o endereço.
  - Página da liga é longa: aumente a tela do teste (`tester.view.physicalSize`).

## Armadilhas do ambiente

- PowerShell 5.1 quebra argumentos com aspas duplas em comandos nativos: faça commits com
  `git commit -F <arquivo>`.
- `Get-Content` sem `-Encoding UTF8` corrompe acentos; prefira as ferramentas de edição ou bash.
- `dart run flutter_launcher_icons` grava um valor inválido em
  `ios/Runner.xcodeproj/project.pbxproj`; descarte essa alteração (ver README).

## Pendências conhecidas

- Build de release: chave de assinatura (fora do git), assinatura no Gradle, `API_BASE_URL`
  do servidor (backend provavelmente num VPS da Hostinger, com HTTPS) e SHA-1 de release no
  Firebase.
- Distribuição: Android via Firebase App Distribution (recomendado); iOS via TestFlight exige
  conta Apple Developer (US$ 99/ano) e Mac ou build em nuvem. Decisão do usuário pendente.
- Ícone monocromático para ícones temáticos do Android 13+ (opcional).
- Release 1.1.0 (ligas) só depois do backend 1.1.0 em produção; App Links do convite no Android
  depois disso. Remoção das rotas antigas sem liga é do backend, após a publicação do app.

## Referências rápidas

- Decisões de negócio: `C:\Users\luche\IdeaProjects\ranking-beach-tennis\docs\decisions.md`
- Contrato da API: com o backend rodando, `http://localhost:8080/v3/api-docs`
  (Swagger em `/swagger-ui.html`).
- Como rodar, Firebase e ícone: `README.md`.
