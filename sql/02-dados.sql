BEGIN;
SET search_path TO liga_facom, public;
INSERT INTO posicao(codigo,nome) VALUES
('gol','Goleiro'),('lat','Lateral'),('zag','Zagueiro'),('mei','Meia'),('ata','Atacante'),('tec','Técnico') ON CONFLICT DO NOTHING;
INSERT INTO situacao(codigo,descricao) VALUES
('provavel','Provável'),('duvida','Dúvida'),('suspenso','Suspenso'),('contundido','Contundido'),('nulo','Nulo') ON CONFLICT DO NOTHING;
INSERT INTO scout_tipo(sigla,descricao,valor,posicoes_permitidas) VALUES
('G','Gol',8,NULL),('A','Assistência',5,NULL),('FT','Finalização na trave',3,NULL),('FD','Finalização defendida',1.2,NULL),('FF','Finalização para fora',0.8,NULL),('FS','Falta sofrida',0.5,NULL),('PS','Pênalti sofrido',1,NULL),('DS','Desarme',1.5,NULL),('SG','Jogo sem sofrer gol',5,ARRAY['gol','lat','zag']::char(3)[]),('DE','Defesa',1.3,ARRAY['gol']::char(3)[]),('DP','Defesa de pênalti',7,ARRAY['gol']::char(3)[]),('GS','Gol sofrido',-1,ARRAY['gol']::char(3)[]),('FC','Falta cometida',-0.3,NULL),('I','Impedimento',-0.1,NULL),('CA','Cartão amarelo',-1,NULL),('CV','Cartão vermelho',-3,NULL),('GC','Gol contra',-3,NULL),('PC','Pênalti cometido',-1,NULL),('PP','Pênalti perdido',-4,NULL) ON CONFLICT DO NOTHING;
INSERT INTO esquema(nome,qtd_lat,qtd_zag,qtd_mei,qtd_ata) VALUES
('3-4-3',0,3,4,3),('3-5-2',0,3,5,2),('4-3-3',2,2,3,3),('4-4-2',2,2,4,2),('4-5-1',2,2,5,1),('5-3-2',2,3,3,2),('5-4-1',2,3,4,1) ON CONFLICT DO NOTHING;
-- Dados fictícios para desenvolvimento; substituam pelos integrantes reais antes da entrega.
INSERT INTO tecnico(nome,email,apelido) VALUES
('Técnico 1','tecnico1@example.com','T1'),('Técnico 2','tecnico2@example.com','T2'),('Técnico 3','tecnico3@example.com','T3'),('Técnico 4','tecnico4@example.com','T4'),('Técnico 5','tecnico5@example.com','T5'),('Técnico 6','tecnico6@example.com','T6'),('Técnico 7','tecnico7@example.com','T7'),('Técnico 8','tecnico8@example.com','T8') ON CONFLICT(email) DO NOTHING;
INSERT INTO time_fantasy(tecnico_id,nome) SELECT tecnico_id,'Time '||apelido FROM tecnico ON CONFLICT DO NOTHING;
INSERT INTO liga(dono_id,nome,descricao,codigo_convite,limite,publica) SELECT tecnico_id,'Liga aberta','Liga pública','ABERTA-'||tecnico_id,20,TRUE FROM tecnico WHERE email='tecnico1@example.com' ON CONFLICT(codigo_convite) DO NOTHING;
INSERT INTO liga(dono_id,nome,descricao,codigo_convite,limite,publica) SELECT tecnico_id,'Liga fechada','Liga privada','FECHADA-'||tecnico_id,20,FALSE FROM tecnico WHERE email='tecnico2@example.com' ON CONFLICT(codigo_convite) DO NOTHING;
INSERT INTO liga(dono_id,nome,descricao,codigo_convite,limite,publica) SELECT tecnico_id,'Liga mista','Exemplo de liga','MISTA-'||tecnico_id,20,TRUE FROM tecnico WHERE email='tecnico3@example.com' ON CONFLICT(codigo_convite) DO NOTHING;
INSERT INTO participacao(liga_id,tecnico_id) SELECT l.liga_id,t.tecnico_id FROM liga l CROSS JOIN tecnico t WHERE l.nome='Liga aberta' ON CONFLICT DO NOTHING;
INSERT INTO participacao(liga_id,tecnico_id) SELECT l.liga_id,t.tecnico_id FROM liga l JOIN tecnico t ON t.email IN ('tecnico2@example.com','tecnico4@example.com') WHERE l.nome='Liga fechada' ON CONFLICT DO NOTHING;
INSERT INTO participacao(liga_id,tecnico_id) SELECT l.liga_id,t.tecnico_id FROM liga l JOIN tecnico t ON t.email IN ('tecnico3@example.com','tecnico1@example.com','tecnico5@example.com') WHERE l.nome='Liga mista' ON CONFLICT DO NOTHING;
COMMIT;
