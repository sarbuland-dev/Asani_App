-- Dev seed (D-52): fresh test data, same clinics and doctors as the demo backend (demo_seed.dart).
-- Safe to run again (upserts). No accounts here: patients sign up in the app; the Super Admin and
-- clinic logins are created by the admin tools (phase 6).
-- "Long day" doctors sit 08:00–23:00 every day so the queue can be tested at any time.

insert into public.billing_settings (id) values ('billing') on conflict (id) do nothing;

insert into public.clinics (id, name, area, city, address, phone, lat, lng, status, search_keywords) values
  ('c_alshifa',     'Al-Shifa Clinic',       'Johar Town',  'Lahore',    'Main Boulevard, Johar Town', '042-1234567',  31.4697, 74.2728, 'active',    '{al-shifa,shifa,johar,town}'),
  ('c_citycare',    'City Care Clinic',      'Gulberg',     'Lahore',    'MM Alam Road, Gulberg III',  '042-3576543',  31.5102, 74.3511, 'active',    '{city,care,gulberg}'),
  ('c_modeltown',   'Model Town Medical',    'Model Town',  'Lahore',    'Link Road, Model Town',      '042-3588812',  31.4835, 74.3239, 'pilot',     '{model,town,medical}'),
  ('c_dha',         'DHA Family Clinic',     'DHA Phase 5', 'Lahore',    'Sector C, DHA Phase 5',      '042-3712990',  31.4625, 74.4086, 'active',    '{dha,family,phase}'),
  ('c_shifafamily', 'Shifa Family Clinic',   'Model Town',  'Lahore',    'Block K, Model Town',        '042-3591177',  null,    null,    'active',    '{shifa,family,model,town}'),
  ('c_rehman',      'Rehman Clinic',         'Iqbal Town',  'Lahore',    'Moon Market, Iqbal Town',    '042-3781100',  31.5040, 74.2870, 'suspended', '{rehman,iqbal,town}'),
  ('c_clifton',     'Clifton Care Clinic',   'Clifton',     'Karachi',   'Block 5, Clifton',           '021-35871234', 24.8138, 67.0300, 'active',    '{clifton,care}'),
  ('c_capital',     'Capital Health Clinic', 'F-8 Markaz',  'Islamabad', 'F-8 Markaz',                 '051-2287654',  33.7086, 73.0375, 'pilot',     '{capital,health,f-8}')
on conflict (id) do update set
  name = excluded.name, area = excluded.area, city = excluded.city, address = excluded.address, phone = excluded.phone,
  lat = excluded.lat, lng = excluded.lng, status = excluded.status, search_keywords = excluded.search_keywords;

insert into public.clinic_billing (clinic_id, plan, monthly_fee, pilot_ends_at, owner_name, email)
select id, case when status = 'pilot' then 'pilot' else 'basic' end, case when status = 'pilot' then 0 else 3000 end,
       now() + interval '30 days', 'Owner of ' || name, null
from public.clinics
on conflict (clinic_id) do nothing;

-- Weekly schedules (jsonb). Helper CTE: every day, or every day except a set of days.
with s as (
  select
    jsonb_build_object('mon', d, 'tue', d, 'wed', d, 'thu', d, 'fri', d, 'sat', d, 'sun', d) as long_day,
    jsonb_build_object('mon', e, 'tue', e, 'wed', e, 'thu', e, 'fri', e, 'sat', e, 'sun', null) as evening,
    jsonb_build_object('mon', m, 'tue', m, 'wed', m, 'thu', m, 'fri', m, 'sat', m, 'sun', null) as morning,
    jsonb_build_object('mon', l, 'tue', l, 'wed', l, 'thu', l, 'fri', l, 'sat', null, 'sun', null) as weekdays_late
  from (select '{"start": "08:00", "end": "23:00"}'::jsonb as d,
               '{"start": "17:00", "end": "21:00"}'::jsonb as e,
               '{"start": "10:00", "end": "14:00"}'::jsonb as m,
               '{"start": "16:00", "end": "20:00"}'::jsonb as l) x
)
insert into public.doctors (id, clinic_id, name, speciality, city, name_key, doctor_group_id, qualification,
                            avg_consult_minutes, max_tokens_per_day, token_prefix, schedule, sort_order)
