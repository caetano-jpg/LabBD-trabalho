"""Aplicação de terminal da Liga FACOM Fantasy (PostgreSQL 16+)."""
import os
from decimal import Decimal
import psycopg
from psycopg.rows import dict_row


def linha(conn, sql, params=()):
    return conn.execute(sql, params).fetchone()


def linhas(conn, sql, params=()):
    return conn.execute(sql, params).fetchall()


def exigir_tecnico(atual):
    if atual is None:
        raise ValueError("Escolha ou cadastre um técnico primeiro (opção 1 ou 2).")
    return atual


def escolher_tecnico(conn):
    for t in linhas(conn, "SELECT tecnico_id, apelido, nome FROM liga_facom.tecnico ORDER BY tecnico_id"):
        print(f"{t['tecnico_id']}: {t['apelido']} — {t['nome']}")
    tecnico = int(input("ID do técnico: ").strip())
    t = linha(conn, "SELECT tecnico_id, apelido FROM liga_facom.tecnico WHERE tecnico_id=%s", (tecnico,))
    if not t:
        raise ValueError("Técnico não encontrado.")
    print(f"Técnico ativo: {t['apelido']} (ID {t['tecnico_id']}).")
    return t['tecnico_id']


def cadastrar_tecnico(conn):
    nome = input("Nome: ").strip()
    email = input("E-mail: ").strip()
    apelido = input("Apelido: ").strip()
    time = input("Nome do time: ").strip()
    with conn.transaction():
        t = linha(conn, """INSERT INTO liga_facom.tecnico(nome,email,apelido)
            VALUES (%s,%s,%s) RETURNING tecnico_id""", (nome, email, apelido))
        conn.execute("INSERT INTO liga_facom.time_fantasy(tecnico_id,nome) VALUES (%s,%s)", (t['tecnico_id'], time))
    print(f"Cadastro criado. Técnico ativo: ID {t['tecnico_id']}.")
    return t['tecnico_id']


def mostrar_mercado(conn, filtrar=True):
    pos = clube = ""
    preco_max = None
    if filtrar:
        pos = input("Posição (gol/lat/zag/mei/ata/tec; Enter = todas): ").strip().lower()
        rotulos = {"gol": "Goleiro", "lat": "Lateral", "zag": "Zagueiro",
                   "mei": "Meia", "ata": "Atacante", "tec": "Técnico"}
        pos = rotulos.get(pos, pos)
        clube = input("Clube (parte do nome; Enter = todos): ").strip()
        entrada = input("Preço máximo (Enter = sem limite): ").strip().replace(",", ".")
        preco_max = Decimal(entrada) if entrada else None
    rows = linhas(conn, """SELECT atleta_id,apelido,clube,posicao,situacao,preco,media,ultima_pontuacao
        FROM liga_facom.visao_mercado
        WHERE (%s = '' OR posicao = %s)
          AND (%s = '' OR clube ILIKE %s)
          AND (%s::numeric IS NULL OR preco <= %s::numeric)
        ORDER BY posicao,apelido""",
        (pos, pos, clube, f"%{clube}%", preco_max, preco_max))
    if not rows:
        print("Nenhum atleta encontrado com esses filtros.")
        return False
    for r in rows:
        print(f"ID {r['atleta_id']} | {r['apelido']} | {r['clube']} | {r['posicao']} | "
              f"{r['situacao']} | C$ {r['preco']} | média {r['media']} | última {r['ultima_pontuacao']}")
    return True


def criar_liga(conn, tecnico):
    tecnico = exigir_tecnico(tecnico)
    nome = input("Nome da liga: ").strip()
    codigo = input("Código de convite: ").strip()
    limite = int(input("Limite de participantes: ").strip())
    publica = input("Pública? (s/n): ").strip().lower() == 's'
    with conn.transaction():
        r = linha(conn, """INSERT INTO liga_facom.liga(dono_id,nome,codigo_convite,limite,publica)
            VALUES (%s,%s,%s,%s,%s) RETURNING liga_id""", (tecnico,nome,codigo,limite,publica))
    print(f"Liga criada. ID {r['liga_id']}.")


def entrar_liga(conn, tecnico):
    tecnico = exigir_tecnico(tecnico)
    for l in linhas(conn, "SELECT liga_id,nome,publica FROM liga_facom.liga ORDER BY liga_id"):
        print(f"{l['liga_id']}: {l['nome']} ({'pública' if l['publica'] else 'privada'})")
    liga = int(input("ID da liga: ").strip())
    codigo = input("Código de convite (deixe vazio se pública): ").strip() or None
    with conn.transaction():
        conn.execute("CALL liga_facom.entrar_liga(%s,%s,%s)", (liga,tecnico,codigo))
    print("Entrada registrada.")


