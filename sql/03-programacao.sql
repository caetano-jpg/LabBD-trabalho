SET search_path TO liga_facom, public;

CREATE FUNCTION pontos_atleta(p_atleta BIGINT,p_rodada SMALLINT) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
 SELECT COALESCE(sum(sp.quantidade*st.valor),0)::numeric(8,2)
 FROM scout_partida sp JOIN scout_tipo st ON st.sigla = sp.scout
 JOIN atleta a ON a.atleta_id=sp.atleta_id
 WHERE sp.atleta_id=p_atleta AND sp.rodada_id=p_rodada
   AND (st.posicoes_permitidas IS NULL OR a.posicao=ANY(st.posicoes_permitidas))
$$;
CREATE FUNCTION pontos_escalacao(p_escalacao BIGINT) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
 SELECT COALESCE(sum(ar.pontuacao * CASE WHEN ei.capitao THEN 1.5 ELSE 1 END),0)
        + COALESCE((SELECT CASE WHEN p.gols_mandante=p.gols_visitante THEN 2
                        WHEN p.mandante_id=cr.clube_id AND p.gols_mandante>p.gols_visitante THEN 5
                        WHEN p.visitante_id=cr.clube_id AND p.gols_visitante>p.gols_mandante THEN 5 ELSE 0 END
          FROM escalacao e JOIN escalacao_item i ON i.escalacao_id=e.escalacao_id
          JOIN atleta a ON a.atleta_id=i.atleta_id AND a.posicao='tec'
          JOIN clube_rodada cr ON cr.atleta_id=a.atleta_id AND cr.rodada_id=e.rodada_id
          JOIN partida p ON p.rodada_id=e.rodada_id AND p.valida AND (p.mandante_id=cr.clube_id OR p.visitante_id=cr.clube_id)
          WHERE e.escalacao_id=p_escalacao AND p.gols_mandante IS NOT NULL
          ORDER BY p.partida_id LIMIT 1),0)
 FROM escalacao_item ei JOIN escalacao e USING(escalacao_id)
 JOIN atleta a USING(atleta_id)
 LEFT JOIN atleta_rodada ar ON ar.atleta_id=ei.atleta_id AND ar.rodada_id=e.rodada_id
 WHERE ei.escalacao_id=p_escalacao AND a.posicao<>'tec'
$$;

CREATE FUNCTION validar_item_escalacao() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
 v_escalacao BIGINT; v_rodada SMALLINT; v_estado TEXT; v_estado_rodada TEXT;
 v_situacao TEXT; v_orc NUMERIC; v_patrimonio NUMERIC; v_preco NUMERIC;
BEGIN
 v_escalacao:=COALESCE(NEW.escalacao_id,OLD.escalacao_id);
 SELECT e.rodada_id,e.estado,r.estado INTO v_rodada,v_estado,v_estado_rodada
 FROM escalacao e JOIN rodada r USING(rodada_id) WHERE e.escalacao_id=v_escalacao;
 IF v_estado_rodada IS DISTINCT FROM 'aberta' OR v_estado IS DISTINCT FROM 'edicao' THEN
   RAISE EXCEPTION 'Só é possível alterar atletas de uma escalação em edição durante uma rodada aberta.';
 END IF;
 IF TG_OP <> 'DELETE' THEN
   SELECT situacao INTO v_situacao FROM atleta WHERE atleta_id=NEW.atleta_id;
   IF v_situacao NOT IN ('provavel','duvida') THEN
     RAISE EXCEPTION 'O atleta não está provável nem em dúvida e não pode ser escalado.';
   END IF;
   IF NOT EXISTS(SELECT 1 FROM clube_rodada WHERE atleta_id=NEW.atleta_id AND rodada_id=v_rodada) THEN
     RAISE EXCEPTION 'O atleta não possui clube registrado para esta rodada.';
   END IF;
   SELECT preco INTO v_preco FROM preco_historico WHERE atleta_id=NEW.atleta_id AND rodada_id=v_rodada;
   IF v_preco IS NULL THEN RAISE EXCEPTION 'Não existe preço registrado para este atleta nesta rodada.'; END IF;
   IF NEW.preco_pago <> v_preco THEN
     RAISE EXCEPTION 'O preço pago (C$ %) deve ser o preço atual do atleta (C$ %).',NEW.preco_pago,v_preco;
   END IF;
 END IF;
 SELECT COALESCE(sum(i.preco_pago),0) INTO v_orc FROM escalacao_item i
 WHERE i.escalacao_id=v_escalacao
   AND (TG_OP='INSERT' OR i.atleta_id<>OLD.atleta_id);
 IF TG_OP <> 'DELETE' THEN v_orc:=v_orc+NEW.preco_pago; END IF;
 SELECT t.patrimonio INTO v_patrimonio FROM escalacao e JOIN time_fantasy t USING(tecnico_id)
 WHERE e.escalacao_id=v_escalacao;
 IF v_orc>v_patrimonio THEN
   RAISE EXCEPTION 'Orçamento excedido: custo C$ %, patrimônio C$ %.',v_orc,v_patrimonio;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
