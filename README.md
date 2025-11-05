# multi-schema-postgres-etl

Cet outil d'ETL permet de réunir et d'anonymiser plusieurs bases de données postgres dans une même base de données sous différents schemas.

Cette base de données peut ensuite être utilisée par Metabase ou un autre outil de BI.

Cet outil est utilisé par RDV Service Public, RDV Insertion et Agents en Intervention

Beaucoup de contexte sur les origines de cet ETL sont disponibles dans la [PR#4362](https://github.com/betagouv/rdv-service-public/pull/4362) de RDV Service Public

## Fonctionnement

```mermaid
sequenceDiagram
    participant ETL as Script ETL
    participant DB_ETL as Metabase Database
    participant DB_RDV as RDV Database
    activate ETL
    GitHub->>ETL: Téléchargement config/anonymizer.yml
    DB_RDV->>ETL: pg_dump
    ETL->>DB_ETL: restore to public schema without indexes
    ETL->>DB_ETL: anonymize
    ETL->>DB_ETL: restore indexes
    ETL->>DB_ETL: move to schema rdvs, rdvi...
    ETL->>DB_ETL: grand permissions to metabase user
    ETL->>DB_ETL: clean public schema
    deactivate ETL
```

Le schéma public est utilisé transitoirement :

- On restore les dumps tels quels dans le schéma public ;
- On anonymise, puis on copie tout vers le schéma du nom souhaité ;
- On supprime tout de public.

On n’a pas trouvé de manière plus simple de faire ça car pg_restore ne permet pas de restorer dans un schéma différent.
Il n’y a jamais de données non-anonymisées dans les schémas cibles.
Le user Postgres de la base remplie par l’ETL utilisé par Metabase n’a pas accès à public mais uniquement aux schémas cibles.

## Usage en staging et production

### Hébergeur Scalingo

Depuis votre terminal, avec scalingo-cli configuré et loggé vous pouvez lancer :

```shell
bundle exec ruby trigger_detached_run.rb --app rdvsp
```

Des jobs lancent ces commandes toutes les nuits pour les trois apps, cf /cron.json

## Usage en local

> [!WARNING]
> Assurez vous de supprimer les fichiers de dumps, les bases de données restaurées, et les mots de passe des users Postgres utilisés en local après vos tests

### Variables d’environnement

Copiez le fichier `.env.example` puis renseignez les variables d’environnement dans un fichier `.env` :

`cp .env.example .env`

### Préparation Postgres local

Créer une base de données PostgreSQL, un rôle superuser pour l’ETL, et un rôle sans droits pour Metabase.

```sh
createdb rdv-sp-etl
echo "CREATE ROLE rdv_sp_etl_user WITH LOGIN SUPERUSER PASSWORD 'rdv_sp_etl_password'" | psql -d rdv-sp-etl;
echo "CREATE ROLE rdv_metabase WITH LOGIN PASSWORD 'rdv_metabase_password'" | psql -d rdv-sp-etl;
```

Mettez à jour dans le `.env` :

`ETL_DB_URL=postgresql://rdv_sp_etl_user:rdv_sp_etl_password@localhost:5432/rdv-sp-etl`

### Préparation de l’URL de la base de données cible

Dans cet exemple nous configurons pour la base de données de démo de RDV-Solidarités.

En utilisant le CLI scalingo, récupérez le nom de la base de données

```sh
scalingo env-get --app demo-rdv-solidarites --region osc-secnum-fr1  SCALINGO_POSTGRESQL_URL | sed -E 's|.*://.*/([^?]+).*|\1|'
```

Puisque nous allons utiliser le tunnel scalingo, le host et le port de la base de données sont toujours `localhost:10000`

Récupérez les credentials d’un user Postgres read-only en vous connectant depuis le dashboard scalingo.

Vous pouvez maintenant renseigner la variable d’environnement dans votre fichier `.env` :

`RDV_SOLIDARITES_DB_URL=postgresql://RO_USER:RO_PASSWORD@localhost:10000/demo_db_name`

### Lancement

Dans un terminal ouvrir un tunnel par exemple vers la db scalingo Postgres de `demo-rdv-solidarites` avec :

```shell
scalingo db-tunnel --app demo-rdv-solidarites --region osc-secnum-fr1  SCALINGO_POSTGRESQL_URL
```

Dans un autre terminal, lancer l’ETL :

```shell
bundle exec ruby main.rb --app rdvs
```

## Usage en local avec Docker

Commencer par renseigner les variables d'environnement nécessaires dans le fichier `.env`, par exemple :

```dotenv
ETL_DB_URL=postgresql://esd:[password]@192.168.120.44:5432/aei-etl
METABASE_USERNAME=esd
ORIGIN_DB_URL=postgresql://esd:[password]@192.168.120.44:5432/api-aei
CONFIG_PATH=https://gitlab.com/incubateur-territoires/startups/agents-intervention/agents-en-intervention/-/raw/feat/metabase/config.etl.yml
```

Puis :

```shell
docker build -t etl .
docker run --env-file .env -it etl bundle exec ruby main.rb --app [app]
```
