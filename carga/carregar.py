"""Carga idempotente dos JSON salvos da API Cartola para PostgreSQL 16+.
Uso: python carga/carregar.py --dados carga/dados
Exige que 01-ddl.sql, 02-dados.sql e 03-programacao.sql tenham sido executados.
"""
import argparse
import json
import os
from pathlib import Path
import psycopg
from psycopg.rows import dict_row

POS_FALLBACK = {1: "gol", 2: "lat", 3: "zag", 4: "mei", 5: "ata", 6: "tec"}
STATUS_NOME = {
    "provável": "provavel", "provavel": "provavel", "dúvida": "duvida", "duvida": "duvida",
    "suspenso": "suspenso", "contundido": "contundido", "nulo": "nulo",
}


def ler(pasta: Path, arquivo: str):
    caminho = pasta / arquivo
    if not caminho.is_file():
        raise FileNotFoundError(f"Arquivo JSON não encontrado: {caminho}")
    return json.loads(caminho.read_text(encoding="utf-8"))


def inserir_clubes(cur, clubes):
    if isinstance(clubes, list):
        pares = [(c.get("id"), c) for c in clubes]
    else:
        pares = [(int(k), v) for k, v in clubes.items()]
    for fonte_id, c in pares:
        if fonte_id is None:
            continue
        abreviacao = (c.get("abreviacao") or f"C{int(fonte_id):02d}")[:3].upper()
        escudos = c.get("escudos") or {}
        cur.execute("""INSERT INTO liga_facom.clube(fonte_id,nome,abreviacao,escudo_url)
          VALUES (%s,%s,%s,%s) ON CONFLICT(fonte_id) DO UPDATE
          SET nome=EXCLUDED.nome,abreviacao=EXCLUDED.abreviacao,escudo_url=EXCLUDED.escudo_url""",
          (int(fonte_id), c.get("nome_fantasia") or c.get("nome") or f"Clube {fonte_id}", abreviacao, escudos.get("60x60") or escudos.get("45x45")))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dados", type=Path, default=Path(__file__).parent / "dados")
    args = parser.parse_args()
    pasta = args.dados.resolve()
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        raise SystemExit("Defina DATABASE_URL com a conexão PostgreSQL.")

    mercado = ler(pasta, "atletas_mercado.json")
    esquemas = ler(pasta, "esquemas.json")
    status_data = ler(pasta, "mercado_status.json")
    rodadas = []
    for n in range(1, 39):
        if (pasta / f"partidas_{n}.json").exists() and (pasta / f"pontuados_{n}.json").exists():
            rodadas.append(n)
    if len(rodadas) < 10:
        raise SystemExit(f"Foram encontrados dados de apenas {len(rodadas)} rodadas; são necessárias pelo menos 10.")

    pos_por_id = dict(POS_FALLBACK)
    for k, item in (mercado.get("posicoes") or {}).items():
        abreviacao = item.get("abreviacao")
        if abreviacao:
            pos_por_id[int(item.get("id", k))] = abreviacao.lower()
    status_por_id = {}
    for k, item in (mercado.get("status") or {}).items():
        nome = STATUS_NOME.get((item.get("nome") or "").strip().lower())
        if nome:
            status_por_id[int(item.get("id", k))] = nome

    with psycopg.connect(dsn, row_factory=dict_row) as conn:
      with conn.cursor() as cur:
        cur.execute("SET search_path TO liga_facom, public")
        # Dicionários de domínio ligados aos identificadores da API.
        for pid, codigo in pos_por_id.items():
            nome = next((v.get("nome") for k,v in (mercado.get("posicoes") or {}).items() if int(v.get("id", k)) == pid), codigo.upper())
            cur.execute("""INSERT INTO liga_facom.posicao(codigo,nome,fonte_id) VALUES (%s,%s,%s)
                ON CONFLICT(codigo) DO UPDATE SET nome=EXCLUDED.nome,fonte_id=EXCLUDED.fonte_id""", (codigo,nome,pid))
        for sid, codigo in status_por_id.items():
            nome = next((v.get("nome") for k,v in (mercado.get("status") or {}).items() if int(v.get("id", k)) == sid), codigo)
            cur.execute("""INSERT INTO liga_facom.situacao(codigo,descricao,fonte_id) VALUES (%s,%s,%s)
                ON CONFLICT(codigo) DO UPDATE SET descricao=EXCLUDED.descricao,fonte_id=EXCLUDED.fonte_id""", (codigo,nome,sid))

        inserir_clubes(cur, mercado.get("clubes") or {})
        # Também carrega atletas antigos que aparecem apenas nos JSON de pontuados.
        for rodada in rodadas:
            partidas_json = ler(pasta, f"partidas_{rodada}.json")
            pontos_json = ler(pasta, f"pontuados_{rodada}.json")
            inserir_clubes(cur, partidas_json.get("clubes") or {})
            cur.execute("""INSERT INTO liga_facom.rodada(rodada_id,estado) VALUES (%s,'fechada')
                ON CONFLICT(rodada_id) DO UPDATE SET estado='fechada'""", (rodada,))
            partidas = partidas_json.get("partidas") or []
            partida_por_clube = {}
            for p in partidas:
                partida_id = p.get("partida_id") or p.get("id")
                mandante = p.get("clube_casa_id")
                visitante = p.get("clube_visitante_id")
                if not partida_id or not mandante or not visitante:
                    continue
                ts = p.get("timestamp")
                cur.execute("""INSERT INTO liga_facom.partida
                    (fonte_id,rodada_id,mandante_id,visitante_id,local,inicio,gols_mandante,gols_visitante,valida)
                    SELECT %s,%s,c1.clube_id,c2.clube_id,%s,
                           CASE WHEN %s IS NULL THEN NULL ELSE to_timestamp(%s) END,%s,%s,%s
                    FROM liga_facom.clube c1,liga_facom.clube c2
                    WHERE c1.fonte_id=%s AND c2.fonte_id=%s
                    ON CONFLICT(fonte_id) DO UPDATE SET rodada_id=EXCLUDED.rodada_id,
                    mandante_id=EXCLUDED.mandante_id,visitante_id=EXCLUDED.visitante_id,local=EXCLUDED.local,
                    inicio=EXCLUDED.inicio,gols_mandante=EXCLUDED.gols_mandante,
                    gols_visitante=EXCLUDED.gols_visitante,valida=EXCLUDED.valida""",
                    (int(partida_id),rodada,p.get("local"),ts,ts,p.get("placar_oficial_mandante"),p.get("placar_oficial_visitante"),bool(p.get("valida", True)),int(mandante),int(visitante)))
                cur.execute("SELECT partida_id FROM liga_facom.partida WHERE fonte_id=%s", (int(partida_id),))
                linha = cur.fetchone()
                if linha:
                    partida_por_clube[int(mandante)] = linha["partida_id"]
                    partida_por_clube[int(visitante)] = linha["partida_id"]

            atletas_pontuados = pontos_json.get("atletas") or {}
            for fonte_id, a in atletas_pontuados.items():
                pos = pos_por_id.get(int(a.get("posicao_id") or 0), "mei")
                status = status_por_id.get(int(a.get("status_id") or 0), "nulo")
                apelido = a.get("apelido") or f"Atleta {fonte_id}"
                nome = a.get("nome") or apelido
                cur.execute("""INSERT INTO liga_facom.atleta(fonte_id,nome,apelido,posicao,situacao)
                    VALUES (%s,%s,%s,%s,%s) ON CONFLICT(fonte_id) DO UPDATE SET
                    nome=CASE WHEN EXCLUDED.nome=EXCLUDED.apelido THEN liga_facom.atleta.nome ELSE EXCLUDED.nome END,
                    apelido=EXCLUDED.apelido,posicao=EXCLUDED.posicao RETURNING atleta_id""",
                    (int(fonte_id),nome,apelido,pos,status))
                atleta_id = cur.fetchone()["atleta_id"]
                cur.execute("""INSERT INTO liga_facom.atleta_rodada(atleta_id,rodada_id,entrou_em_campo,pontuacao)
                    VALUES (%s,%s,%s,0) ON CONFLICT(atleta_id,rodada_id) DO UPDATE
                    SET entrou_em_campo=EXCLUDED.entrou_em_campo""",
                    (atleta_id,rodada,bool(a.get("entrou_em_campo", False))))
                club_id = a.get("clube_id")
                if club_id:
                    cur.execute("""INSERT INTO liga_facom.clube_rodada(atleta_id,rodada_id,clube_id)
                      SELECT %s,%s,clube_id FROM liga_facom.clube WHERE fonte_id=%s
                      ON CONFLICT(atleta_id,rodada_id) DO UPDATE SET clube_id=EXCLUDED.clube_id""", (atleta_id,rodada,int(club_id)))
                match_id = partida_por_clube.get(int(club_id)) if club_id else None
                scouts = a.get("scout") or {}
                if match_id:
                    for sigla, quantidade in scouts.items():
                        cur.execute("SELECT 1 FROM liga_facom.scout_tipo WHERE sigla=%s", (sigla,))
                        if cur.fetchone() and quantidade:
                            cur.execute("""INSERT INTO liga_facom.scout_partida(atleta_id,rodada_id,partida_id,scout,quantidade)
                                VALUES (%s,%s,%s,%s,%s) ON CONFLICT(atleta_id,partida_id,scout)
                                DO UPDATE SET quantidade=EXCLUDED.quantidade""",
                                (atleta_id,rodada,match_id,sigla,int(quantidade)))
            # Atualiza pontuação armazenada a partir dos scouts e seus valores.
            cur.execute("""UPDATE liga_facom.atleta_rodada ar SET pontuacao=COALESCE((
                SELECT sum(sp.quantidade*st.valor) FROM liga_facom.scout_partida sp
                JOIN liga_facom.scout_tipo st USING(scout) JOIN liga_facom.atleta a USING(atleta_id)
                WHERE sp.atleta_id=ar.atleta_id AND sp.rodada_id=ar.rodada_id
                AND (st.posicoes_permitidas IS NULL OR a.posicao=ANY(st.posicoes_permitidas))),0)
                WHERE ar.rodada_id=%s""", (rodada,))
            # Regra do trabalho para técnicos reais: pontos calculados do placar.
            cur.execute("""UPDATE liga_facom.atleta_rodada ar SET pontuacao=COALESCE((
                SELECT CASE WHEN (p.mandante_id=cr.clube_id AND p.gols_mandante>p.gols_visitante)
                                  OR (p.visitante_id=cr.clube_id AND p.gols_visitante>p.gols_mandante) THEN 5
                            WHEN p.gols_mandante=p.gols_visitante THEN 2 ELSE 0 END
                FROM liga_facom.clube_rodada cr JOIN liga_facom.partida p ON p.rodada_id=cr.rodada_id
                AND (p.mandante_id=cr.clube_id OR p.visitante_id=cr.clube_id)
                WHERE cr.atleta_id=ar.atleta_id AND cr.rodada_id=ar.rodada_id AND p.valida
                ORDER BY p.partida_id LIMIT 1),0)
                FROM liga_facom.atleta a WHERE a.atleta_id=ar.atleta_id AND a.posicao='tec' AND ar.rodada_id=%s""", (rodada,))

        # Dados atuais do mercado: atualiza cadastro e clubes da próxima rodada.
        prox = max(rodadas) + 1
        if prox <= 38:
            cur.execute("INSERT INTO liga_facom.rodada(rodada_id,estado) VALUES (%s,'aberta') ON CONFLICT(rodada_id) DO UPDATE SET estado='aberta'", (prox,))
            for a in mercado.get("atletas") or []:
                fonte_id = a.get("atleta_id")
                if fonte_id is None:
                    continue
                pos = pos_por_id.get(int(a.get("posicao_id") or 0), "mei")
                status = status_por_id.get(int(a.get("status_id") or 0), "nulo")
                apelido = a.get("apelido") or f"Atleta {fonte_id}"
                cur.execute("""INSERT INTO liga_facom.atleta(fonte_id,nome,apelido,posicao,situacao)
                    VALUES (%s,%s,%s,%s,%s) ON CONFLICT(fonte_id) DO UPDATE SET nome=EXCLUDED.nome,
                    apelido=EXCLUDED.apelido,posicao=EXCLUDED.posicao,situacao=EXCLUDED.situacao RETURNING atleta_id""",
                    (int(fonte_id),a.get("nome") or apelido,apelido,pos,status))
                atleta_id=cur.fetchone()["atleta_id"]
                clube_fonte=a.get("clube_id")
                if clube_fonte:
                    cur.execute("""INSERT INTO liga_facom.clube_rodada(atleta_id,rodada_id,clube_id)
                    SELECT %s,%s,clube_id FROM liga_facom.clube WHERE fonte_id=%s
                    ON CONFLICT(atleta_id,rodada_id) DO UPDATE SET clube_id=EXCLUDED.clube_id""",(atleta_id,prox,int(clube_fonte)))
        # Cadastra formações a partir da resposta real, preservando os sete esquemas.
        for e in esquemas:
            nome=e.get("nome")
            q=e.get("posicoes") or {}
            if nome:
                cur.execute("""INSERT INTO liga_facom.esquema(nome,qtd_gol,qtd_lat,qtd_zag,qtd_mei,qtd_ata,qtd_tec)
                  VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT(nome) DO UPDATE SET
                  qtd_gol=EXCLUDED.qtd_gol,qtd_lat=EXCLUDED.qtd_lat,qtd_zag=EXCLUDED.qtd_zag,
                  qtd_mei=EXCLUDED.qtd_mei,qtd_ata=EXCLUDED.qtd_ata,qtd_tec=EXCLUDED.qtd_tec""",
                  (nome,q.get("gol",1),q.get("lat",0),q.get("zag",0),q.get("mei",0),q.get("ata",0),q.get("tec",1)))

        # A carga simula a liga desde a primeira rodada: o preço observado no mercado
        # no momento da carga é o preço inicial; daí em diante a regra do banco o altera.
        cur.execute("DELETE FROM liga_facom.preco_historico WHERE rodada_id BETWEEN %s AND %s", (min(rodadas), max(rodadas)))
        cur.execute("""INSERT INTO liga_facom.preco_historico(atleta_id,rodada_id,preco)
          SELECT a.atleta_id,1,GREATEST(1,COALESCE(m.preco_num,1))
          FROM liga_facom.atleta a LEFT JOIN LATERAL (
            SELECT (x->>'preco_num')::numeric preco_num FROM jsonb_array_elements(%s::jsonb) x
            WHERE (x->>'atleta_id')::bigint=a.fonte_id LIMIT 1
          ) m ON TRUE
          ON CONFLICT(atleta_id,rodada_id) DO UPDATE SET preco=EXCLUDED.preco""", (json.dumps(mercado.get("atletas") or []),))
        # Reprocessa rodadas em ordem, gerando pontuação e preços históricos pelo modelo da liga.
        for rodada in rodadas:
            cur.execute("UPDATE liga_facom.rodada SET estado='fechada' WHERE rodada_id=%s", (rodada,))
            cur.execute("CALL liga_facom.consolidar_rodada(%s)", (rodada,))
        # Abre uma rodada de demonstração e leva o preço consolidado mais recente.
        if prox <= 38:
            cur.execute("""INSERT INTO liga_facom.preco_historico(atleta_id,rodada_id,preco)
              SELECT a.atleta_id,%s,COALESCE((SELECT ph.preco FROM liga_facom.preco_historico ph
                WHERE ph.atleta_id=a.atleta_id AND ph.rodada_id<=%s ORDER BY ph.rodada_id DESC LIMIT 1),1)
              FROM liga_facom.atleta a ON CONFLICT(atleta_id,rodada_id) DO UPDATE SET preco=EXCLUDED.preco""", (prox,max(rodadas)))
        conn.commit()
    print(f"Carga concluída: {len(rodadas)} rodadas, {pasta}")
    print("Os preços atuais foram usados como orçamento inicial da próxima rodada de demonstração.")


if __name__ == "__main__":
    main()
