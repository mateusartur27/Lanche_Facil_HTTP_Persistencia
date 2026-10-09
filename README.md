# Lanche Fácil — HTTP + Persistência (Flutter)

Versão do aplicativo **Lanche Fácil** (pedidos antecipados na lanchonete da Faculdade FANS)
adaptada para as duas atividades da disciplina *Laboratório de Desenvolvimento de
Aplicações Móveis e Distribuídas*:

| Apostila | Até a seção | Onde foi aplicada |
|---|---|---|
| **Implementação do Protocolo HTTP no Flutter** (GET • POST • PUT • DELETE) | 17 | Cardápio, cadastro de produtos e pedidos falam com uma API REST |
| **Persistência Local e Banco de Dados Remoto** (SharedPreferences • SQLite • API REST) | 21 | Produtos, pedidos, carrinho e preferências ficam salvos no aparelho e sincronizam com a API |

> Não foi criada nenhuma tela de exemplo do tipo "Minhas Tarefas": o HTTP e a persistência foram
> implementados **nas funcionalidades do próprio app** (cardápio, carrinho, pedidos e gestão do cardápio).

Projeto de origem: <https://github.com/RafaSniper001/Lanche_Facil> (pasta `NOVO_IFOOD/frontend`).

## Sumário

1. [O que mudou em relação ao original](#1-o-que-mudou-em-relação-ao-original)
2. [Como executar](#2-como-executar)
3. [Arquitetura e pastas](#3-arquitetura-e-pastas)
4. [Onde está cada item — Apostila de HTTP](#4-onde-está-cada-item--apostila-de-http-seções-1-a-17)
5. [Onde está cada item — Apostila de Persistência](#5-onde-está-cada-item--apostila-de-persistência-seções-1-a-21)
6. [Roteiro de testes para a apresentação](#6-roteiro-de-testes-para-a-apresentação)
7. [Testes automatizados](#7-testes-automatizados)

---

## 1. O que mudou em relação ao original

* **Tela de login removida.** O app abre direto no cardápio ([`lib/main.dart`](lib/main.dart)).
* O original dependia de Firebase (Auth, Firestore, Cloud Functions, Storage). Como as regras
  do Firestore exigem usuário autenticado, sem login esses serviços deixariam de funcionar. Por isso
  o Firebase foi substituído por:
  * **SQLite** (`sqflite`) — produtos, pedidos e itens do pedido;
  * **SharedPreferences** — tema, carrinho, endereço da API e horário da última sincronização;
  * **API REST via HTTP** (`http`) — publicada no **Cloudflare** (Worker + banco D1, pasta
    [`cloudflare-api/`](cloudflare-api/)) e sempre online, fazendo o papel do "banco remoto" da apostila.
    Há também uma versão local opcional com `json-server` na pasta [`api/`](api/).
* Funcionalidades mantidas e adaptadas: catálogo com busca e categorias, quantidade por produto,
  carrinho com observação, criação de pedido com baixa de estoque, histórico de pedidos com filtros,
  gestão do cardápio (cadastro, edição, estoque, foto por URL, exclusão), tema claro/escuro,
  layout responsivo (celular, tablet e computador) e "Sobre o aplicativo".
* Removidas por dependerem do Firebase/backend com login: pagamento Pix, QR de retirada,
  painel do atendente, painéis de vendas, promoções/notificações, auditoria e diretório de lojas.
  Esse código continua disponível no repositório original.

## 2. Como executar

### 2.1 Jeito mais simples: baixar o APK

1. Baixe o `lanche-facil-http-persistencia.apk` em **[Releases](../../releases/latest)** e instale no celular
   (permita "instalar apps de fontes desconhecidas").
2. Abra o app. Ele já vem configurado para a API na nuvem — não é preciso ligar nenhum servidor.

### 2.2 API REST na nuvem (Cloudflare)

Endereço: **<https://lanche-facil-api.mateus2002ns.workers.dev>**

Abra no navegador para ver o "banco remoto" mudando durante os testes:

* <https://lanche-facil-api.mateus2002ns.workers.dev/produtos>
* <https://lanche-facil-api.mateus2002ns.workers.dev/pedidos>

Código em [`cloudflare-api/src/index.js`](cloudflare-api/src/index.js) (Worker) e
[`cloudflare-api/schema.sql`](cloudflare-api/schema.sql) (tabelas do D1 + cardápio inicial).

**Simular erros** (apostila de HTTP, seção 15): em **Configurações → Servidor da API**, acrescente o trecho no fim do
endereço e **toque em Salvar e testar** (só assim o app passa a usar o novo endereço):

| Endereço | Efeito |
|---|---|
| `https://lanche-facil-api.mateus2002ns.workers.dev/simular/500` | toda requisição responde **HTTP 500** |
| `https://lanche-facil-api.mateus2002ns.workers.dev/simular/404` | toda requisição responde **HTTP 404** |
| `https://lanche-facil-api.mateus2002ns.workers.dev/simular/json-invalido` | os `GET` respondem um JSON quebrado |
| `https://lanche-facil-api.mateus2002ns.workers.dev/simular/lento` | espera 12 s antes de responder (o app desiste em 8 s) |

Depois, toque em **Usar padrão (nuvem)** → **Salvar e testar** para voltar ao normal.

> **Sobre o banco remoto:** o app só conversa com a API por **HTTP + JSON** (`Content-Type: application/json`,
> `jsonEncode`/`jsonDecode`), como pedem as apostilas. O banco por trás da API é um detalhe do servidor: aqui é o
> Cloudflare D1 (SQL/SQLite), e cada registro é guardado como um documento JSON (coluna `json`, igual ao `db.json`
> do json-server). Trocar o banco do servidor (Firebase, Firebird, MySQL...) não muda nada no aplicativo.

Para publicar de novo ou voltar o servidor ao cardápio inicial (precisa de conta Cloudflare com acesso ao projeto):

```bash
cd cloudflare-api
npx wrangler deploy
npx wrangler d1 execute lanche-facil-db --remote --file schema.sql
```

### 2.3 Rodar pelo código-fonte

```bash
flutter pub get
flutter run            # celular ou emulador Android
flutter run -d chrome  # navegador
```

APK: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`.

### 2.4 (Opcional) API local com json-server

Útil para mostrar o banco remoto como arquivo (`api/db.json`) ou testar sem internet externa:

```bash
cd api
npm install
npm start
```

No app: **Configurações → Servidor da API** → `http://10.0.2.2:3000` (emulador),
`http://localhost:3000` (navegador) ou `http://IP-do-computador:3000` (celular na mesma rede Wi-Fi).
Modos de erro locais: `npm run erro500`, `npm run json-invalido`, `npm run lento`; `npm run resetar` volta ao cardápio inicial.

O endereço escolhido fica salvo com SharedPreferences.

## 3. Arquitetura e pastas

```
lib/
├── main.dart                          inicialização sem login (abre direto no cardápio)
├── config/
│   ├── app_dependencies.dart          cria banco, preferências, ApiService e SyncService
│   └── theme.dart                     tema claro/escuro
├── models/
│   ├── product.dart                   Product: toMap/fromMap (SQLite) e toJson/fromJson (API)
│   └── order.dart                     Order e OrderItem: idem
├── database/
│   └── app_database.dart              SQLite: abrir() e CREATE TABLE
├── repositories/
│   ├── product_repository.dart        CRUD local de produtos
│   └── order_repository.dart          CRUD local de pedidos
├── services/
│   ├── api_service.dart               HTTP: GET / POST / PUT / DELETE
│   ├── sync_service.dart              offline-first: SQLite → API e API → SQLite
│   └── preferences_service.dart       SharedPreferences
├── view_models/                       estado e regras de cada tela
├── screens/                           telas (cardápio, pedidos, gestão, configurações...)
└── widgets/                           componentes (navegação, faixa de sincronização...)
cloudflare-api/                        API REST publicada no Cloudflare (Worker + D1)
api/                                   API REST local opcional (json-server)
test/                                  testes automatizados
```

Fluxo: **Tela → ViewModel → Repository (SQLite) → SyncService → ApiService (HTTP) → API REST no Cloudflare (banco D1)**

| Recurso | GET (lista) | GET (um) | POST | PUT | DELETE |
|---|---|---|---|---|---|
| `/produtos` | sincronizar | "Ver no servidor" | cadastrar produto | editar / estoque | excluir produto |
| `/pedidos` | sincronizar | — | confirmar pedido | pronto / retirada / cancelar | excluir do histórico |

## 4. Onde está cada item — Apostila de HTTP (seções 1 a 17)

| Seção da apostila | O que pede | Onde está no projeto |
|---|---|---|
| 1–3. Roteiro, objetivos e pré-requisitos | Fluxo cliente → servidor | App (cliente) → [`cloudflare-api/src/index.js`](cloudflare-api/src/index.js) (servidor REST no Cloudflare) |
| 4. Conceitos (HTTP, métodos, status, JSON) | GET/POST/PUT/DELETE, códigos 200/201/400/401/403/404/500 | Métodos em [`api_service.dart`](lib/services/api_service.dart); tradução dos códigos em [`_messageForStatus`](lib/services/api_service.dart#L233) |
| 5. Preparando o projeto | `flutter pub add http`, permissão de Internet, pastas `models/services/screens` | [`pubspec.yaml`](pubspec.yaml) (`http: ^1.6.0`); [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml#L3) (`INTERNET` + `usesCleartextTraffic` para `http://`) |
| 6. Primeira requisição GET | `Uri.parse`, `http.get`, `statusCode`, `body` | [`ApiService.listarProdutos`](lib/services/api_service.dart#L83) → `GET /produtos`; envio em [`_send`](lib/services/api_service.dart#L181) com log de status e corpo |
| 7. Tela consumindo a API, chamada no `initState` | Buscar dados ao abrir a tela | [`main.dart` `_initialize`](lib/main.dart#L37) dispara a sincronização (GETs) ao abrir; [`ProductServerDialog.initState`](lib/screens/product_server_dialog.dart#L35) |
| 8. JSON → objeto Dart | Model com `fromJson`, `jsonDecode` | [`Product.fromJson`](lib/models/product.dart#L133), [`Order.fromJson`](lib/models/order.dart#L132); `jsonDecode` em [`_decodeBody`](lib/services/api_service.dart#L270) |
| 9. FutureBuilder | Loading / sucesso / erro | [`ProductServerDialog`](lib/screens/product_server_dialog.dart#L55) — Gestão do cardápio → **Ver no servidor** |
| 10. POST | `http.post`, `Content-Type`, `jsonEncode`, 201 | [`criarProduto`](lib/services/api_service.dart#L96) e [`criarPedido`](lib/services/api_service.dart#L136) |
| 10.1 Exercício guiado | TextField + botão **Cadastrar** → chama o POST → mensagem de sucesso/erro → JSON no console | Formulário em [`product_management_screen.dart`](lib/screens/product_management_screen.dart#L382): campos de texto, botão **Cadastrar**, SnackBar com o resultado; o console mostra `[API] Produto cadastrado. JSON retornado: ...` |
| 11. PUT | Atualizar registro | [`atualizarProduto`](lib/services/api_service.dart#L105) (editar, estoque) e [`atualizarPedido`](lib/services/api_service.dart#L144) (pronto, retirado, cancelado) |
| 12. DELETE | Remover registro | [`excluirProduto`](lib/services/api_service.dart#L113) e [`excluirPedido`](lib/services/api_service.dart#L152) |
| 13. Organização Model / Service / Screen | Separar responsabilidades | `models/`, `services/api_service.dart`, `screens/` (+ `view_models/` e `repositories/`) |
| 14. Atividade prática | GET, model, widgets, formulário POST, PUT, DELETE, mensagens | Aplicada ao app (sem "Minhas Tarefas"): GET na sincronização, `Product`/`Order`, cards do cardápio, formulário de produto (POST), editar/estoque/pedido (PUT), excluir (DELETE), SnackBars e faixa de sincronização |
| 15. Tratamento de erros | Sem internet, URL errada, 404, 500, JSON inesperado, cliques repetidos | [`_send`](lib/services/api_service.dart#L181) (`ClientException`, `TimeoutException`, URL inválida), [`_messageForStatus`](lib/services/api_service.dart#L233) (404/500), [`_decodeBody`/`_convert`](lib/services/api_service.dart#L270) (JSON inválido/incompleto); botões desabilitados durante o envio (**Cadastrar**, **Confirmar pedido**, ações do pedido) |
| 16. Headers | `Content-Type` e `Accept`; não colocar tokens no código | [`ApiService.headers`](lib/services/api_service.dart#L67) |
| 17. Testar e depurar | statusCode, body, URL no navegador, uma operação por vez | Console com `[HTTP] → MÉTODO url` / `← status` / corpo; **Configurações → Salvar e testar** (status, quantidade e tempo); URLs da API abertas no navegador |

## 5. Onde está cada item — Apostila de Persistência (seções 1 a 21)

| Seção da apostila | O que pede | Onde está no projeto |
|---|---|---|
| 1–2. Objetivos e visão geral | Flutter → SharedPreferences + SQLite + HTTP/JSON → API REST → banco remoto | Mesma arquitetura: [`preferences_service.dart`](lib/services/preferences_service.dart), [`app_database.dart`](lib/database/app_database.dart), [`api_service.dart`](lib/services/api_service.dart), [`cloudflare-api/`](cloudflare-api/) (banco remoto = Cloudflare D1) |
| 3–4. Preparação | `shared_preferences`, `sqflite`, `path`, `http`; pastas `models/database/repositories/services/screens` | [`pubspec.yaml`](pubspec.yaml) (+ `sqflite_common_ffi_web` para o SQLite no navegador); pastas em [`lib/`](lib/) |
| 5. Dados temporários x persistentes | Memória x SharedPreferences x SQLite x remoto | Tabela abaixo ("O que fica salvo onde") |
| 6. SharedPreferences | Salvar e carregar uma preferência (tema escuro) | Tema: [`themeMode`/`salvarTema`](lib/services/preferences_service.dart#L31), carregado em [`main.dart`](lib/main.dart#L47) e salvo em [`_saveTheme`](lib/main.dart#L137). Também: carrinho ([`carregarCarrinho`](lib/services/preferences_service.dart#L78)/[`salvarCarrinho`](lib/services/preferences_service.dart#L90)), endereço da API e última sincronização |
| 7. Banco SQLite + Model | `AppDatabase.abrir()`, `CREATE TABLE`, `toMap`/`fromMap` | [`AppDatabase.abrir`](lib/database/app_database.dart#L37) e [`_createTables`](lib/database/app_database.dart#L70) (tabelas `produtos`, `pedidos`, `itens_pedido`); [`Product.toMap/fromMap`](lib/models/product.dart#L62), [`Order.toMap/fromMap`](lib/models/order.dart#L81) |
| 8. INSERT | `inserir()` no repository | [`ProductRepository.inserir`](lib/repositories/product_repository.dart#L41), [`OrderRepository.criarPedido`](lib/repositories/order_repository.dart#L58) (transação: pedido + itens + baixa de estoque) |
| 9. SELECT | `listar()` | [`ProductRepository.listar`](lib/repositories/product_repository.dart#L23), [`OrderRepository.listar`](lib/repositories/order_repository.dart#L128) |
| 10. UPDATE | `concluir()` | [`OrderRepository.concluir`](lib/repositories/order_repository.dart#L147) (confirmar retirada), [`marcarComoPronto`](lib/repositories/order_repository.dart#L143), [`cancelar`](lib/repositories/order_repository.dart#L151); [`ProductRepository.atualizar`](lib/repositories/product_repository.dart#L53) e [`atualizarEstoque`](lib/repositories/product_repository.dart#L67) |
| 11. DELETE | `excluir()` | [`ProductRepository.excluir`](lib/repositories/product_repository.dart#L90), [`OrderRepository.excluir`](lib/repositories/order_repository.dart#L182) |
| 12–13. Interface ligada ao banco | Lista + campo + botão; main abrindo a tela | Cardápio ([`home_screen.dart`](lib/screens/home_screen.dart)), Gestão do cardápio ([`product_management_screen.dart`](lib/screens/product_management_screen.dart)), Pedidos ([`orders_screen.dart`](lib/screens/orders_screen.dart)); [`main.dart`](lib/main.dart) |
| 14. Banco remoto (conceito) | Flutter → HTTP → API → banco | Worker [`cloudflare-api/src/index.js`](cloudflare-api/src/index.js) grava no banco D1 ([`schema.sql`](cloudflare-api/schema.sql)); alternativa local: [`api/server.js`](api/server.js) → `api/db.json` |
| 15. Consumindo API remota (GET) | `ApiService.listar()` | [`listarProdutos`](lib/services/api_service.dart#L83) e [`listarPedidos`](lib/services/api_service.dart#L123) |
| 16. Enviando dados (POST) | `criarTarefa()` → aqui produtos e pedidos | [`criarProduto`](lib/services/api_service.dart#L96) e [`criarPedido`](lib/services/api_service.dart#L136) |
| 17. Combinando local e remoto | Salvar no SQLite → tentar enviar → sincronizada/pendente; coluna `sincronizado` | Colunas `sincronizado` (0 pendente / 1 sincronizado), `no_servidor` e `excluido` em [`_createTables`](lib/database/app_database.dart#L70); salvar → enviar em [`saveProduct`](lib/view_models/product_management_view_model.dart#L64) e [`_createOrder`](lib/screens/home_screen.dart#L583); envio em [`tentarEnviarProduto`/`tentarEnviarPedido`](lib/services/sync_service.dart#L115) |
| 18. Testando offline | Criar sem internet e sincronizar depois | Etiqueta **Pendente de envio** em cada item + [faixa de sincronização](lib/widgets/sync_status.dart#L36) (vermelha no modo offline) |
| 19. Sincronização simples | `listarPendentes()` → enviar → `marcarSincronizado()` com try/catch | [`SyncService.sincronizar`](lib/services/sync_service.dart#L96) → [`_sendPending`](lib/services/sync_service.dart#L183) → [`_sendProduct`](lib/services/sync_service.dart#L208)/[`_sendOrder`](lib/services/sync_service.dart#L229) (POST novo, PUT alterado, DELETE excluído) → [`marcarSincronizado`](lib/repositories/product_repository.dart#L142) |
| 20. Organização final | models / database / repositories / services / screens | Ver [seção 3](#3-arquitetura-e-pastas) |
| 21. Tratamento de erros | Rede: manter local; HTTP: informar; JSON inválido; sem internet: continuar | Falhas viram [`ApiException`](lib/services/api_service.dart#L14) com mensagem; dados continuam no SQLite como pendentes; [`SyncResult`](lib/services/sync_service.dart#L13) resume enviados/falhas; o app segue funcionando offline |

### O que fica salvo onde

| Dado | Onde | Continua após fechar o app? |
|---|---|---|
| Produtos, pedidos e itens | SQLite (`lanche_facil.db`) | Sim |
| Tema, carrinho, endereço da API, última sincronização | SharedPreferences | Sim |
| Cópia compartilhada de produtos e pedidos | API REST no Cloudflare (banco D1) | Sim (no servidor) |
| Busca digitada, categoria selecionada | Memória | Não |

## 6. Roteiro de testes para a apresentação

### Preparação

1. Baixe e instale o APK da página **[Releases](../../releases/latest)**.
2. No app, abra ☰ → **Configurações** → **Salvar e testar**. Tem que aparecer *"Conectado! HTTP 200"*.
3. No navegador do computador, deixe abertos (atualize com F5 depois de cada teste para mostrar o servidor mudando):
   * <https://lanche-facil-api.mateus2002ns.workers.dev/produtos>
   * <https://lanche-facil-api.mateus2002ns.workers.dev/pedidos>

### Passo a passo

1. **Sem login:** abra o app. Ele vai direto para o "Cardápio de hoje".
2. **GET:** puxe a tela para baixo (ou toque em **Sincronizar**). Aparece "Tudo salvo no aparelho e no servidor" e os itens ficam com a etiqueta **Sincronizado**.
3. **POST (exercício 10.1):** ☰ → **Gestão do cardápio** → **Novo produto** → preencha → **Cadastrar**. Aparece "Produto cadastrado. Sincronizado com o servidor." e o produto surge em `/produtos`.
4. **GET por id (FutureBuilder):** no produto, toque em **Ver no servidor**. Mostra o carregamento e depois nome, preço, estoque e o JSON recebido.
5. **PUT:** **Editar** o preço → **Salvar**, ou use **+ / −** no estoque. O valor muda em `/produtos`.
6. **DELETE:** **Excluir** um produto → confirmar. Ele some do app e de `/produtos`.
7. **Pedido (POST):** no cardápio, **Adicionar** → carrinho → **Confirmar pedido**. Aparece "Pedido de R$ … confirmado. Sincronizado com o servidor."; o pedido surge em `/pedidos` e o estoque do produto diminui.
8. **Pedido (PUT):** ☰ → **Pedidos** → **Marcar como pronto** → **Confirmar retirada**. O status muda no app e em `/pedidos` (`AWAITING_PICKUP` → `PICKED_UP`).
9. **Cancelar:** em outro pedido, **Cancelar pedido**. Status `CANCELED` e o estoque volta.
10. **Pedido (DELETE):** num pedido retirado ou cancelado, **Excluir do histórico**. Some do app e de `/pedidos`.
11. **SharedPreferences:** **Configurações → Escuro** e coloque itens no carrinho. Feche o app (tire dos recentes) e abra de novo: tema escuro e carrinho continuam.
12. **SQLite:** ative o **modo avião**, feche e abra o app. Cardápio e pedidos continuam aparecendo (vêm do banco do aparelho).
13. **Offline:** ainda em modo avião, crie um pedido e mude um estoque. Aparece "… no aparelho. Envio pendente: Sem conexão com a API…", a etiqueta **Pendente de envio** e a faixa vermelha com o número de pendências.
14. **Sincronizar pendentes:** desligue o modo avião e toque em **Sincronizar**. Tudo vira **Sincronizado** e aparece no navegador.
15. **URL errada:** **Configurações** → apague o endereço e digite `https://servidor-que-nao-existe.invalid` → **Salvar e testar**. Aparece "Falhou: Sem conexão com a API…".
16. **Erros simulados:** em **Configurações**, acrescente o trecho no **fim** do endereço da API e **toque em Salvar e testar** (sem isso o app continua usando o endereço anterior):

    | Acrescente | Depois de **Salvar e testar** | Resultado esperado |
    |---|---|---|
    | `/simular/404` | Toque em **Ver no servidor** num produto | "Falhou: Registro não encontrado no servidor (HTTP 404)" no teste e "(HTTP 404)" no produto |
    | `/simular/500` | Toque em **Sincronizar** | "Erro interno no servidor (HTTP 500)" — os dados continuam salvos no aparelho |
    | `/simular/json-invalido` | Toque em **Sincronizar** | "A API respondeu com um JSON inválido." |
    | `/simular/lento` | Espere o teste terminar (8 s) e **Cadastre** um produto | Botão bloqueado com indicador de carregamento; após 8 s "O servidor demorou para responder" e o produto fica **Pendente de envio** |

    Exemplo de endereço completo: `https://lanche-facil-api.mateus2002ns.workers.dev/simular/500`.
17. **Voltar ao normal:** **Configurações** → **Usar padrão (nuvem)** → **Salvar e testar** → **Sincronizar**. As pendências são enviadas e tudo fica **Sincronizado**.

### Zerar o servidor antes da apresentação

Dentro da pasta `cloudflare-api` (precisa estar logado no Cloudflare com `npx wrangler login`):

```bash
npx wrangler d1 execute lanche-facil-db --remote --file schema.sql
```

Depois de zerar, puxe a tela para baixo no app: ele se alinha com o servidor (pedidos de teste já sincronizados somem
do aparelho e o cardápio volta ao inicial). Para começar o celular totalmente do zero, limpe os dados do app nas configurações do Android.

## 7. Testes automatizados

```bash
flutter test
```

34 testes, todos passando:

| Arquivo | O que cobre |
|---|---|
| [`test/models_test.dart`](test/models_test.dart) | `toMap/fromMap` (SQLite) e `toJson/fromJson` (API), JSON incompleto |
| [`test/api_service_test.dart`](test/api_service_test.dart) | GET, POST (headers + 201), PUT, DELETE, 404, 409, 500, sem conexão, JSON inválido, URL incorreta |
| [`test/repositories_test.dart`](test/repositories_test.dart) | Criação das tabelas, INSERT/SELECT/UPDATE/DELETE, transação do pedido, estoque, cancelamento |
| [`test/sync_service_test.dart`](test/sync_service_test.dart) | Primeira sincronização, modo offline → sincronizar depois, POST/PUT/DELETE corretos, exclusão vinda do servidor |
| [`test/widget_test.dart`](test/widget_test.dart) | App abre sem login em 320/768/1440 px; carrinho no SharedPreferences; pedido offline salvo no SQLite |
| [`test/quantity_contrast_test.dart`](test/quantity_contrast_test.dart) | Contraste do seletor de quantidade (teste original mantido) |

## Autores

Rafael Araújo Nascimento e Mateus Artur Santos — Faculdade FANS.
