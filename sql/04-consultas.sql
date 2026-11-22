SET search_path TO liga_facom, public;
-- 1. Mercado da rodada aberta (parâmetro: rodada aberta é obtida pelo estado).
CREATE OR REPLACE VIEW visao_mercado AS
SELECT a.atleta_id,a.apelido,c.nome clube,p.nome posicao,s.descricao situacao,ph.preco,
       COALESCE((SELECT avg(ar.pontuacao) FROM atleta_rodada ar WHERE ar.atleta_id=a.atleta_id AND ar.entrou_em_campo),0)::numeric(8,2) media,
       (SELECT ar.pontuacao FROM atleta_rodada ar JOIN rodada r USING(rodada_id) WHERE ar.atleta_id=a.atleta_id AND ar.entrou_em_campo AND r.estado='consolidada' ORDER BY ar.rodada_id DESC LIMIT 1) ultima_pontuacao
FROM atleta a JOIN posicao p ON p.codigo=a.posicao JOIN situacao s ON s.codigo=a.situacao
JOIN clube_rodada cr ON cr.atleta_id=a.atleta_id AND cr.rodada_id=(SELECT min(rodada_id) FROM rodada WHERE estado='aberta')
JOIN clube c USING(clube_id)
JOIN preco_historico ph ON ph.atleta_id=a.atleta_id AND ph.rodada_id=cr.rodada_id
WHERE a.situacao IN ('provavel','duvida');
-- 2. Ranking acumulado por liga; empates compartilham posição.
CREATE OR REPLACE VIEW visao_ranking AS
SELECT l.liga_id,l.nome liga,t.tecnico_id,t.apelido,
       COALESCE(sum(pontos_escalacao(e.escalacao_id)) FILTER(WHERE e.estado='confirmada' AND r.estado='consolidada'),0)::numeric(10,2) pontos,
       rank() OVER(PARTITION BY l.liga_id ORDER BY COALESCE(sum(pontos_escalacao(e.escalacao_id)) FILTER(WHERE e.estado='confirmada' AND r.estado='consolidada'),0) DESC) posicao
