-- Camera catalog, batch 0 (20261121100000): the 67 lens mounts Diego
-- approved, each once. Run after the migration (twice in the rehearsal, to
-- show it never duplicates), inside BEGIN / ROLLBACK.
do $$
declare
  n bigint;
begin
  select count(*) into n from public.lens_mounts
   where status = 'approved' and name in ('Nikon F', 'Canon EF', 'Canon FD', 'Canon FL', 'Canon R', 'M42', 'Pentax K', 'Minolta SR', 'Minolta A', 'Olympus OM', 'Contax/Yashica', 'Konica AR', 'Fujica X', 'Praktica B', 'Petri', 'Exakta', 'Topcon', 'Leica M', 'Leica LTM (L39)', 'Leica R', 'Contax RF', 'Contax G', 'Nikon S', 'Olympus Pen F', 'Hasselblad V', 'Hasselblad H', 'Hasselblad 1000F/1600F', 'Hasselblad Xpan', 'Mamiya 645', 'Mamiya RB67', 'Mamiya RZ67', 'Mamiya C (TLR)', 'Mamiya 7', 'Mamiya Press', 'Bronica ETR', 'Bronica SQ', 'Bronica S (EC)', 'Bronica GS', 'Pentax 67', 'Pentax 645', 'Contax 645', 'Pentax Auto 110', 'Rollei QBM', 'Retina DKL', 'Tablero de lente', 'Lente integrado', 'Alpa', 'Paxette', 'Bronica RF', 'Canon EX', 'Konica F', 'Kowa Six', 'Mamiya 6', 'Mamiya ZE', 'Mamiya/Sekor E', 'Miranda M44', 'Pentacon Six', 'Praktina', 'Rolleiflex SL66', 'Contax N', 'M39 (SLR)', 'Sigma SA', 'C-mount', 'Nikonos', 'Nikonos RS', 'Kiev 88 (Salyut)', 'Rollei 6000');
  assert n = 67, format('the 67 approved mounts (%s)', n);
  assert (select count(*) from public.lens_mounts where status = 'approved') = 67,
    'and no other';
  assert not exists (select 1 from public.lens_mounts where name = 'Canon LTM'),
    'Canon LTM is Leica LTM (L39)';
end $$;
