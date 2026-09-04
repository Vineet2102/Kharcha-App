insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- Path convention: <household_id>/<expense_id>/<attachment_id>.jpg
create policy "receipts read own household"
on storage.objects for select to authenticated
using (bucket_id = 'receipts'
       and (storage.foldername(name))[1] = public.current_household_id()::text);

create policy "receipts insert own household"
on storage.objects for insert to authenticated
with check (bucket_id = 'receipts'
            and (storage.foldername(name))[1] = public.current_household_id()::text);

create policy "receipts update own household"
on storage.objects for update to authenticated
using (bucket_id = 'receipts'
       and (storage.foldername(name))[1] = public.current_household_id()::text);

create policy "receipts delete own or admin"
on storage.objects for delete to authenticated
using (bucket_id = 'receipts'
       and (storage.foldername(name))[1] = public.current_household_id()::text
       and (owner = auth.uid() or public.is_admin()));
