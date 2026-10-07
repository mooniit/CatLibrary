-- User confirmed 2026-10-06. No grants or legacy ownership conversion.
update public.room_policies set lease_seconds=120, renewal_seconds=30 where id='production';