CREATE TRIGGER escalacao_item_validacao BEFORE INSERT OR UPDATE OR DELETE ON escalacao_item
FOR EACH ROW EXECUTE FUNCTION validar_item_escalacao();

CREATE FUNCTION validar_scout() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_rodada SMALLINT;
BEGIN
 v_rodada:=COALESCE(NEW.rodada_id,OLD.rodada_id);
 IF EXISTS(SELECT 1 FROM rodada WHERE rodada_id=v_rodada AND estado='consolidada') THEN RAISE EXCEPTION 'Não é permitido alterar scouts de rodada consolidada.'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
CREATE TRIGGER scout_rodada_nao_consolidada BEFORE INSERT OR UPDATE OR DELETE ON scout_partida FOR EACH ROW EXECUTE FUNCTION validar_scout();

CREATE PROCEDURE confirmar_escalacao(p_escalacao BIGINT) LANGUAGE plpgsql AS $$
DECLARE e escalacao%ROWTYPE; s esquema%ROWTYPE; v_gol INT;v_lat INT;v_zag INT;v_mei INT;v_ata INT;v_tec INT;v_cap INT;v_cap_tec INT;v_soma NUMERIC;v_patrimonio NUMERIC;
BEGIN
 SELECT * INTO e FROM escalacao WHERE escalacao_id=p_escalacao FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Escalação não encontrada.'; END IF;
 IF e.estado<>'edicao' OR NOT EXISTS(SELECT 1 FROM rodada WHERE rodada_id=e.rodada_id AND estado='aberta') THEN RAISE EXCEPTION 'A escalação só pode ser confirmada em edição e com a rodada aberta.'; END IF;
 SELECT * INTO s FROM esquema WHERE nome=e.esquema;
 SELECT count(*) FILTER(WHERE a.posicao='gol'),count(*) FILTER(WHERE a.posicao='lat'),count(*) FILTER(WHERE a.posicao='zag'),count(*) FILTER(WHERE a.posicao='mei'),count(*) FILTER(WHERE a.posicao='ata'),count(*) FILTER(WHERE a.posicao='tec'),count(*) FILTER(WHERE i.capitao),count(*) FILTER(WHERE i.capitao AND a.posicao='tec'),COALESCE(sum(i.preco_pago),0)
 INTO v_gol,v_lat,v_zag,v_mei,v_ata,v_tec,v_cap,v_cap_tec,v_soma FROM escalacao_item i JOIN atleta a USING(atleta_id) WHERE i.escalacao_id=p_escalacao;
 IF (v_gol,v_lat,v_zag,v_mei,v_ata,v_tec) IS DISTINCT FROM (s.qtd_gol,s.qtd_lat,s.qtd_zag,s.qtd_mei,s.qtd_ata,s.qtd_tec) THEN RAISE EXCEPTION 'Escalação incompleta ou posições incompatíveis com o esquema %.',e.esquema; END IF;
 IF v_cap<>1 OR v_cap_tec<>0 THEN RAISE EXCEPTION 'Escolha exatamente um capitão entre os 11 atletas; o técnico real não pode ser capitão.'; END IF;
 SELECT patrimonio INTO v_patrimonio FROM time_fantasy WHERE tecnico_id=e.tecnico_id;
 IF v_soma>v_patrimonio THEN RAISE EXCEPTION 'O custo total excede o patrimônio.'; END IF;
 UPDATE escalacao SET estado='confirmada',confirmada_em=clock_timestamp() WHERE escalacao_id=p_escalacao;
END $$;

CREATE PROCEDURE entrar_liga(p_liga BIGINT,p_tecnico BIGINT,p_codigo TEXT DEFAULT NULL) LANGUAGE plpgsql AS $$
DECLARE l liga%ROWTYPE; n INT;
BEGIN
 SELECT * INTO l FROM liga WHERE liga_id=p_liga FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Liga não encontrada.'; END IF;
 IF NOT l.publica AND l.codigo_convite IS DISTINCT FROM p_codigo THEN RAISE EXCEPTION 'Código de convite inválido.'; END IF;
 IF EXISTS(SELECT 1 FROM participacao WHERE liga_id=p_liga AND tecnico_id=p_tecnico) THEN RAISE EXCEPTION 'Este técnico já participa da liga.'; END IF;
 SELECT count(*) INTO n FROM participacao WHERE liga_id=p_liga;
 IF n>=l.limite THEN RAISE EXCEPTION 'A liga já atingiu o limite de participantes.'; END IF;
 INSERT INTO participacao(liga_id,tecnico_id) VALUES(p_liga,p_tecnico);
