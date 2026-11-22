# SmartBlock qualified lease signing: provider handoff

## Current state

The app currently stores an in-app acceptance event from each party. This is not a qualified electronic signature (QES). The UI now labels it accordingly. No signing credentials or signing links are exposed in Flutter.

The database readiness migration `SB_151_Qualified_Lease_Signing_Readiness.sql` adds a separate QES state and server-only request/event tables. It does not claim that a signature has been obtained and does not create a provider request.

## Provider path

JCC is the first provider to assess. Cyprus' National eID Framework describes remote-signature integrations using CSC or ETSI remote-signing APIs, but SmartBlock still needs JCC's current commercial/API package, sandbox access, supported document profile, authentication flow, callback or polling rules, and confirmation that the tenant and owner can authorize each signature independently. The framework alone is not an integration agreement.

## Final integration checklist

1. Obtain JCC's written API specification, sandbox credentials, production onboarding, pricing, allowed redirect/callback URLs, and support contact.
2. Build the final, case-specific lease document and preserve an immutable copy. Calculate SHA-256 over the exact bytes submitted for signing.
3. Upload the prepared document to a private Supabase Storage bucket. Never put identity documents, provider secrets, bearer tokens, or signing URLs in the Flutter app.
4. Add a server-side Supabase Edge Function that authenticates the requester, confirms they are an assigned party, creates an idempotent provider request, and stores only provider request IDs and approved status metadata.
5. Implement the provider's documented OAuth/CSC or ETSI protocol, user authorization / sole-control confirmation, and signed-document return flow. Do not invent endpoints or webhook verification rules.
6. Verify the returned PDF signature and certificate chain using a trusted validation library/service; confirm the signature is qualified and the signed document hash matches the submitted version.
7. Record each provider status transition idempotently, notify both parties, and set `lease_renewals.qes_status = 'completed'` only after validation succeeds.
8. Apply the tenancy renewal to rent/installment records only after the verified QES document is complete, then retain the document and validation evidence under the agreed retention and access policy.
9. Run sandbox tests for owner-first, tenant-first, decline, expiry, retries, duplicate callbacks, altered document, and incomplete signing before production credentials are enabled.

## Secrets (server-side only)

Names must be adjusted to JCC's official onboarding package. Candidate Supabase Edge Function secrets are `JCC_CSC_BASE_URL`, `JCC_CLIENT_ID`, `JCC_CLIENT_SECRET`, and any provider-required user or callback credentials. Store them with Supabase Edge Function secrets; never in repository files, GitHub Pages build variables, or Flutter compile-time defines.

## Document and legal review

The uploaded tenancy agreement is a sample. Each agreement must be assembled from that case's agreed terms; do not copy the sample's personal details or assume its clauses apply. A Cyprus-qualified lawyer should approve the reusable template and data-retention wording before production use. A visual signature image or ordinary in-app click must never be represented as QES.

