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
  * **API REST via HTTP** (`http`) — servidor `json-server` na pasta [`api/`](api/), que faz o papel do
    "banco remoto" da apostila.
* Funcionalidades mantidas e adaptadas: catálogo com busca e categorias, quantidade por produto,
  carrinho com observação, criação de pedido com baixa de estoque, histórico de pedidos com filtros,
  gestão do cardápio (cadastro, edição, estoque, foto por URL, exclusão), tema claro/escuro,
  layout responsivo (celular, tablet e computador) e "Sobre o aplicativo".
* Removidas por dependerem do Firebase/backend com login: pagamento Pix, QR de retirada,
  painel do atendente, painéis de vendas, promoções/notificações, auditoria e diretório de lojas.
  Esse código continua disponível no repositório original.

## 2. Como executar

Pré-requisitos: **Flutter 3.x** e **Node.js 18+**.

### 2.1 Subir a API REST (banco remoto)

```bash
cd api
npm install
npm start
```

O terminal mostra os endereços:

```
API do Lanche Fácil rodando na porta 3000
  Navegador / Flutter Web : http://localhost:3000/produtos
  Emulador Android        : http://10.0.2.2:3000
  Celular na mesma rede   : http://192.168.x.x:3000
```

Abra <http://localhost:3000/produtos> e <http://localhost:3000/pedidos> no navegador para ver os dados do servidor.
Os dados ficam em `api/db.json` (criado a partir de [`api/db.inicial.json`](api/db.inicial.json)).
Para voltar ao cardápio inicial: `npm run resetar`.

Modos de teste de erro (pare com `Ctrl+C` e suba de novo com o modo desejado):

| Comando | Efeito |
|---|---|
| `npm run erro500` | toda requisição responde **HTTP 500** |
| `npm run json-invalido` | os `GET` respondem um JSON quebrado |
| `npm run lento` | espera 12 s antes de responder (o app desiste em 8 s) |

### 2.2 Rodar o aplicativo

```bash
flutter pub get
flutter run            # celular ou emulador Android
flutter run -d chrome  # navegador
```

APK: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
(também anexado na página **Releases** deste repositório).

### 2.3 Endereço da API dentro do app

Menu ☰ → **Configurações** → **Servidor da API (HTTP)** → **Salvar e testar**.

| Onde o app roda | Endereço |
|---|---|
| Emulador Android | `http://10.0.2.2:3000` (padrão no Android) |
| Navegador (Chrome) | `http://localhost:3000` (padrão na Web) |
| Celular físico (APK) | `http://IP-do-computador:3000` — mesma rede Wi-Fi; libere o Node.js no Firewall do Windows |

