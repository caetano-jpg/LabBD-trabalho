-- Suporte à criação de uma escalação para o técnico na rodada aberta.
-- As regras de rodada e escalação confirmada permanecem no banco.
SET search_path TO liga_facom, public;

CREATE OR REPLACE FUNCTION obter_ou_criar_escalacao(p_tecnico BIGINT, p_esquema TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_rodada SMALLINT;
  v_escalacao BIGINT;
  v_estado TEXT;
BEGIN
  SELECT rodada_id INTO v_rodada
  FROM rodada
  WHERE estado = 'aberta'
  ORDER BY rodada_id
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não há rodada aberta para montar uma escalação.';
  END IF;

  INSERT INTO escalacao(tecnico_id, rodada_id, esquema)
  VALUES (p_tecnico, v_rodada, p_esquema)
  ON CONFLICT (tecnico_id, rodada_id) DO NOTHING;

  SELECT escalacao_id, estado
    INTO v_escalacao, v_estado
  FROM escalacao
  WHERE tecnico_id = p_tecnico AND rodada_id = v_rodada
  FOR UPDATE;

  IF v_estado <> 'edicao' THEN
    RAISE EXCEPTION 'A escalação desta rodada já está confirmada e não pode ser editada.';
  END IF;

  RETURN v_escalacao;
END;
$$;

-- Confirma a escalação da rodada aberta pertencente ao técnico.
CREATE OR REPLACE PROCEDURE confirmar_escalacao_tecnico(p_tecnico BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rodada SMALLINT;
  v_escalacao BIGINT;
BEGIN
  SELECT rodada_id INTO v_rodada
  FROM rodada
  WHERE estado = 'aberta'
  ORDER BY rodada_id
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não há rodada aberta para confirmar uma escalação.';
  END IF;

  SELECT escalacao_id INTO v_escalacao
  FROM escalacao
  WHERE tecnico_id = p_tecnico AND rodada_id = v_rodada
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'O técnico ainda não montou uma escalação para a rodada aberta.';
  END IF;

  CALL confirmar_escalacao(v_escalacao);
END;
$$;

-- Valida a participação do atleta e atualiza o capitão dentro do banco.
CREATE OR REPLACE PROCEDURE escolher_capitao(p_escalacao BIGINT, p_atleta BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM escalacao_item
    WHERE escalacao_id = p_escalacao AND atleta_id = p_atleta
  ) THEN
    RAISE EXCEPTION 'Esse atleta não está na escalação.';
  END IF;

  UPDATE escalacao_item
  SET capitao = FALSE
  WHERE escalacao_id = p_escalacao AND capitao;

  UPDATE escalacao_item
  SET capitao = TRUE
  WHERE escalacao_id = p_escalacao AND atleta_id = p_atleta;
END;
$$;

-- Administrador: fecha o mercado da única rodada atualmente aberta.
CREATE OR REPLACE PROCEDURE fechar_rodada()
LANGUAGE plpgsql
AS $$
DECLARE
  v_rodada SMALLINT;
BEGIN
  SELECT rodada_id INTO v_rodada
  FROM rodada
  WHERE estado = 'aberta'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não há rodada aberta para fechar o mercado.';
  END IF;

  UPDATE rodada
  SET estado = 'fechada', fechada_em = clock_timestamp()
  WHERE rodada_id = v_rodada;
END;
$$;

-- Administrador: abre a rodada seguinte após a anterior ser consolidada.
-- Reutiliza o último clube conhecido e o preço mais recente como base inicial.
CREATE OR REPLACE PROCEDURE abrir_proxima_rodada()
LANGUAGE plpgsql
AS $$
DECLARE
  v_anterior SMALLINT;
  v_estado TEXT;
  v_proxima SMALLINT;
BEGIN
  IF EXISTS (SELECT 1 FROM rodada WHERE estado = 'aberta') THEN
    RAISE EXCEPTION 'Já existe uma rodada aberta. Feche o mercado antes de abrir outra.';
  END IF;

  SELECT rodada_id, estado INTO v_anterior, v_estado
  FROM rodada
  ORDER BY rodada_id DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Carregue os dados iniciais antes de abrir uma rodada.';
  END IF;
  IF v_estado <> 'consolidada' THEN
    RAISE EXCEPTION 'A rodada % precisa ser consolidada antes de abrir a próxima.', v_anterior;
  END IF;
  IF v_anterior >= 38 THEN
    RAISE EXCEPTION 'O campeonato já atingiu o limite de 38 rodadas.';
  END IF;

  v_proxima := v_anterior + 1;
  INSERT INTO rodada(rodada_id, estado, aberta_em)
  VALUES (v_proxima, 'aberta', clock_timestamp());

  INSERT INTO clube_rodada(atleta_id, rodada_id, clube_id)
  SELECT atleta_id, v_proxima, clube_id
  FROM clube_rodada
  WHERE rodada_id = v_anterior
  ON CONFLICT (atleta_id, rodada_id) DO NOTHING;

  INSERT INTO preco_historico(atleta_id, rodada_id, preco)
  SELECT DISTINCT ON (atleta_id) atleta_id, v_proxima, preco
  FROM preco_historico
  WHERE rodada_id <= v_anterior
  ORDER BY atleta_id, rodada_id DESC
  ON CONFLICT (atleta_id, rodada_id) DO NOTHING;
END;
$$;