select v.id, v.clinic_id, v.name, v.speciality, c.city, v.name_key, v.grp, v.qual, v.avg, v.max, v.prefix,
       case v.sched when 'long' then s.long_day when 'evening' then s.evening when 'morning' then s.morning
                    else s.weekdays_late end,
       v.sort
from s, (values
  ('d_ayesha',     'c_alshifa',     'Dr. Ayesha Malik',  'generalPhysician', 'ayesha malik',  'g_ayesha', 'MBBS, FCPS',              10, 40, 'A', 'long',    1),
  ('d_kamran',     'c_alshifa',     'Dr. Kamran Ahmed',  'child',            'kamran ahmed',  null,       'MBBS, DCH',               10, 40, 'B', 'morning', 2),
  ('d_sana',       'c_alshifa',     'Dr. Sana Riaz',     'womensHealth',     'sana riaz',     null,       'MBBS, FCPS',              15, 30, 'C', 'evening', 3),
  ('d_imran',      'c_citycare',    'Dr. Imran Qureshi', 'generalPhysician', 'imran qureshi', null,       null,                      10, 40, 'A', 'long',    1),
  ('d_farah',      'c_citycare',    'Dr. Farah Naz',     'skin',             'farah naz',     null,       null,                      12, 40, 'B', 'morning', 2),
  ('d_asif',       'c_citycare',    'Dr. Asif Khan',     'heart',            'asif khan',     null,       'MBBS, FCPS (Cardiology)', 15, 40, 'C', 'long',    3),
  ('d_usman',      'c_modeltown',   'Dr. Usman Tariq',   'ent',              'usman tariq',   null,       null,                      10, 40, 'A', 'late',    1),
  ('d_hina',       'c_dha',         'Dr. Hina Shah',     'child',            'hina shah',     null,       null,                      10, 40, 'A', 'morning', 1),
  ('d_bilal',      'c_dha',         'Dr. Bilal Ahmed',   'generalPhysician', 'bilal ahmed',   null,       null,                      10, 40, 'B', 'long',    2),
  ('d_ayesha_dha', 'c_dha',         'Dr. Ayesha Malik',  'generalPhysician', 'ayesha malik',  'g_ayesha', 'MBBS, FCPS',              10, 40, 'C', 'morning', 3),
  ('d_nadia',      'c_shifafamily', 'Dr. Nadia Karim',   'generalPhysician', 'nadia karim',   null,       null,                      10, 40, 'A', 'evening', 1),
  ('d_rehman',     'c_rehman',      'Dr. Abdul Rehman',  'generalPhysician', 'abdul rehman',  null,       null,                      10, 40, 'A', 'evening', 1),
  ('d_zara',       'c_clifton',     'Dr. Zara Hussain',  'generalPhysician', 'zara hussain',  null,       null,                      10, 40, 'A', 'long',    1),
  ('d_omar',       'c_capital',     'Dr. Omar Farooq',   'heart',            'omar farooq',   null,       null,                      15, 40, 'A', 'late',    1)
) as v (id, clinic_id, name, speciality, name_key, grp, qual, avg, max, prefix, sched, sort)
join public.clinics c on c.id = v.clinic_id
on conflict (id) do update set
  name = excluded.name, speciality = excluded.speciality, city = excluded.city, name_key = excluded.name_key,
  doctor_group_id = excluded.doctor_group_id, qualification = excluded.qualification,
  avg_consult_minutes = excluded.avg_consult_minutes, max_tokens_per_day = excluded.max_tokens_per_day,
  schedule = excluded.schedule, sort_order = excluded.sort_order;

-- The same-doctor pair is already linked (D-32 demo).
insert into public.doctor_link_suggestions (id, doctor_ids, clinic_ids, strength, status, decided_at)
values ('d_ayesha_d_ayesha_dha', '{d_ayesha,d_ayesha_dha}', '{c_alshifa,c_dha}', 'weak', 'linked', now())
on conflict (id) do nothing;

update public.clinics c set
  doctor_count = (select count(*) from public.doctors d where d.clinic_id = c.id and d.active),
  next_doctor_letter = (select count(*) from public.doctors d where d.clinic_id = c.id);
