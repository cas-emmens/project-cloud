# gitea-repos

Maakt alle benodigde repositories en tokens aan in Gitea. Dit is de voorbereiding voor het CI/CD-systeem: broncode-repos voor Drone, GitOps-repos voor Argo CD, en persoonlijke toegangstokens voor beide.

**Gebruikt door:** `setup-cicd-pipeline.yml` (play 2)

## Wat doet deze rol?

1. **Health checks**: wacht tot Gitea en Drone bereikbaar zijn.
2. **Organisatie**: maakt de Gitea-organisatie aan als die nog niet bestaat.
3. **Broncode-repos**: controleert of de repos al bestaan. Verwijdert eventuele mirror-repos (die conflicteren met een normale push). Maakt lege repos aan.
4. **GitOps-repos** (`customer-instances` en `test-customers`): maakt aan met `auto_init: true` (README zodat Argo CD direct een commit heeft om te synchroniseren).
5. **Tokens aanmaken**:
   - `drone-oauth`: breed token voor Drone repository-sync (schrijf-rechten).
   - `argocd-gitops`: read-only token voor Argo CD.
6. **Repo-metadata ophalen** van Gitea — de `drone-setup`-rol heeft deze nodig om repos in de Drone-database in te voegen.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `repos` | `[orange-uptime-kuma, orange-uptime-kuma-management-tool]` | Lijst van broncode-repos om te importeren (met GitHub-URL en default branch) |

## Afhankelijkheden

- Gitea en Drone draaien (Phase 3 klaar).
- `namespaces` heeft alle namespaces aangemaakt.

## Geregistreerde variabelen (doorgegeven aan volgende rollen)

| Variabele | Gebruikt door |
|-----------|---------------|
| `repo_checks` | `drone-setup` (bepaalt welke repos gepusht moeten worden) |
| `gitea_repo_details` | `drone-setup` (metadata voor DB-insert en build-tracking) |
| `gitea_drone_pat` | `drone-setup` (OAuth-token injecteren in Drone-database) |
| `gitea_argocd_pat` | `argocd-gitops` (credentials voor repo-secrets en Image Updater) |

## Opmerkingen

- **Tokens worden altijd opnieuw aangemaakt**: bestaande `drone-oauth` en `argocd-gitops` tokens worden verwijderd en hergemaakt. Dit is nodig omdat Gitea de token-waarde (sha1) alleen toont bij aanmaken — bij een re-run weten we de waarde niet meer.
- **`auto_init: true` op GitOps-repos**: zonder een initiële commit heeft Argo CD geen `HEAD` om te checken en rapporteert hij een fout. De automatische README lost dit op.