def ranking(conn, por_rodada=False):
    liga = int(input("ID da liga: ").strip())
    if por_rodada:
        rodada = int(input("Número da rodada: ").strip())
        rows = linhas(conn, """SELECT t.apelido,tf.nome AS time,
            liga_facom.pontos_escalacao(e.escalacao_id) AS pontos,
            rank() OVER(ORDER BY liga_facom.pontos_escalacao(e.escalacao_id) DESC) AS posicao
            FROM liga_facom.participacao pa
            JOIN liga_facom.tecnico t ON t.tecnico_id=pa.tecnico_id
            JOIN liga_facom.time_fantasy tf ON tf.tecnico_id=t.tecnico_id
            JOIN liga_facom.escalacao e ON e.tecnico_id=t.tecnico_id AND e.rodada_id=%s AND e.estado='confirmada'
            JOIN liga_facom.rodada r ON r.rodada_id=e.rodada_id AND r.estado='consolidada'
            WHERE pa.liga_id=%s ORDER BY pontos DESC,t.apelido""", (rodada,liga))
    else:
        rows = linhas(conn, """SELECT vr.apelido, tf.nome AS time, vr.pontos, vr.posicao
            FROM liga_facom.visao_ranking vr
            JOIN liga_facom.tecnico t ON t.tecnico_id = vr.tecnico_id
            JOIN liga_facom.time_fantasy tf ON tf.tecnico_id = t.tecnico_id
            WHERE vr.liga_id = %s
            ORDER BY vr.posicao, vr.apelido""", (liga,))
    if not rows:
        print("Ainda não há escalações confirmadas/consolidadas para esse ranking.")
    for r in rows:
        print(dict(r))


def montar_ou_editar(conn, tecnico):
    tecnico = exigir_tecnico(tecnico)
    rodada = linha(conn, "SELECT rodada_id FROM liga_facom.rodada WHERE estado='aberta' ORDER BY rodada_id LIMIT 1")
    atual = None
    if rodada:
        atual = linha(conn, "SELECT escalacao_id,esquema FROM liga_facom.escalacao WHERE tecnico_id=%s AND rodada_id=%s", (tecnico,rodada['rodada_id']))
    if atual:
        esquema = atual['esquema']
    else:
        esquemas = linhas(conn, "SELECT nome,qtd_gol,qtd_lat,qtd_zag,qtd_mei,qtd_ata,qtd_tec FROM liga_facom.esquema ORDER BY nome")
        for e in esquemas:
            print(f"{e['nome']}: gol {e['qtd_gol']}, lat {e['qtd_lat']}, zag {e['qtd_zag']}, mei {e['qtd_mei']}, ata {e['qtd_ata']}, técnico {e['qtd_tec']}")
        esquema = input("Esquema: ").strip()
    with conn.transaction():
        eid = linha(conn, "SELECT liga_facom.obter_ou_criar_escalacao(%s,%s) AS escalacao_id", (tecnico,esquema))['escalacao_id']
    dados_escalacao = linha(conn, "SELECT rodada_id,esquema FROM liga_facom.escalacao WHERE escalacao_id=%s", (eid,))
    rid = dados_escalacao['rodada_id']
    if atual:
        print(f"Editando escalação {eid}, esquema {dados_escalacao['esquema']}, rodada {rid}.")
    else:
        print(f"Escalação {eid} criada para a rodada {rid}.")

    while True:
        t = linha(conn, "SELECT patrimonio FROM liga_facom.time_fantasy WHERE tecnico_id=%s", (tecnico,))
        itens = linhas(conn, """SELECT i.atleta_id,a.apelido,a.posicao,i.preco_pago,i.capitao
            FROM liga_facom.escalacao_item i JOIN liga_facom.atleta a USING(atleta_id)
            WHERE i.escalacao_id=%s ORDER BY a.posicao,a.apelido""", (eid,))
        total = sum((i['preco_pago'] for i in itens), start=0)
        disponivel = t['patrimonio'] - total
        print(f"\nEscalação {eid} | custo C$ {total} | patrimônio C$ {t['patrimonio']} | saldo disponível C$ {disponivel}")
        for i in itens:
            print(f"ID {i['atleta_id']} | {i['apelido']} | {i['posicao']} | C$ {i['preco_pago']} | {'CAPITÃO' if i['capitao'] else ''}")
        print("1 Ver mercado e adicionar atleta | 2 Remover atleta | 3 Escolher capitão | 4 Voltar")
        op = input("Opção: ").strip()
        if op == '4':
            return
        if op == '1':
            if not mostrar_mercado(conn, filtrar=True):
                continue
            atleta = int(input("ID do atleta para adicionar: ").strip())
            with conn.transaction():
                inserted = linha(conn, """INSERT INTO liga_facom.escalacao_item(escalacao_id,atleta_id,preco_pago)
                    SELECT %s,%s,ph.preco FROM liga_facom.preco_historico ph
                    WHERE ph.atleta_id=%s AND ph.rodada_id=%s RETURNING atleta_id""", (eid,atleta,atleta,rid))
                if not inserted:
                    raise ValueError("Não há preço deste atleta registrado para a rodada aberta.")
            print("Atleta adicionado.")
        elif op == '2':
            atleta = int(input("ID do atleta para remover: ").strip())
            with conn.transaction():
                conn.execute("DELETE FROM liga_facom.escalacao_item WHERE escalacao_id=%s AND atleta_id=%s", (eid,atleta))
            print("Atleta removido, se estava na escalação.")
        elif op == '3':
            atleta = int(input("ID do atleta que será o capitão: ").strip())
            with conn.transaction():
                conn.execute("CALL liga_facom.escolher_capitao(%s,%s)", (eid,atleta))
            print("Capitão atualizado.")
        else:
            print("Opção inválida.")


