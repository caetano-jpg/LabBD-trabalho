# Mapeamento relacional da Liga FACOM Fantasy

## Relações

- `tecnico(tecnico_id PK, nome, email UK, apelido, cadastrado_em)` - entidade forte.
- `time_fantasy(tecnico_id PK/FK -> tecnico, nome UK, patrimonio)` - relação 1:1; chave do técnico reaproveitada.
- `clube(clube_id PK, fonte_id UK, nome UK, abreviacao UK, escudo_url)` - entidade forte. ID interno como PK e ID externo como candidata evita acoplar a identidade local à fonte.
- `posicao(codigo PK, nome UK, fonte_id UK)` e `situacao(codigo PK, descricao UK, fonte_id UK)` - domínios de referência.
- `atleta(atleta_id PK, fonte_id UK, nome, apelido, posicao FK, situacao FK)` - entidade forte; transferências não alteram identidade do atleta.
- `rodada(rodada_id PK, estado, timestamps)` - entidade forte identificada pelo número da competição.
- `clube_rodada(atleta_id PK/FK -> atleta, rodada_id PK/FK -> rodada, clube_id FK -> clube)` - relacionamento temporal atleta-clube com chave composta.
- `partida(partida_id PK, fonte_id UK, rodada_id FK, mandante_id FK, visitante_id FK, local, inicio, gols_mandante, gols_visitante, valida)` - entidade forte.
- `scout_tipo(sigla PK, descricao UK, valor, posicoes_permitidas)` - entidade de catálogo.
- `atleta_rodada(atleta_id PK/FK, rodada_id PK/FK, entrou_em_campo, pontuacao)` - associação de atleta e rodada; pontuação materializada para congelar consolidação e facilitar consultas.
- `scout_partida(atleta_id PK/FK, rodada_id FK, partida_id PK/FK, scout PK/FK, quantidade)` - associação ternária atleta-partida-scout com atributo quantidade.
- `esquema(nome PK, qtd_gol, qtd_lat, qtd_zag, qtd_mei, qtd_ata, qtd_tec)` - entidade forte.
- `escalacao(escalacao_id PK, tecnico_id FK, rodada_id FK, esquema FK, estado, confirmada_em; UK(tecnico_id, rodada_id))` - entidade associativa com atributos próprios.
- `escalacao_item(escalacao_id PK/FK, atleta_id PK/FK, preco_pago, capitao)` - relacionamento N:N com atributos.
- `preco_historico(atleta_id PK/FK, rodada_id PK/FK, preco)` - relacionamento temporal atleta-rodada.
- `liga(liga_id PK, dono_id FK, nome, descricao, codigo_convite UK, limite, publica)` - entidade forte.
- `participacao(liga_id PK/FK, tecnico_id PK/FK, entrou_em)` - relacionamento N:N com atributo data.

## Decisões de mapeamento

Os identificadores internos são chaves primárias substitutas; os números da API são chaves candidatas `UNIQUE NOT NULL`. Assim, uma mudança na API não troca as FKs internas, e a carga continua idempotente pelo ID externo. A pontuação do atleta fica materializada em `atleta_rodada` porque a consolidação precisa congelar resultados; o cálculo é refeito a partir dos scouts antes de fechar a rodada.

O clube do atleta é representado por `clube_rodada`, não como atributo mutável em `atleta`, para preservar transferências. `preco_historico` conserva o preço por rodada. A posição e situação ficam normalizadas em tabelas de domínio. Quantidades de cada posição no esquema ficam como colunas porque são um conjunto fixo de seis categorias exigido diretamente pela regra.

## Regras fora do alcance declarativo do DER/DDL

Precisam de procedimento/gatilho: no máximo uma rodada aberta (também protegido por índice parcial); transições abertas -> fechadas -> consolidadas; confirmação de escalação completa segundo o esquema; capitão dentre os jogadores de linha; estado de mercado e situação elegível; orçamento baseado no patrimônio atual; pontuação derivada dos scouts e regra por posição; preço valorizado e patrimônio; convite privado e limite de participantes; consistência de participações e dono da liga. As restrições simples (unicidade, domínios e limites) ficam em PK/FK/UNIQUE/CHECK/NOT NULL.