O endereço fica salvo com SharedPreferences.

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
api/                                   API REST local (json-server)
test/                                  testes automatizados
```

Fluxo: **Tela → ViewModel → Repository (SQLite) → SyncService → ApiService (HTTP) → API REST (db.json)**

| Recurso | GET (lista) | GET (um) | POST | PUT | DELETE |
|---|---|---|---|---|---|
| `/produtos` | sincronizar | "Ver no servidor" | cadastrar produto | editar / estoque | excluir produto |
| `/pedidos` | sincronizar | — | confirmar pedido | pronto / retirada / cancelar | excluir do histórico |

## 4. Onde está cada item — Apostila de HTTP (seções 1 a 17)

| Seção da apostila | O que pede | Onde está no projeto |
|---|---|---|
| 1–3. Roteiro, objetivos e pré-requisitos | Fluxo cliente → servidor | App (cliente) → [`api/server.js`](api/server.js) (servidor REST) |
| 4. Conceitos (HTTP, métodos, status, JSON) | GET/POST/PUT/DELETE, códigos 200/201/400/401/403/404/500 | Métodos em [`api_service.dart`](lib/services/api_service.dart); tradução dos códigos em [`_messageForStatus`](lib/services/api_service.dart#L233) |
| 5. Preparando o projeto | `flutter pub add http`, permissão de Internet, pastas `models/services/screens` | [`pubspec.yaml`](pubspec.yaml) (`http: ^1.6.0`); [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml#L3) (`INTERNET` + `usesCleartextTraffic` para `http://`) |
| 6. Primeira requisição GET | `Uri.parse`, `http.get`, `statusCode`, `body` | [`ApiService.listarProdutos`](lib/services/api_service.dart#L83) → `GET /produtos`; envio em [`_send`](lib/services/api_service.dart#L181) com log de status e corpo |
| 7. Tela consumindo a API, chamada no `initState` | Buscar dados ao abrir a tela | [`main.dart` `_initialize`](lib/main.dart#L37) dispara a sincronização (GETs) ao abrir; [`ProductServerDialog.initState`](lib/screens/product_server_dialog.dart#L35) |
| 8. JSON → objeto Dart | Model com `fromJson`, `jsonDecode` | [`Product.fromJson`](lib/models/product.dart#L133), [`Order.fromJson`](lib/models/order.dart#L132); `jsonDecode` em [`_decodeBody`](lib/services/api_service.dart#L268) |
| 9. FutureBuilder | Loading / sucesso / erro | [`ProductServerDialog`](lib/screens/product_server_dialog.dart#L55) — Gestão do cardápio → **Ver no servidor** |
| 10. POST | `http.post`, `Content-Type`, `jsonEncode`, 201 | [`criarProduto`](lib/services/api_service.dart#L96) e [`criarPedido`](lib/services/api_service.dart#L136) |
| 10.1 Exercício guiado | TextField + botão **Cadastrar** → chama o POST → mensagem de sucesso/erro → JSON no console | Formulário em [`product_management_screen.dart`](lib/screens/product_management_screen.dart#L382): campos de texto, botão **Cadastrar**, SnackBar com o resultado; o console mostra `[API] Produto cadastrado. JSON retornado: ...` |
| 11. PUT | Atualizar registro | [`atualizarProduto`](lib/services/api_service.dart#L105) (editar, estoque) e [`atualizarPedido`](lib/services/api_service.dart#L144) (pronto, retirado, cancelado) |
| 12. DELETE | Remover registro | [`excluirProduto`](lib/services/api_service.dart#L113) e [`excluirPedido`](lib/services/api_service.dart#L152) |
| 13. Organização Model / Service / Screen | Separar responsabilidades | `models/`, `services/api_service.dart`, `screens/` (+ `view_models/` e `repositories/`) |
| 14. Atividade prática | GET, model, widgets, formulário POST, PUT, DELETE, mensagens | Aplicada ao app (sem "Minhas Tarefas"): GET na sincronização, `Product`/`Order`, cards do cardápio, formulário de produto (POST), editar/estoque/pedido (PUT), excluir (DELETE), SnackBars e faixa de sincronização |
| 15. Tratamento de erros | Sem internet, URL errada, 404, 500, JSON inesperado, cliques repetidos | [`_send`](lib/services/api_service.dart#L181) (`ClientException`, `TimeoutException`, URL inválida), [`_messageForStatus`](lib/services/api_service.dart#L233) (404/500), [`_decodeBody`/`_convert`](lib/services/api_service.dart#L268) (JSON inválido/incompleto); botões desabilitados durante o envio (**Cadastrar**, **Confirmar pedido**, ações do pedido) |
| 16. Headers | `Content-Type` e `Accept`; não colocar tokens no código | [`ApiService.headers`](lib/services/api_service.dart#L67) |
| 17. Testar e depurar | statusCode, body, URL no navegador, uma operação por vez | Console com `[HTTP] → MÉTODO url` / `← status` / corpo; **Configurações → Salvar e testar** (status, quantidade e tempo); URLs da API abertas no navegador |

## 5. Onde está cada item — Apostila de Persistência (seções 1 a 21)

| Seção da apostila | O que pede | Onde está no projeto |
|---|---|---|
| 1–2. Objetivos e visão geral | Flutter → SharedPreferences + SQLite + HTTP/JSON → API REST → banco remoto | Mesma arquitetura: [`preferences_service.dart`](lib/services/preferences_service.dart), [`app_database.dart`](lib/database/app_database.dart), [`api_service.dart`](lib/services/api_service.dart), [`api/`](api/) (`db.json` = banco remoto) |
| 3–4. Preparação | `shared_preferences`, `sqflite`, `path`, `http`; pastas `models/database/repositories/services/screens` | [`pubspec.yaml`](pubspec.yaml) (+ `sqflite_common_ffi_web` para o SQLite no navegador); pastas em [`lib/`](lib/) |
| 5. Dados temporários x persistentes | Memória x SharedPreferences x SQLite x remoto | Tabela abaixo ("O que fica salvo onde") |
| 6. SharedPreferences | Salvar e carregar uma preferência (tema escuro) | Tema: [`themeMode`/`salvarTema`](lib/services/preferences_service.dart#L31), carregado em [`main.dart`](lib/main.dart#L47) e salvo em [`_saveTheme`](lib/main.dart#L137). Também: carrinho ([`carregarCarrinho`](lib/services/preferences_service.dart#L72)/[`salvarCarrinho`](lib/services/preferences_service.dart#L84)), endereço da API e última sincronização |
| 7. Banco SQLite + Model | `AppDatabase.abrir()`, `CREATE TABLE`, `toMap`/`fromMap` | [`AppDatabase.abrir`](lib/database/app_database.dart#L37) e [`_createTables`](lib/database/app_database.dart#L70) (tabelas `produtos`, `pedidos`, `itens_pedido`); [`Product.toMap/fromMap`](lib/models/product.dart#L62), [`Order.toMap/fromMap`](lib/models/order.dart#L81) |
| 8. INSERT | `inserir()` no repository | [`ProductRepository.inserir`](lib/repositories/product_repository.dart#L41), [`OrderRepository.criarPedido`](lib/repositories/order_repository.dart#L58) (transação: pedido + itens + baixa de estoque) |
| 9. SELECT | `listar()` | [`ProductRepository.listar`](lib/repositories/product_repository.dart#L23), [`OrderRepository.listar`](lib/repositories/order_repository.dart#L128) |
| 10. UPDATE | `concluir()` | [`OrderRepository.concluir`](lib/repositories/order_repository.dart#L147) (confirmar retirada), [`marcarComoPronto`](lib/repositories/order_repository.dart#L143), [`cancelar`](lib/repositories/order_repository.dart#L151); [`ProductRepository.atualizar`](lib/repositories/product_repository.dart#L53) e [`atualizarEstoque`](lib/repositories/product_repository.dart#L67) |
| 11. DELETE | `excluir()` | [`ProductRepository.excluir`](lib/repositories/product_repository.dart#L90), [`OrderRepository.excluir`](lib/repositories/order_repository.dart#L182) |
| 12–13. Interface ligada ao banco | Lista + campo + botão; main abrindo a tela | Cardápio ([`home_screen.dart`](lib/screens/home_screen.dart)), Gestão do cardápio ([`product_management_screen.dart`](lib/screens/product_management_screen.dart)), Pedidos ([`orders_screen.dart`](lib/screens/orders_screen.dart)); [`main.dart`](lib/main.dart) |
| 14. Banco remoto (conceito) | Flutter → HTTP → API → banco | [`api/server.js`](api/server.js) grava em `api/db.json` |
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
| Cópia compartilhada de produtos e pedidos | API REST (`api/db.json`) | Sim (no servidor) |
| Busca digitada, categoria selecionada | Memória | Não |

## 6. Roteiro de testes para a apresentação

Antes: suba a API (`cd api && npm start`), abra o app e confira em **Configurações → Salvar e testar**
a mensagem *"Conectado! HTTP 200 · 5 produto(s) no servidor"*.
Deixe <http://localhost:3000/produtos> e <http://localhost:3000/pedidos> abertos no navegador para mostrar o servidor.

| # | Teste | Como fazer | Resultado esperado |
|---|---|---|---|
| 1 | **Sem login** | Abrir o app | Vai direto para "Cardápio de hoje" |
| 2 | **GET** | Puxar a lista para baixo (ou **Sincronizar**) | Faixa "Tudo salvo no aparelho e no servidor" e etiquetas **Sincronizado**; no console `[HTTP] ← 200 GET .../produtos` |
| 3 | **POST (exercício 10.1)** | ☰ → **Gestão do cardápio** → **Novo produto** → preencher → **Cadastrar** | SnackBar "Produto cadastrado. Sincronizado com o servidor."; console mostra o JSON retornado (201); produto aparece em `/produtos` no navegador e no cardápio |
| 4 | **GET por id + FutureBuilder** | No produto → **Ver no servidor** | Carregando → nome, preço, estoque e o JSON recebido |
| 5 | **PUT** | **Editar** o preço → **Salvar**; usar **+ / −** no estoque | Valor novo em `/produtos` no navegador |
| 6 | **DELETE** | **Excluir** um produto → confirmar | Some do app e de `/produtos` |
| 7 | **Pedido (POST /pedidos)** | Cardápio → **Adicionar** → carrinho → **Confirmar pedido** | "Pedido de R$ … confirmado. Sincronizado com o servidor."; aparece em `/pedidos`; estoque do produto diminui |
| 8 | **Pedido (PUT)** | ☰ → **Pedidos** → **Marcar como pronto** → **Confirmar retirada** | Status muda no app e em `/pedidos` (`AWAITING_PICKUP` → `PICKED_UP`) |
| 9 | **Cancelar** | Em outro pedido → **Cancelar pedido** | Status `CANCELED` e estoque devolvido |
| 10 | **Pedido (DELETE)** | Pedido retirado/cancelado → **Excluir do histórico** | Some do app e de `/pedidos` |
| 11 | **SharedPreferences** | **Configurações → Escuro**; adicionar itens ao carrinho; **fechar o app** e abrir de novo | Tema escuro e carrinho continuam |
| 12 | **SQLite** | Cadastrar produto/pedido, **fechar o app** (até com a API desligada) e abrir | Tudo continua na lista |
| 13 | **Offline** | Parar a API (`Ctrl+C`) → criar um pedido e mudar um estoque | "… no aparelho. Envio pendente: Sem conexão com a API…"; etiqueta **Pendente de envio**; faixa vermelha com o número de pendências |
| 14 | **Sincronizar pendentes** | Subir a API (`npm start`) → **Sincronizar** | Etiquetas viram **Sincronizado**; registros aparecem no navegador |
| 15 | **URL incorreta** | Configurações → `http://localhost:9999` → **Salvar e testar** | "Falhou: Sem conexão com a API…" (depois clique **Usar padrão**) |
| 16 | **404** | Com a API parada, cadastrar um produto; subir a API; antes de sincronizar → **Ver no servidor** | "Este produto ainda não existe no servidor (HTTP 404)" |
| 17 | **500** | `npm run erro500` → **Sincronizar** | "Não foi possível sincronizar. Erro interno no servidor (HTTP 500)." — dados seguem salvos e pendentes |
| 18 | **JSON inválido** | `npm run json-invalido` → **Sincronizar** | "A API respondeu com um JSON inválido." |
| 19 | **Carregamento e cliques repetidos** | `npm run lento` → **Cadastrar** um produto | Botão desabilitado com indicador de carregamento; após 8 s "O servidor demorou para responder" e o produto fica pendente |

Depois dos testes: `npm run resetar` volta a API ao cardápio inicial.

## 7. Testes automatizados

```bash
flutter test
```

33 testes, todos passando:

| Arquivo | O que cobre |
|---|---|
| [`test/models_test.dart`](test/models_test.dart) | `toMap/fromMap` (SQLite) e `toJson/fromJson` (API), JSON incompleto |
| [`test/api_service_test.dart`](test/api_service_test.dart) | GET, POST (headers + 201), PUT, DELETE, 404, 500, sem conexão, JSON inválido, URL incorreta |
| [`test/repositories_test.dart`](test/repositories_test.dart) | Criação das tabelas, INSERT/SELECT/UPDATE/DELETE, transação do pedido, estoque, cancelamento |
| [`test/sync_service_test.dart`](test/sync_service_test.dart) | Primeira sincronização, modo offline → sincronizar depois, POST/PUT/DELETE corretos, exclusão vinda do servidor |
| [`test/widget_test.dart`](test/widget_test.dart) | App abre sem login em 320/768/1440 px; carrinho no SharedPreferences; pedido offline salvo no SQLite |
| [`test/quantity_contrast_test.dart`](test/quantity_contrast_test.dart) | Contraste do seletor de quantidade (teste original mantido) |

## Autores

Rafael Araújo Nascimento e Mateus Artur Santos — Faculdade FANS.
