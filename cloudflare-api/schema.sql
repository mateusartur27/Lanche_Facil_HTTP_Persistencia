-- Banco remoto (Cloudflare D1) usado pela API REST do Lanche Fácil.
-- Cada linha guarda o JSON completo do registro, como o json-server faz com o db.json.
-- Executar de novo este arquivo volta o servidor ao cardápio inicial:
--   npx wrangler d1 execute lanche-facil-db --remote --file schema.sql
DROP TABLE IF EXISTS produtos;
DROP TABLE IF EXISTS pedidos;

CREATE TABLE produtos (
  id TEXT PRIMARY KEY,
  json TEXT NOT NULL
);

CREATE TABLE pedidos (
  id TEXT PRIMARY KEY,
  json TEXT NOT NULL
);

INSERT INTO produtos (id, json) VALUES
('cachorro-quente', '{"id":"cachorro-quente","estabelecimentoId":"campus-principal","nome":"Cachorro-quente","descricao":"Pão, salsicha, molho, milho, batata palha e complementos.","preco":1400,"categoria":"Lanches","ativo":true,"disponivel":true,"estoque":18,"imagemUrl":null,"ajusteImagem":"contain","criadoEm":"2026-08-16T00:00:00.000","atualizadoEm":"2026-08-16T00:00:00.000"}'),
('refrigerante', '{"id":"refrigerante","estabelecimentoId":"campus-principal","nome":"Refrigerante lata","descricao":"Lata de 350 ml servida gelada.","preco":600,"categoria":"Bebidas","ativo":true,"disponivel":true,"estoque":24,"imagemUrl":null,"ajusteImagem":"contain","criadoEm":"2026-08-16T00:00:00.000","atualizadoEm":"2026-08-16T00:00:00.000"}'),
('salgado', '{"id":"salgado","estabelecimentoId":"campus-principal","nome":"Salgado assado","descricao":"Opções de frango, presunto e queijo conforme disponibilidade.","preco":900,"categoria":"Salgados","ativo":true,"disponivel":true,"estoque":30,"imagemUrl":null,"ajusteImagem":"contain","criadoEm":"2026-08-16T00:00:00.000","atualizadoEm":"2026-08-16T00:00:00.000"}'),
('trident', '{"id":"trident","estabelecimentoId":"campus-principal","nome":"Trident","descricao":"Goma de mascar em sabores variados.","preco":350,"categoria":"Conveniência","ativo":true,"disponivel":true,"estoque":40,"imagemUrl":null,"ajusteImagem":"contain","criadoEm":"2026-08-16T00:00:00.000","atualizadoEm":"2026-08-16T00:00:00.000"}'),
('x-salada', '{"id":"x-salada","estabelecimentoId":"campus-principal","nome":"X-Salada especial","descricao":"Hambúrguer, queijo, salada fresca e molho da casa.","preco":1800,"categoria":"Lanches","ativo":true,"disponivel":true,"estoque":15,"imagemUrl":null,"ajusteImagem":"contain","criadoEm":"2026-08-16T00:00:00.000","atualizadoEm":"2026-08-16T00:00:00.000"}');
