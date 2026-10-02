-- SuperD: proof-of-delivery photos stop being world-readable.
--
-- The bucket was created public (0001), so every delivery photo has been
-- served to anyone with the URL, forever, with no signature and no
-- expiry. Those photos are taken at a customer's door: they show the
-- address, the parcel, and sometimes the person receiving it.
--
-- Nothing was enumerable - the path is keyed by delivery id - but a URL
-- is a weak secret. It survives in browser history, proxy logs, anything
-- the link is pasted into, and it never expires. The rider-photos bucket
-- (0091) was built private with short-lived signed links for exactly
-- these reasons; this brings the older bucket in line.
--
-- Only two screens ever display it - the admin delivery detail and the
-- driver's own - and both viewers are signed in, so a signed URL can be
-- minted client-side. The customer tracking page does not show it, which
-- is what makes this a small change rather than one needing a public
-- endpoint to sign on an anonymous visitor's behalf.

update storage.buckets set public = false where id = 'proof-of-delivery';

-- The public read policy goes; reads are now for the rider who took the
-- photo and the staff who supervise them.
drop policy if exists "pod: public read" on storage.objects;

create policy "pod: owner or staff read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'proof-of-delivery'
    and (owner = auth.uid() or public.is_dispatcher_or_above())
  );

-- Stored values become paths rather than absolute public URLs, since a
-- public URL no longer resolves. Existing rows are rewritten in place:
-- everything after the bucket name is the path the signer wants.
update public.deliveries
set proof_of_delivery_url =
  regexp_replace(proof_of_delivery_url, '^.*/proof-of-delivery/', '')
where proof_of_delivery_url is not null
  and proof_of_delivery_url like '%/proof-of-delivery/%';

comment on column public.deliveries.proof_of_delivery_url is 'Path within the private proof-of-delivery bucket (not a URL, despite the column name - kept for compatibility). Readers mint a short-lived signed link; see DeliveryRepository.proofOfDeliveryUrl.';
