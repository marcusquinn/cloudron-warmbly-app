# Publish the Cloudron package

## Release authority

Pull requests run static package checks (ShellCheck, the sign-in script's
syntax), a patch-apply check against the pinned upstream commit, a dry run of
the real Cloudron CLI and a no-push image build. Merging is not publication.
The catalog workflow publishes from `main` only after the operator sets the
repository variable `CLOUDRON_PUBLICATION_ENABLED=true`; setting it is standing
authorization for that workflow's image and catalog publication.

Before enabling it:

1. Keep this repository public. The store reads `iconUrl` and `mediaLinks`
   from `raw.githubusercontent.com`, and Cloudron servers fetch the catalog
   from there; both return 404 for a private repository.
2. Add the repository secret `CLOUDRON_RELEASE_PAT`. The pinned workflow uses
   it, and only it, to push the generated catalog commit and tag. Reuse the
   owner's existing fine-grained token (Contents read/write on the selected
   `cloudron-*-app` repositories): add this repository to its access list,
   then set the secret from gopass without displaying it:

   ```sh
   aidevops secret CLOUDRON_RELEASE_PAT -- sh -c 'printf %s "$CLOUDRON_RELEASE_PAT" | gh secret set CLOUDRON_RELEASE_PAT --repo marcusquinn/cloudron-warmbly-app'
   ```

   Never put it in Git or an issue. GHCR pushes always use the job token.
3. Apply the repository rulesets: block force pushes and deletion on the
   default branch, and block updates and deletion of `v*` tags (tag creation
   stays allowed).

## Pipeline

1. In a PR: bump `version` in `CloudronManifest.json` and add the version's
   section to `CHANGELOG` (store format: a `[X.Y.Z]` line, then `*` bullets).
   To move to a newer Warmbly, update the upstream pin together:
   `WARMBLY_VERSION`, `WARMBLY_COMMIT`, every `ghcr.io/warmbly/warmbly/*`
   image tag and digest in the `Dockerfile`, `upstreamVersion` and the
   `upstreamLicense` URL in the manifest. Rebase
   `patches/0001-cloudron-oidc-first-user-owner.patch` if it no longer applies,
   and check `web-extra/cloudron-sso.js` still finds the sign-in form. A
   package-only release keeps the pin; say so in the changelog.
2. Qualify the build on a test install (below), review, merge with a merge
   commit (see [Store listing](#store-listing)).
3. The catalog workflow builds `linux/amd64`, pushes
   `ghcr.io/marcusquinn/cloudron-warmbly-app:<version>` and attests the image
   digest with GitHub keyless provenance.
4. After the first push, make the GHCR package public. Cloudron pulls
   anonymously, and the workflow refuses to publish an image it cannot pull
   anonymously; rerun the failed workflow after changing visibility. The
   attested image is reused.
5. The pinned Cloudron CLI adds the version as `testing` with the
   digest-pinned image, promotes it to `published` and verifies the catalog.
   Never hand-edit `CloudronVersions.json`.
6. The workflow attests the catalog, verifies that attestation, commits only
   that file and pushes `main` and the `vX.Y.Z` tag atomically. A concurrent
   package change on `main` rejects the push instead of overwriting it.
7. The release job creates the GitHub release from the tag after checking the
   tag is on `main`, the image pulls anonymously and both attestations verify.
   Notes come from the version's `CHANGELOG` section.
8. Update the production install from the catalog and confirm it is healthy
   and that sign-in, mailboxes and campaigns persist.

Published versions are append-only: never rebuild or overwrite one; revoke and
ship a new version instead. A pushed image without a catalog entry is a
recoverable intermediate state, not a release. Only the generated catalog
commit may carry GitHub's skip-CI marker; describe it in prose elsewhere,
because GitHub skips runs whose head commit message contains it anywhere.

Verify provenance with:

```sh
gh attestation verify oci://ghcr.io/marcusquinn/cloudron-warmbly-app@sha256:<digest> --repo marcusquinn/cloudron-warmbly-app
gh attestation verify CloudronVersions.json --repo marcusquinn/cloudron-warmbly-app
```

Cloudron itself does not check these attestations; they are publisher
provenance and tamper evidence.

## Qualification on a test install

`cloudron install --location <test-location>` from a checkout builds the image
on the server; `cloudron update --app <test-location>` rebuilds. This exercises
the package, not the catalog. Check:

- `https://<app>/healthz`, `https://<API domain>/health` and
  `https://<tracking domain>/health` answer; `warmblyctl status` and
  `warmblyctl doctor` in the app's *Terminal* report no failures.
- `https://<API domain>/v1/auth/config` lists the `oidc` provider. On a fresh
  install it reports `cloudron_first_owner: true`.
- The sign-in screen shows *Continue with* the Cloudron's name with the
  first-owner note; the first Cloudron sign-in becomes owner and platform
  admin, and `cloudron_first_owner` then turns `false`. A second Cloudron user
  gets an ordinary account.
- Platform mail: an invitation or sign-in code arrives.
- Connect a Cloudron Mail mailbox over IMAP/SMTP; send a test campaign step to
  your own address, open it and click a link; the opens and clicks record.
- A hosted form on the forms domain accepts a submission.
- Restart; back up and restore to a disposable app; connected mailboxes still
  work (the restore reused `/app/data/.secrets.env`).

To test an update from the catalog, install the previous version with
`cloudron install --versions-url <catalog-url>`, then update from the
dashboard and confirm `cloudron status --app <app>` reports the new digest.

## Store listing

Catalog URL:
`https://raw.githubusercontent.com/marcusquinn/cloudron-warmbly-app/main/CloudronVersions.json`

The CLI copies the manifest into each catalog entry, so a listing shows
`DESCRIPTION.md`, `POSTINSTALL.md`, that version's `CHANGELOG` section, the
icon and `mediaLinks` as they were when published. `iconUrl` and `mediaLinks`
are pinned to commits so published entries never change. Merge with a merge
commit, not a squash, so those commits stay reachable from `main`. Before
release, check each URL returns HTTPS 200 with an image content type:

```sh
jq -r '.iconUrl, .mediaLinks[]' CloudronManifest.json | xargs -n1 curl -sS -o /dev/null -w '%{http_code} %{content_type} %{url_effective}\n'
```

Artwork sources and provenance: [DESIGN.md](../DESIGN.md). After changing the
images, render and commit them first, then pin `iconUrl` and `mediaLinks` to
that commit in a second commit.

To list the app on [Cloudron Community Apps](https://ca.cloudron.io), sign in,
add the catalog URL to your apps, and check the imported title, icon,
screenshots, changelog and install link. Then announce it in the forum's
[Community Apps](https://forum.cloudron.io/category/220/community-apps)
category and add the topic as `forumUrl` in the manifest for the next
version. Both the listing and the announcement are publication actions for
the maintainer.
