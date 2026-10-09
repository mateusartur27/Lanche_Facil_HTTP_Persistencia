// API REST do Lanche Fácil publicada como Cloudflare Worker.
//
// Faz o mesmo papel do json-server da pasta api/, mas fica online o tempo todo:
//   GET    /produtos         lista       GET    /pedidos         lista
//   GET    /produtos/{id}    busca um    GET    /pedidos/{id}    busca um
//   POST   /produtos         cria (201)  POST   /pedidos         cria (201)
//   PUT    /produtos/{id}    atualiza    PUT    /pedidos/{id}    atualiza
//   DELETE /produtos/{id}    remove      DELETE /pedidos/{id}    remove
//
// Os registros ficam no Cloudflare D1 (SQLite gerenciado) — o "banco remoto".
//
// Para testar o tratamento de erros do app, basta trocar o endereço da API
// nas Configurações acrescentando um prefixo:
//   .../simular/500            toda requisição responde HTTP 500
//   .../simular/404            toda requisição responde HTTP 404
//   .../simular/json-invalido  os GET respondem um JSON quebrado
//   .../simular/lento          espera 12 s antes de responder (o app desiste em 8 s)

const RESOURCES = new Set(['produtos', 'pedidos']);
const MAX_BODY_BYTES = 64 * 1024;
const MAX_RECORDS = 1000;

/** Cabeçalhos CORS: permitem que o app rodando no navegador acesse a API. */
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Accept',
  'Access-Control-Max-Age': '86400',
};

/** Monta uma resposta JSON com status e CORS. */
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS_HEADERS },
  });
}

/** Lê o corpo da requisição e garante que seja um objeto JSON. */
async function readObject(request) {
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) return { error: json({ erro: 'Corpo muito grande.' }, 413) };
  try {
    const value = JSON.parse(text);
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      return { error: json({ erro: 'Envie um objeto JSON.' }, 400) };
    }
    return { value };
  } catch {
    return { error: json({ erro: 'JSON inválido.' }, 400) };
  }
}

/** Executa o CRUD de /produtos ou /pedidos no banco D1. */
async function handleResource(request, env, resource, id) {
  const db = env.DB;

  if (request.method === 'GET' && !id) {
    const { results } = await db.prepare(`SELECT json FROM ${resource} ORDER BY rowid`).all();
    return json(results.map((row) => JSON.parse(row.json)));
  }

  if (request.method === 'GET') {
    const row = await db.prepare(`SELECT json FROM ${resource} WHERE id = ?`).bind(id).first();
    return row ? json(JSON.parse(row.json)) : json({}, 404);
  }

  if (request.method === 'POST' && !id) {
    const { value, error } = await readObject(request);
    if (error) return error;
    const count = await db.prepare(`SELECT COUNT(*) AS total FROM ${resource}`).first('total');
    if (count >= MAX_RECORDS) return json({ erro: 'Limite de registros atingido.' }, 429);
    const record = { ...value, id: String(value.id ?? crypto.randomUUID()) };
    try {
      await db.prepare(`INSERT INTO ${resource} (id, json) VALUES (?, ?)`)
        .bind(record.id, JSON.stringify(record)).run();
    } catch (err) {
      if (String(err).includes('UNIQUE')) return json({ erro: 'Já existe um registro com este id.' }, 409);
      throw err;
    }
    return json(record, 201);
  }

  if (request.method === 'PUT' && id) {
    const { value, error } = await readObject(request);
    if (error) return error;
    const record = { ...value, id };
    const result = await db.prepare(`UPDATE ${resource} SET json = ? WHERE id = ?`)
      .bind(JSON.stringify(record), id).run();
    return result.meta.changes > 0 ? json(record) : json({}, 404);
  }

  if (request.method === 'DELETE' && id) {
    const result = await db.prepare(`DELETE FROM ${resource} WHERE id = ?`).bind(id).run();
    return result.meta.changes > 0 ? json({}) : json({}, 404);
  }

  return json({ erro: 'Método não permitido.' }, 405);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS_HEADERS });

    const url = new URL(request.url);
    let segments = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);

    // Prefixo /simular/{modo}: respostas de erro controladas para os testes.
    if (segments[0] === 'simular' && segments[1]) {
      const mode = segments[1];
      segments = segments.slice(2);
      const status = Number(mode);
      if (status >= 400 && status <= 599) {
        return json({ erro: `Falha simulada (HTTP ${status})` }, status);
      }
      if (mode === 'json-invalido' && request.method === 'GET') {
        return new Response('{"produtos": [ isto nao e JSON', {
          headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS_HEADERS },
        });
      }
      if (mode === 'lento') await new Promise((resolve) => setTimeout(resolve, 12000));
    }

    if (segments.length === 0) {
      return json({
        api: 'Lanche Fácil',
        recursos: ['/produtos', '/pedidos'],
        metodos: ['GET', 'POST', 'PUT', 'DELETE'],
        testes: ['/simular/500', '/simular/404', '/simular/json-invalido', '/simular/lento'],
      });
    }

    const [resource, id, extra] = segments;
    if (!RESOURCES.has(resource) || extra !== undefined) return json({ erro: 'Recurso não encontrado.' }, 404);

    try {
      return await handleResource(request, env, resource, id);
    } catch (err) {
      console.error('Falha na API', err);
      return json({ erro: 'Erro interno no servidor.' }, 500);
    }
  },
};
