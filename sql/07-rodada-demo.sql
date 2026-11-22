-- Fixture opcional para testar a rodada 11 da aplicação.
-- Replica na rodada 11 os jogos, participações e scouts da rodada 10 já carregada.
-- Estes registros são SIMULADOS para demonstração; não são uma nova coleta da API.
-- Execute somente com a rodada 11 aberta e pelo menos três escalações confirmadas.
-- docker exec -i lbd-postgres psql -U lbd -d lbd -v ON_ERROR_STOP=1 -f /tmp/07-rodada-demo.sql

BEGIN;
SET search_path TO liga_facom, public;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM rodada WHERE rodada_id=10 AND estado='consolidada') THEN
    RAISE EXCEPTION 'A rodada 10 precisa estar consolidada para servir de base ao fixture.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM rodada WHERE rodada_id=11 AND estado='aberta') THEN
    RAISE EXCEPTION 'A rodada 11 precisa estar aberta para receber o fixture.';
  END IF;
  IF EXISTS (SELECT 1 FROM partida WHERE rodada_id=11 AND partida_id > 0) THEN
    RAISE EXCEPTION 'A rodada 11 já contém partidas reais; o fixture não será aplicado.';
  END IF;
  IF (SELECT count(*) FROM escalacao WHERE rodada_id=11 AND estado='confirmada') < 3 THEN
    RAISE EXCEPTION 'Confirme pelo menos três escalações da rodada 11 antes de preparar a demonstração.';
  END IF;
END;
$$;

-- IDs negativos distinguem claramente partidas de demonstração das partidas da API.
INSERT INTO partida(partida_id,fonte_id,rodada_id,mandante_id,visitante_id,local,inicio,
                    gols_mandante,gols_visitante,valida)
SELECT -p.partida_id,-abs(p.fonte_id),11,p.mandante_id,p.visitante_id,p.local,p.inicio,
       p.gols_mandante,p.gols_visitante,p.valida
FROM partida p
WHERE p.rodada_id=10
ON CONFLICT DO NOTHING;

-- A rodada simulada usa a composição de clubes registrada para cada atleta na rodada 10.
INSERT INTO clube_rodada(atleta_id,rodada_id,clube_id)
SELECT atleta_id,11,clube_id
FROM clube_rodada
WHERE rodada_id=10
ON CONFLICT(atleta_id,rodada_id) DO UPDATE SET clube_id=EXCLUDED.clube_id;

INSERT INTO atleta_rodada(atleta_id,rodada_id,entrou_em_campo,pontuacao)
SELECT atleta_id,11,entrou_em_campo,0
FROM atleta_rodada
WHERE rodada_id=10
ON CONFLICT(atleta_id,rodada_id) DO UPDATE
SET entrou_em_campo=EXCLUDED.entrou_em_campo,pontuacao=0;

INSERT INTO scout_partida(atleta_id,rodada_id,partida_id,scout,quantidade)
SELECT atleta_id,11,-partida_id,scout,quantidade
FROM scout_partida
WHERE rodada_id=10
ON CONFLICT(atleta_id,partida_id,scout) DO UPDATE SET quantidade=EXCLUDED.quantidade;

COMMIT;
