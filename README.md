# Cloud-1

Déploiement automatisé d'un site **WordPress** sur une instance **AWS EC2**, avec :

- **Terraform** pour créer l'infrastructure (instance, security groups) ;
- **Ansible** pour configurer le serveur et lancer les conteneurs ;
- **Docker Compose** pour orchestrer les services (NGINX, WordPress, MariaDB, phpMyAdmin).

---

## Sommaire

- [Architecture](#architecture)
- [Arborescence](#arborescence)
- [Prérequis](#prérequis)
- [1. Provisionner l'infrastructure (Terraform)](#1-provisionner-linfrastructure-terraform)
- [2. Configurer les secrets (Ansible Vault)](#2-configurer-les-secrets-ansible-vault)
- [3. Déployer l'application (Ansible)](#3-déployer-lapplication-ansible)
- [Lancer en local](#lancer-en-local)
- [Accès aux services](#accès-aux-services)
- [Commandes utiles](#commandes-utiles)
- [Détruire l'infrastructure](#détruire-linfrastructure)
- [Sécurité](#sécurité)

---

## Architecture

```
                    Internet
                       │
             ┌─────────┴─────────┐
             │   AWS EC2 (Ubuntu 24.04, t3.micro, eu-west-3)
             │   SG ssh-access : 22  (IP admin uniquement)
             │   SG web-access : 80, 443 (ouvert)
             └─────────┬─────────┘
                       │  :80 → redirection 301 vers HTTPS
                       │  :443 (TLS 1.2 / 1.3, certificat auto-signé)
                ┌──────▼──────┐
                │    NGINX    │  reverse proxy
                └──┬───────┬──┘
     FastCGI :9000 │       │ FastCGI :9000  (/phpmyadmin/)
            ┌──────▼───┐ ┌─▼───────────┐
            │WordPress │ │ phpMyAdmin  │
            │ PHP-FPM  │ │  PHP-FPM    │
            └──────┬───┘ └─┬───────────┘
                   │ :3306 │
                ┌──▼───────▼──┐
                │   MariaDB   │
                └─────────────┘
        Réseau Docker : cloud-1 (bridge)
```

| Service      | Image                                  | Rôle                                                   |
|--------------|----------------------------------------|--------------------------------------------------------|
| `nginx`      | build local (`alpine:3.18`)            | Seul point d'entrée (ports 80/443), termine le TLS     |
| `wordpress`  | `wordpress:7.1.4-php8.2-fpm-alpine`    | Exécute WordPress via PHP-FPM                          |
| `mariadb`    | `mariadb:lts`                          | Base de données                                        |
| `phpmyadmin` | `phpmyadmin:5.2.3-fpm-alpine`          | Administration de la base, servi sous `/phpmyadmin/`   |
| `wpcli`      | `wordpress:cli-php8.2` (profil `tools`)| Conteneur ponctuel pour installer WordPress (WP-CLI)   |

**Volumes persistants** : `mariadb_volume` (données SQL), `wordpress_volume` (fichiers WordPress), `phpmyadmin_files`.
NGINX monte les volumes WordPress et phpMyAdmin pour servir directement les fichiers statiques.

---

## Arborescence

```
cloud-1/
├── terraform/
│   ├── main.tf                 # AMI Ubuntu, security groups, instance EC2, output IP
│   └── .terraform.lock.hcl     # versions figées des providers (à versionner)
├── ansible/
│   ├── inventory.ini           # hôte(s) cible(s) – groupe [cloud]
│   ├── playbook.yaml           # enchaîne les rôles
│   ├── group_vars/cloud/
│   │   ├── vars.yaml           # variables non sensibles (titre, admin, URL…)
│   │   └── vault.yaml          # secrets chiffrés avec Ansible Vault
│   └── roles/
│       ├── docker/             # installe Docker + Compose, ajoute l'user au groupe docker
│       ├── files/              # copie docker-compose.yaml + nginx/, génère le .env
│       │   └── templates/env.j2
│       ├── mariadb/            # docker compose up mariadb
│       ├── wordpress/          # docker compose up wordpress + installation via WP-CLI
│       ├── phpmyadmin/         # docker compose up phpmyadmin
│       └── nginx/              # docker compose up nginx
├── nginx/
│   ├── Dockerfile              # Alpine + nginx + certificat auto-signé
│   └── conf/nginx.conf         # redirection HTTP→HTTPS, routes WordPress / phpMyAdmin
├── docker-compose.yaml
└── .env                        # secrets pour l'usage local (non versionné)
```

---

## Prérequis

Sur la machine de contrôle (ton poste) :

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) ≥ 2.15
- La collection Ansible Docker :
  ```bash
  ansible-galaxy collection install community.docker
  ```
- Des identifiants AWS configurés (`aws configure` ou variables `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)
- Une **key pair** existante dans AWS (région `eu-west-3`) nommée `Macbook`, dont la clé privée est disponible localement (par défaut `~/.ssh/id_ed25519`)
- Docker + Docker Compose (uniquement pour le lancement en local)

---

## 1. Provisionner l'infrastructure (Terraform)

```bash
cd terraform
terraform init      # télécharge le provider AWS
terraform plan      # affiche ce qui va être créé
terraform apply     # crée l'instance et les security groups
```

Ressources créées :

- `aws_security_group.ssh` (`ssh-access`) : port **22** autorisé uniquement depuis l'IP de l'administrateur ;
- `aws_security_group.web` (`web-access`) : ports **80** et **443** ouverts à tous ;
- `aws_instance.serveur` : Ubuntu 24.04 (dernière AMI Canonical), `t3.micro`, tag `Name = cloud-1`.

À la fin, Terraform affiche l'IP publique :

```bash
terraform output ip_publique
```

> ⚠️ Si ton IP publique change, mets à jour le `cidr_blocks` du security group SSH dans [terraform/main.tf](terraform/main.tf) puis relance `terraform apply`.

Reporte ensuite cette IP dans [ansible/inventory.ini](ansible/inventory.ini) :

```ini
[cloud]
<IP_PUBLIQUE> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

---

## 2. Configurer les secrets (Ansible Vault)

Les secrets sont stockés chiffrés dans `ansible/group_vars/cloud/vault.yaml`. Variables attendues :

```yaml
vault_wp_db_root_password: "..."
vault_wp_db_name: "..."
vault_wp_db_user: "..."
vault_wp_db_password: "..."
vault_wp_admin_password: "..."
```

Commandes utiles :

```bash
cd ansible
ansible-vault create group_vars/cloud/vault.yaml   # créer le fichier
ansible-vault edit   group_vars/cloud/vault.yaml   # le modifier
ansible-vault view   group_vars/cloud/vault.yaml   # le lire
```

Les variables non sensibles (titre du site, utilisateur et email admin, URL) sont dans
[ansible/group_vars/cloud/vars.yaml](ansible/group_vars/cloud/vars.yaml).

Pendant le déploiement, le rôle `files` génère sur le serveur un fichier `.env` (permissions `0600`) à partir du template
[env.j2](ansible/roles/files/templates/env.j2), lu ensuite par Docker Compose.

---

## 3. Déployer l'application (Ansible)

```bash
cd ansible

# Vérifier la connexion SSH
ansible -i inventory.ini cloud -m ping

# Déploiement complet
ansible-playbook -i inventory.ini playbook.yaml --ask-vault-pass
```

Étapes réalisées par le playbook :

1. **docker** : installe Docker, Docker Compose et buildx, démarre le service, ajoute `ubuntu` au groupe `docker` ;
2. **files** : crée `/home/ubuntu/cloud-1`, y copie `docker-compose.yaml` et `nginx/`, génère le `.env` ;
3. **mariadb** : démarre MariaDB ;
4. **wordpress** : démarre WordPress, attend `wp-config.php` et la disponibilité de MariaDB en TCP, puis lance `wp core install` via le conteneur `wpcli` **uniquement si le site n'est pas déjà installé** (le playbook est idempotent) ;
5. **phpmyadmin** : démarre phpMyAdmin ;
6. **nginx** : build l'image et démarre le reverse proxy.

### Déployer un seul service

Chaque rôle a un tag. Les rôles `docker` et `files` sont tagués `always` et s'exécutent à chaque fois.

```bash
ansible-playbook -i inventory.ini playbook.yaml --ask-vault-pass --tags nginx
ansible-playbook -i inventory.ini playbook.yaml --ask-vault-pass --tags wordpress,phpmyadmin
```

Tags disponibles : `mariadb`, `wordpress`, `phpmyadmin`, `nginx`.

---

## Lancer en local

Crée un fichier `.env` à la racine :

```dotenv
WP_DB_NAME=wordpress
WP_DB_USER=wpuser
WP_DB_PASSWORD=changeme
WP_DB_ROOT_PASSWORD=changeme_root
```

Puis :

```bash
docker compose up -d --build

# Installation initiale de WordPress (sinon via l'assistant web)
docker compose run --rm wpcli wp core install \
  --url=https://localhost --title="Cloud-1" \
  --admin_user=admin --admin_password=changeme --admin_email=admin@example.com \
  --skip-email
```

Le site est alors accessible sur <https://localhost>.

---

## Accès aux services

| URL                                   | Service                          |
|---------------------------------------|----------------------------------|
| `http://<IP>`                         | redirige vers HTTPS (301)        |
| `https://<IP>/`                       | site WordPress                   |
| `https://<IP>/wp-admin`               | administration WordPress         |
| `https://<IP>/phpmyadmin/`            | phpMyAdmin (identifiants MariaDB)|

> Le certificat TLS est **auto-signé** (généré dans le [Dockerfile](nginx/Dockerfile)) : le navigateur affichera un avertissement, c'est normal.

---

## Commandes utiles

Sur le serveur (`ssh ubuntu@<IP>`), depuis `~/cloud-1` :

```bash
docker compose ps                      # état des conteneurs
docker compose logs -f nginx           # logs d'un service
docker compose restart wordpress       # redémarrer un service
docker compose run --rm wpcli wp plugin list   # utiliser WP-CLI
docker exec -it mariadb mariadb -u root -p     # console SQL
```

---

## Détruire l'infrastructure

```bash
cd terraform
terraform destroy
```

> Les volumes Docker vivent sur le disque de l'instance : détruire l'instance supprime **définitivement** la base de données et les fichiers WordPress.

---

## Sécurité

- **Secrets** : chiffrés avec Ansible Vault ; le `.env` local et les fichiers `*.tfstate` / `*.tfvars` sont exclus de git (voir [.gitignore](.gitignore)).
- **Réseau** : seul NGINX expose des ports (80/443) ; MariaDB, WordPress et phpMyAdmin ne sont joignables que via le réseau Docker interne `cloud-1`.
- **SSH** : restreint à l'IP de l'administrateur via le security group `ssh-access`.
- **TLS** : uniquement TLS 1.2 et 1.3, tout le trafic HTTP est redirigé vers HTTPS.
- **Fichiers sensibles** : le `.env` généré sur le serveur a les permissions `0600`, et la tâche Ansible correspondante est en `no_log`.