FROM liga l JOIN participacao pa USING(liga_id) JOIN tecnico t USING(tecnico_id)
LEFT JOIN escalacao e ON e.tecnico_id=t.tecnico_id LEFT JOIN rodada r ON r.rodada_id=e.rodada_id
GROUP BY l.liga_id,l.nome,t.tecnico_id,t.apelido;
-- 3. Cinco melhores relações média/preço por posição, com 3 aparições.
WITH m AS (SELECT a.atleta_id,a.apelido,a.posicao,avg(ar.pontuacao) FILTER(WHERE ar.entrou_em_campo) media,count(*) FILTER(WHERE ar.entrou_em_campo) jogos
FROM atleta a JOIN atleta_rodada ar USING(atleta_id) JOIN rodada r USING(rodada_id)
WHERE r.estado='consolidada' GROUP BY a.atleta_id,a.apelido,a.posicao HAVING count(*) FILTER(WHERE ar.entrou_em_campo)>=3), atual AS (
SELECT m.*,ph.preco,round(m.media/nullif(ph.preco,0),3) custo_beneficio,row_number() OVER(PARTITION BY m.posicao ORDER BY m.media/nullif(ph.preco,0) DESC) rn
FROM m JOIN preco_historico ph ON ph.atleta_id=m.atleta_id AND ph.rodada_id=(SELECT max(rodada_id) FROM preco_historico WHERE atleta_id=m.atleta_id))
SELECT * FROM atual WHERE rn<=5 ORDER BY posicao,rn;
-- 4. Top da rodada (parâmetro de exemplo: rodada 10); desempate pela confirmação mais antiga.
WITH pontuadas AS (SELECT e.escalacao_id,e.tecnico_id,e.confirmada_em,pontos_escalacao(e.escalacao_id) pontos FROM escalacao e WHERE e.rodada_id=10 AND e.estado='confirmada')
SELECT t.apelido,tf.nome time,p.pontos,a.apelido capitao FROM pontuadas p JOIN tecnico t USING(tecnico_id) JOIN time_fantasy tf USING(tecnico_id)
JOIN escalacao_item i ON i.escalacao_id=p.escalacao_id AND i.capitao JOIN atleta a USING(atleta_id)
ORDER BY p.pontos DESC,p.confirmada_em ASC LIMIT 1;
-- 5. Clube com mais jogos sem sofrer gol nas 5 rodadas consolidadas mais recentes.
WITH ultimas AS (SELECT rodada_id FROM rodada WHERE estado='consolidada' ORDER BY rodada_id DESC LIMIT 5), clean AS (
SELECT c.clube_id,c.nome FROM partida p JOIN ultimas u USING(rodada_id) JOIN clube c ON (c.clube_id=p.mandante_id AND p.gols_visitante=0) OR (c.clube_id=p.visitante_id AND p.gols_mandante=0) WHERE p.valida)
SELECT nome,count(*) jogos_sem_sofrer FROM clean GROUP BY clube_id,nome ORDER BY count(*) DESC,nome LIMIT 1;
-- 6. Atleta mais escolhido como capitão numa liga (parâmetro liga_id=1).
SELECT a.apelido,count(*) vezes FROM participacao pa JOIN escalacao e USING(tecnico_id) JOIN escalacao_item i USING(escalacao_id) JOIN atleta a USING(atleta_id)
WHERE pa.liga_id=1 AND i.capitao GROUP BY a.atleta_id,a.apelido ORDER BY count(*) DESC LIMIT 1;
-- 7. Técnicos que nunca escalaram atletas do clube informado (parâmetro clube_id=1).
SELECT t.tecnico_id,t.apelido FROM tecnico t WHERE NOT EXISTS(
SELECT 1 FROM escalacao e JOIN escalacao_item i USING(escalacao_id) JOIN clube_rodada cr ON cr.atleta_id=i.atleta_id AND cr.rodada_id=e.rodada_id
WHERE e.tecnico_id=t.tecnico_id AND cr.clube_id=1);
-- 8. Atletas sempre acima da média da posição na rodada em que atuaram.
SELECT a.atleta_id,a.apelido FROM atleta a WHERE EXISTS(SELECT 1 FROM atleta_rodada ar JOIN rodada r USING(rodada_id) WHERE ar.atleta_id=a.atleta_id AND ar.entrou_em_campo AND r.estado='consolidada')
AND NOT EXISTS(SELECT 1 FROM atleta_rodada ar JOIN rodada r USING(rodada_id) WHERE ar.atleta_id=a.atleta_id AND ar.entrou_em_campo AND r.estado='consolidada'
AND ar.pontuacao <= (SELECT avg(ar2.pontuacao) FROM atleta_rodada ar2 JOIN atleta a2 USING(atleta_id) WHERE ar2.rodada_id=ar.rodada_id AND ar2.entrou_em_campo AND a2.posicao=a.posicao));
-- 9. Evolução do patrimônio de um técnico (parâmetro tecnico_id=1).
WITH variacoes AS (
 SELECT r.rodada_id,COALESCE(sum(ph.preco-ei.preco_pago),0) variacao
 FROM rodada r LEFT JOIN escalacao e ON e.rodada_id=r.rodada_id AND e.tecnico_id=1 AND e.estado='confirmada'
 LEFT JOIN escalacao_item ei USING(escalacao_id)
 LEFT JOIN preco_historico ph ON ph.atleta_id=ei.atleta_id AND ph.rodada_id=r.rodada_id
 WHERE r.estado='consolidada' GROUP BY r.rodada_id
), historico AS (
 SELECT rodada_id,100.00+sum(variacao) OVER(ORDER BY rodada_id) patrimonio,variacao FROM variacoes
)
SELECT rodada_id,patrimonio,variacao FROM historico ORDER BY rodada_id;
-- 10. Ligas com ao menos 3 técnicos e média por técnico acima da média geral.
WITH pontos AS (SELECT t.tecnico_id,COALESCE(sum(pontos_escalacao(e.escalacao_id)) FILTER(WHERE e.estado='confirmada' AND r.estado='consolidada'),0) pts FROM tecnico t LEFT JOIN escalacao e USING(tecnico_id) LEFT JOIN rodada r USING(rodada_id) GROUP BY t.tecnico_id), geral AS (SELECT avg(pts) m FROM pontos)
SELECT l.liga_id,l.nome,avg(p.pts) media_liga FROM liga l JOIN participacao pa USING(liga_id) JOIN pontos p USING(tecnico_id) GROUP BY l.liga_id,l.nome HAVING count(*)>=3 AND avg(p.pts)>(SELECT m FROM geral);
-- 11. Seleção simplificada: melhor pontuador elegível por posição, preço até C$ 12 (rodada 10).
WITH elegiveis AS (SELECT a.atleta_id,a.apelido,a.posicao,ar.pontuacao,ph.preco,
row_number() OVER(PARTITION BY a.posicao ORDER BY ar.pontuacao DESC,ph.preco ASC,a.apelido) rn
FROM atleta a JOIN atleta_rodada ar USING(atleta_id) JOIN preco_historico ph ON ph.atleta_id=a.atleta_id AND ph.rodada_id=ar.rodada_id
WHERE ar.rodada_id=10 AND ar.entrou_em_campo AND ph.preco<=12)
SELECT apelido,posicao,pontuacao,preco,(SELECT sum(preco) FROM elegiveis WHERE rn=1) custo_total FROM elegiveis WHERE rn=1;
