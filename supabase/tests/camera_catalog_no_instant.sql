-- Instant formats out of the camera catalogue (20261121180000). Run after
-- the migration, inside BEGIN / ROLLBACK.
do $$
begin
  assert (select count(*) from public.camera_models
           where format ~ '^(Instax|Polaroid)' or type = 'Instantánea') = 0,
    'no instant model is left';
  assert not app_private.camera_format_ok('Instax Mini')
     and not app_private.camera_format_ok('Polaroid SX-70')
     and not app_private.camera_format_ok('Polaroid i-Type'), 'instant formats are out';
  assert not app_private.camera_type_ok('Instantánea'), 'the instant type is out';
  assert app_private.camera_format_ok('35mm') and app_private.camera_format_ok('Large Format')
     and app_private.camera_type_ok('Caja') and app_private.camera_type_ok('P&S'), 'the rest stays';
end $$;
