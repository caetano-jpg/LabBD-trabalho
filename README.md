Liga FACOM Fantasy

Projeto desenvolvido para o Trabalho Prático de Laboratório de Banco de Dados. O sistema usa PostgreSQL 16+, PL/pgSQL e uma aplicação de terminal em Python para administrar atletas, escalações e ligas de fantasy.

Repositório:

• GitHub: https://github.com/caetano-jpg/LabBD-trabalho

Integrantes:

• Caetano Raimundo de Moraes — RGA 202419070426


Requisitos

• Docker Desktop com suporte a contêineres Linux.
• PostgreSQL 16 ou superior (a imagem Docker abaixo usa PostgreSQL 16).
• Python 3.11 ou superior.
• Arquivos JSON coletados e salvos em carga/dados/.

Banco de dados

Execute os comandos no PowerShell, a partir da pasta raiz do repositório.

Na primeira execução, crie e inicie o contêiner PostgreSQL:

docker run --name lbd-postgres -e POSTGRES_PASSWORD=lbd -e POSTGRES_USER=lbd -e POSTGRES_DB=lbd -p 5432:5432 -d postgres:16

Nas próximas execuções, se o contêiner já existir e estiver parado, inicie-o:

docker start lbd-postgres

O comando docker run cria o banco lbd vazio. Para executar os scripts SQL sem instalar psql no Windows, copie e rode os arquivos dentro do contêiner, nesta ordem:

$arquivosSql = @(
    "01-ddl.sql",
    "02-dados.sql",
    "03-programacao.sql",
    "04-consultas.sql",
    "05-seguranca-indices.sql",
    "06-aplicacao.sql"
)

foreach ($arquivoSql in $arquivosSql) {
    docker cp ".\sql\$arquivoSql" "lbd-postgres:/tmp/$arquivoSql"
    if ($LASTEXITCODE -ne 0) { throw "Falha ao copiar $arquivoSql" }

    docker exec lbd-postgres psql -U lbd -d lbd -v ON_ERROR_STOP=1 -f "/tmp/$arquivoSql"
    if ($LASTEXITCODE -ne 0) { throw "Falha ao executar $arquivoSql" }
}

Se um script apresentar erro, interrompa o processo e corrija o problema antes de seguir para o próximo.

Carga de dados e aplicação:

Na raiz do projeto, defina a conexão e instale as dependências:

$env:DATABASE_URL = "postgresql://lbd:lbd@localhost:5432/lbd"
python -m pip install -r requirements.txt

Carregue os arquivos JSON salvos e inicie a aplicação:

python .\carga\carregar.py --dados .\carga\dados
python .\app\terminal.py

O importador lê os arquivos JSON locais, carrega os dados das rodadas disponíveis e consolida as rodadas carregadas para calcular pontos e histórico de preços. A aplicação oferece cadastro e seleção de técnicos, mercado com filtros, ligas, rankings, montagem e confirmação de escalações, além das operações administrativas de rodada.

O conjunto incluído em carga/dados/ contém os dados de mercado, esquemas táticos e dez rodadas salvas em JSON. O programa de carga pode ser executado novamente para atualizar os dados sem duplicar registros.

Dados de demonstração da rodada 11

O script sql/07-rodada-demo.sql é opcional e cria dados simulados para demonstrar a rodada 11. Use-o somente depois de carregar os dados, abrir a rodada 11 e confirmar ao menos três escalações. Em seguida, o administrador pode fechar o mercado e consolidar a rodada pela aplicação.

Para executar o script opcional:

docker cp .\sql\07-rodada-demo.sql lbd-postgres:/tmp/07-rodada-demo.sql
docker exec lbd-postgres psql -U lbd -d lbd -v ON_ERROR_STOP=1 -f /tmp/07-rodada-demo.sql

Organização do projeto

• sql/: criação do esquema, dados de catálogo, lógica PL/pgSQL, consultas, índices e rotinas administrativas.
• carga/: programa de importação e arquivos JSON.
• app/: aplicação de terminal.
• docs/: documentação do modelo e mapeamento relacional.

Vídeo de apresentação:

• Link: https://drive.google.com/file/d/1VRVnsnoCi473M39MEn_8aXBEDlmPL7QC/view?usp=drive_link

• Diagrama entidade-relacionamento em notação de Chen: https://github.com/caetano-jpg/LabBD-trabalho/blob/main/docs/modelo_chen.png

• Repositório do projeto: https://github.com/caetano-jpg/LabBD-trabalho