SET search_path TO liga_facom, public;
CREATE INDEX IF NOT EXISTS idx_escalacao_rodada_estado ON escalacao(rodada_id,estado);
CREATE INDEX IF NOT EXISTS idx_escalacao_tecnico ON escalacao(tecnico_id,rodada_id);
CREATE INDEX IF NOT EXISTS idx_atleta_rodada_entrou ON atleta_rodada(rodada_id,atleta_id) WHERE entrou_em_campo;
CREATE INDEX IF NOT EXISTS idx_scout_rodada_atleta ON scout_partida(rodada_id,atleta_id);
CREATE INDEX IF NOT EXISTS idx_clube_rodada_clube ON clube_rodada(rodada_id,clube_id);
CREATE INDEX IF NOT EXISTS idx_partida_rodada ON partida(rodada_id,valida);
CREATE INDEX IF NOT EXISTS idx_item_capitao ON escalacao_item(escalacao_id) WHERE capitao;
-- Evita expor senha no programa; em ambiente acadêmico conceda EXECUTE nas rotinas usadas.
-- Criar usuário de execução fora deste script conforme a política local do PostgreSQL.