END $$;

CREATE PROCEDURE consolidar_rodada(p_rodada SMALLINT) LANGUAGE plpgsql AS $$
DECLARE v_estado TEXT;
BEGIN
 SELECT estado INTO v_estado FROM rodada WHERE rodada_id=p_rodada FOR UPDATE;
 IF v_estado IS DISTINCT FROM 'fechada' THEN RAISE EXCEPTION 'A rodada precisa estar fechada e ainda não consolidada.'; END IF;
 -- Persiste scouts calculados e pontos simplificados dos técnicos reais a partir do placar.
 UPDATE atleta_rodada ar SET pontuacao=pontos_atleta(ar.atleta_id,ar.rodada_id) WHERE ar.rodada_id=p_rodada;
 UPDATE atleta_rodada ar SET pontuacao=COALESCE((SELECT CASE WHEN p.gols_mandante=p.gols_visitante THEN 2
                       WHEN p.mandante_id=cr.clube_id AND p.gols_mandante>p.gols_visitante THEN 5
                       WHEN p.visitante_id=cr.clube_id AND p.gols_visitante>p.gols_mandante THEN 5 ELSE 0 END
   FROM clube_rodada cr JOIN partida p ON p.rodada_id=cr.rodada_id AND p.valida AND p.gols_mandante IS NOT NULL AND (p.mandante_id=cr.clube_id OR p.visitante_id=cr.clube_id)
   WHERE cr.atleta_id=ar.atleta_id AND cr.rodada_id=ar.rodada_id ORDER BY p.partida_id LIMIT 1),0)
 FROM atleta a WHERE a.atleta_id=ar.atleta_id AND ar.rodada_id=p_rodada AND a.posicao='tec';
 -- Recalcula o preço a partir do preço-base desta rodada (ou do histórico anterior).
 -- A carga pode ter semeado o preço inicial diretamente na rodada aberta.
 WITH base AS (
   SELECT ar.atleta_id,ar.entrou_em_campo,ar.pontuacao,
          COALESCE(atual.preco,anterior.preco) preco_base,
          COALESCE(media.pontuacao_media,0) media_anterior
   FROM atleta_rodada ar
   LEFT JOIN preco_historico atual ON atual.atleta_id=ar.atleta_id AND atual.rodada_id=p_rodada
   LEFT JOIN LATERAL (SELECT ph.preco FROM preco_historico ph
     WHERE ph.atleta_id=ar.atleta_id AND ph.rodada_id<p_rodada
     ORDER BY ph.rodada_id DESC LIMIT 1) anterior ON TRUE
   LEFT JOIN LATERAL (SELECT avg(x.pontuacao) pontuacao_media FROM atleta_rodada x
     WHERE x.atleta_id=ar.atleta_id AND x.rodada_id<p_rodada AND x.entrou_em_campo) media ON TRUE
   WHERE ar.rodada_id=p_rodada
 ), atualizados AS (
   SELECT atleta_id,CASE WHEN entrou_em_campo THEN
     GREATEST(1.00,round(preco_base+LEAST(1.50,GREATEST(-1.50,0.10*(pontuacao-media_anterior))),2))
     ELSE preco_base END preco_final
   FROM base WHERE preco_base IS NOT NULL
 )
 INSERT INTO preco_historico(atleta_id,rodada_id,preco)
 SELECT atleta_id,p_rodada,preco_final FROM atualizados
 ON CONFLICT(atleta_id,rodada_id) DO UPDATE SET preco=EXCLUDED.preco;
 -- Recalcula patrimônio com a diferença entre preço final e preço pago para os 12 escolhidos.
 UPDATE time_fantasy tf SET patrimonio=tf.patrimonio+COALESCE((SELECT sum(ph.preco-ei.preco_pago)
   FROM escalacao e JOIN escalacao_item ei USING(escalacao_id) JOIN preco_historico ph ON ph.atleta_id=ei.atleta_id AND ph.rodada_id=p_rodada
   WHERE e.tecnico_id=tf.tecnico_id AND e.rodada_id=p_rodada AND e.estado='confirmada'),0)
 WHERE EXISTS(SELECT 1 FROM escalacao WHERE tecnico_id=tf.tecnico_id AND rodada_id=p_rodada AND estado='confirmada');
 UPDATE rodada SET estado='consolidada',consolidada_em=clock_timestamp() WHERE rodada_id=p_rodada;
END $$;
