# zzv2 Deployment

This directory contains the deployment files for `111.228.39.25:/work/project/zzv2`.

- `docker-compose.yml`: Sub2API, PostgreSQL, and Redis.
- `.env.example`: non-secret environment template.
- `nginx/sub2api-zzv2.conf`: dedicated Nginx reverse proxy config.
- `remote-deploy.sh`: remote script used by GitHub Actions.

Runtime secrets are stored only on the server in `/work/project/zzv2/.env`.