def confirmar(conn, tecnico):
    tecnico = exigir_tecnico(tecnico)
    with conn.transaction():
        conn.execute("CALL liga_facom.confirmar_escalacao_tecnico(%s)", (tecnico,))
    print("Escalação confirmada.")



def abrir_proxima_rodada(conn):
    with conn.transaction():
        conn.execute("CALL liga_facom.abrir_proxima_rodada()")
    rodada = linha(conn, "SELECT rodada_id FROM liga_facom.rodada WHERE estado='aberta'")
    print(f"Rodada {rodada['rodada_id']} aberta. Os preços e clubes foram herdados da rodada consolidada anterior.")


def fechar_mercado(conn):
    rodada = linha(conn, "SELECT rodada_id FROM liga_facom.rodada WHERE estado='aberta'")
    with conn.transaction():
        conn.execute("CALL liga_facom.fechar_rodada()")
    print(f"Mercado da rodada {rodada['rodada_id']} fechado.")


def consolidar_rodada(conn):
    fechadas = linhas(conn, "SELECT rodada_id FROM liga_facom.rodada WHERE estado='fechada' ORDER BY rodada_id")
    print("Rodadas fechadas:", ", ".join(str(r['rodada_id']) for r in fechadas))
    rodada = int(input("Número da rodada para consolidar: ").strip())
    with conn.transaction():
        conn.execute("CALL liga_facom.consolidar_rodada(%s)", (rodada,))
    print(f"Rodada {rodada} consolidada; pontuações e preços foram atualizados.")

def main():
    dsn = os.environ.get('DATABASE_URL')
    if not dsn:
        raise SystemExit('Defina DATABASE_URL antes de executar.')
    tecnico = None
    with psycopg.connect(dsn, row_factory=dict_row, autocommit=True) as conn:
        conn.execute('SET search_path TO liga_facom, public')
        while True:
            print("\nLiga FACOM Fantasy | 1 Escolher técnico | 2 Cadastrar técnico | 3 Mercado | "
                  "4 Criar liga | 5 Entrar em liga | 6 Ranking acumulado | 7 Ranking por rodada | "
                  "8 Montar/editar escalação | 9 Confirmar escalação | "
                  "10 Abrir próxima rodada | 11 Fechar mercado | 12 Consolidar rodada | 0 Sair")
            op = input('Opção: ').strip()
            try:
                if op == '0':
                    break
                elif op == '1':
                    tecnico = escolher_tecnico(conn)
                elif op == '2':
                    tecnico = cadastrar_tecnico(conn)
                elif op == '3':
                    mostrar_mercado(conn, filtrar=True)
                elif op == '4':
                    criar_liga(conn, tecnico)
                elif op == '5':
                    entrar_liga(conn, tecnico)
                elif op == '6':
                    ranking(conn, por_rodada=False)
                elif op == '7':
                    ranking(conn, por_rodada=True)
                elif op == '8':
                    montar_ou_editar(conn, tecnico)
                elif op == '9':
                    confirmar(conn, tecnico)
                elif op == '10':
                    abrir_proxima_rodada(conn)
                elif op == '11':
                    fechar_mercado(conn)
                elif op == '12':
                    consolidar_rodada(conn)
                else:
                    print('Opção inválida.')
            except Exception as exc:
                conn.rollback()
                print(f'Operação recusada: {exc}')


if __name__ == '__main__':
    main()
